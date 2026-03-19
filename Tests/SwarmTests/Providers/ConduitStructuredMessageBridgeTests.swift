import Conduit
import Testing
@testable import Swarm

@Suite("Conduit Structured Message Bridge")
struct ConduitStructuredMessageBridgeTests {
    @Test("Bridges assistant tool calls and tool outputs into Conduit messages")
    func bridgesStructuredMessages() async throws {
        struct MockModelID: Conduit.ModelIdentifying {
            let rawValue: String
            var displayName: String { rawValue }
            var provider: Conduit.ProviderType { .openAI }
            var description: String { rawValue }
            init(_ rawValue: String) { self.rawValue = rawValue }
        }

        final class MessageBox: @unchecked Sendable {
            var lastMessages: [Conduit.Message]?
        }

        struct CapturingTextGenerator: Conduit.TextGenerator {
            typealias ModelID = MockModelID

            let box: MessageBox

            func generate(_ prompt: String, model _: ModelID, config _: Conduit.GenerateConfig) async throws -> String {
                prompt
            }

            func generate(
                messages: [Conduit.Message],
                model _: ModelID,
                config _: Conduit.GenerateConfig
            ) async throws -> Conduit.GenerationResult {
                box.lastMessages = messages
                return Conduit.GenerationResult(
                    text: "ok",
                    tokenCount: 0,
                    generationTime: 0,
                    tokensPerSecond: 0,
                    finishReason: .stop
                )
            }

            func stream(_ prompt: String, model _: ModelID, config _: Conduit.GenerateConfig) -> AsyncThrowingStream<String, Error> {
                StreamHelper.makeTrackedStream { continuation in
                    continuation.finish()
                }
            }

            func streamWithMetadata(
                messages _: [Conduit.Message],
                model _: ModelID,
                config _: Conduit.GenerateConfig
            ) -> AsyncThrowingStream<Conduit.GenerationChunk, Error> {
                StreamHelper.makeTrackedStream { continuation in
                    continuation.finish()
                }
            }
        }

        let box = MessageBox()
        let provider = CapturingTextGenerator(box: box)
        let bridge = ConduitInferenceProvider(provider: provider, model: MockModelID("mock"))

        let messages: [InferenceMessage] = [
            .system("You are helpful."),
            .user("Check the weather."),
            .assistant(
                "Calling weather",
                toolCalls: [
                    .init(id: "call_1", name: "weather", arguments: ["city": "SF"])
                ]
            ),
            .tool(name: "weather", content: "72F and sunny", toolCallID: "call_1"),
        ]

        let result = try await bridge.generate(messages: messages, options: .default)

        #expect(result == "ok")

        let captured = box.lastMessages
        #expect(captured?.count == 4)
        #expect(captured?[0].role == .system)
        #expect(captured?[1].role == .user)
        #expect(captured?[2].role == .assistant)
        #expect(captured?[2].metadata?.toolCalls?.first?.id == "call_1")
        #expect(captured?[2].metadata?.toolCalls?.first?.toolName == "weather")
        #expect(captured?[2].metadata?.toolCalls?.first?.argumentsString == #"{"city":"SF"}"#)
        #expect(captured?[3].role == .tool)
        #expect(captured?[3].metadata?.custom?["tool_call_id"] == "call_1")
        #expect(captured?[3].metadata?.custom?["tool_name"] == "weather")
        #expect(captured?[3].content.textValue == "72F and sunny")
    }
}
