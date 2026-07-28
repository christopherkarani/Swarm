import Foundation
import Testing
@testable import Swarm

@Suite("Agent Live Tool Call Streaming")
struct AgentLiveToolCallStreamingTests {
    @Test("Emits toolCallPartial before toolCallStarted when provider streams tool-call assembly")
    func emitsPartialUpdatesBeforeToolExecution() async throws {
        struct EchoTool: AnyJSONTool, Sendable {
            let name = "echo"
            let description = "Echoes the input text"
            let parameters: [ToolParameter] = [
                ToolParameter(name: "text", description: "Text to echo", type: .string)
            ]

            func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                .string(try requiredString("text", from: arguments))
            }
        }

        // NOTE: Do not implement this as an actor. `ToolCallStreamingInferenceProvider.streamWithToolCalls`
        // is a synchronous protocol requirement, and calling it through an existential can bypass actor
        // isolation hops, triggering "Incorrect actor executor assumption" crashes at runtime.
        final class ScriptedStreamingProvider: ToolCallStreamingInferenceProvider, @unchecked Sendable {
            private let lock = NSLock()
            private var scripts: [[InferenceStreamUpdate]]
            private var index: Int = 0

            init(scripts: [[InferenceStreamUpdate]]) {
                self.scripts = scripts
            }

            private func nextScript() -> [InferenceStreamUpdate] {
                lock.lock()
                defer { lock.unlock() }
                defer { index += 1 }
                return scripts[min(index, scripts.count - 1)]
            }

            func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
                throw AgentError.generationFailed(reason: "Unexpected call to generate() in streaming test")
            }

            func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
                StreamHelper.makeTrackedStream { continuation in
                    continuation.finish(throwing: AgentError.generationFailed(reason: "Unexpected call to stream() in streaming test"))
                }
            }

            func generateWithToolCalls(
                prompt _: String,
                tools _: [ToolSchema],
                options _: InferenceOptions
            ) async throws -> InferenceResponse {
                throw AgentError.generationFailed(reason: "Unexpected call to generateWithToolCalls() in streaming test")
            }

            func streamWithToolCalls(
                prompt _: String,
                tools _: [ToolSchema],
                options _: InferenceOptions
            ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
                StreamHelper.makeTrackedStream { continuation in
                    let updates = self.nextScript()
                    for update in updates {
                        continuation.yield(update)
                    }
                    continuation.finish()
                }
            }

            func callCount() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return index
            }
        }

        let partial1 = PartialToolCallUpdate(
            providerCallId: "call_1",
            toolName: "echo",
            index: 0,
            argumentsFragment: #"{"text":"#
        )
        let partial2 = PartialToolCallUpdate(
            providerCallId: "call_1",
            toolName: "echo",
            index: 0,
            argumentsFragment: #"{"text":"hi"}"#
        )
        let completed = [
            InferenceResponse.ParsedToolCall(id: "call_1", name: "echo", arguments: ["text": .string("hi")])
        ]

        let provider = ScriptedStreamingProvider(scripts: [
            [
                .toolCallPartial(partial1),
                .toolCallPartial(partial2),
                .usage(.init(inputTokens: 1, outputTokens: 1)),
                .toolCallsCompleted(completed),
            ],
            [
                .outputChunk("All done"),
                .usage(.init(inputTokens: 1, outputTokens: 1)),
            ],
        ])

        let agent = try Agent(
            tools: [EchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        var events: [AgentEvent] = []
        for try await event in agent.stream("Hi") {
            events.append(event)
        }

        let partialIndex = events.firstIndex { event in
            if case .tool(.partial) = event { return true }
            return false
        }
        let toolStartIndex = events.firstIndex { event in
            if case .tool(.started) = event { return true }
            return false
        }

        #expect(partialIndex != nil)
        #expect(toolStartIndex != nil)
        if let partialIndex, let toolStartIndex {
            #expect(partialIndex < toolStartIndex)
        }

        if let idx = toolStartIndex,
           case let .tool(.started(call: call)) = events[idx]
        {
            #expect(call.providerCallId == "call_1")
            #expect(call.toolName == "echo")
        } else {
            Issue.record("Missing expected tool(.started) event")
        }

        if let completedEvent = events.last(where: { if case .lifecycle(.completed) = $0 { true } else { false } }),
           case let .lifecycle(.completed(result: result)) = completedEvent
        {
            #expect(result.output == "All done")
            #expect(result.toolCalls.first?.providerCallId == "call_1")
        } else {
            Issue.record("Missing expected completed event")
        }

        let count = provider.callCount()
        #expect(count == 2)
    }

    @Test("Uses tool-call streaming when inferenceProvider conforms to ToolCallStreamingInferenceProvider")
    func usesToolCallStreamingThroughStreamingProvider() async throws {
        struct EchoTool: AnyJSONTool, Sendable {
            let name = "echo"
            let description = "Echoes the input text"
            let parameters: [ToolParameter] = [
                ToolParameter(name: "text", description: "Text to echo", type: .string)
            ]

            func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                .string(try requiredString("text", from: arguments))
            }
        }

        // See note in the test above: this must not be an actor.
        final class ScriptedStreamingProvider: ToolCallStreamingInferenceProvider, @unchecked Sendable {
            private let lock = NSLock()
            private var scripts: [[InferenceStreamUpdate]]
            private var index: Int = 0

            init(scripts: [[InferenceStreamUpdate]]) {
                self.scripts = scripts
            }

            private func nextScript() -> [InferenceStreamUpdate] {
                lock.lock()
                defer { lock.unlock() }
                defer { index += 1 }
                return scripts[min(index, scripts.count - 1)]
            }

            func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
                throw AgentError.generationFailed(reason: "Unexpected call to generate() in streaming test")
            }

            func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
                StreamHelper.makeTrackedStream { continuation in
                    continuation.finish(throwing: AgentError.generationFailed(reason: "Unexpected call to stream() in streaming test"))
                }
            }

            func generateWithToolCalls(
                prompt _: String,
                tools _: [ToolSchema],
                options _: InferenceOptions
            ) async throws -> InferenceResponse {
                // If Agent falls back to the non-streaming path, this is called (and the test should fail).
                throw AgentError.generationFailed(reason: "Expected Agent to use streamWithToolCalls(), but it called generateWithToolCalls()")
            }

            func streamWithToolCalls(
                prompt _: String,
                tools _: [ToolSchema],
                options _: InferenceOptions
            ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
                StreamHelper.makeTrackedStream { continuation in
                    let updates = self.nextScript()
                    for update in updates {
                        continuation.yield(update)
                    }
                    continuation.finish()
                }
            }
        }

        let partial = PartialToolCallUpdate(
            providerCallId: "call_1",
            toolName: "echo",
            index: 0,
            argumentsFragment: #"{"text":"hi"}"#
        )
        let completed = [
            InferenceResponse.ParsedToolCall(id: "call_1", name: "echo", arguments: ["text": .string("hi")])
        ]

        let provider = ScriptedStreamingProvider(scripts: [
            [
                .toolCallPartial(partial),
                .toolCallsCompleted(completed),
            ],
            [
                .outputChunk("All done"),
            ],
        ])

        let agent = try Agent(
            tools: [EchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        var events: [AgentEvent] = []
        for try await event in agent.stream("Hi") {
            events.append(event)
        }

        #expect(events.contains { event in
            if case .tool(.partial) = event { return true }
            return false
        })
    }
}
