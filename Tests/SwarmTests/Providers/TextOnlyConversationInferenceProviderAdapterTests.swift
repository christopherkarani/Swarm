import Foundation
@testable import Swarm
import Testing

@Suite("Text-Only Inference Provider Adapter", .ephemeralDefaultStores)
struct TextOnlyConversationInferenceProviderAdapterTests {

    @Test("Default tool-calling emulation works for plain inference providers")
    func defaultToolCallingEmulationWorksForPlainProviders() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .alwaysToolEnvelope)

        let response = try await provider.generateWithToolCalls(
            prompt: "Use the string tool to uppercase hello.",
            tools: [StringTool().schema],
            options: .default
        )

        #expect(response.finishReason == .toolCall)
        let toolCall = try #require(response.toolCalls.first)
        #expect(toolCall.name == "string")
        #expect(toolCall.arguments["operation"] == .string("uppercase"))
        #expect(toolCall.arguments["input"] == .string("hello"))
    }

    @Test("Text-only conversation adapter flattens structured history for plain providers")
    func textOnlyConversationAdapterFlattensStructuredHistory() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .finalAnswer("ok"))
        let adapter = TextOnlyConversationInferenceProviderAdapter.textOnly(provider)

        let output = try await adapter.generate(
            messages: [
                .system("system instructions"),
                .user("hello")
            ],
            options: .default
        )

        #expect(output == "ok")
        let prompts = await provider.recordedPrompts()
        #expect(prompts.count == 1)
        #expect(prompts[0] == """
        [System]: system instructions

        [User]: hello
        """)
    }

    @Test("Flattened history is labeled and lossless-by-construction")
    func flattenedHistoryIsLabeledAndLossless() {
        let messages: [InferenceMessage] = [
            .system("system instructions"),
            .user("hello"),
            .assistant(
                "calling",
                toolCalls: [.init(id: "1", name: "echo", arguments: ["text": .string("hi")])]
            ),
            .tool(name: "echo", content: "hi", toolCallID: "1"),
        ]

        let flattened = TextOnlyConversationInferenceProviderAdapter.prompt(from: messages)
        #expect(flattened == """
        [System]: system instructions

        [User]: hello

        [Assistant]: calling
        [Assistant Tool Calls]: Calling tool: echo

        [Tool Result - echo]: hi
        """)
    }

    @Test("Text-only conversation adapter strips streaming tool-call capability")
    func textOnlyConversationAdapterStripsStreamingToolCallCapability() {
        let provider = ReportingTextBackend(capabilities: [.streamingToolCalls, .responseContinuation])
        let adapter = TextOnlyConversationInferenceProviderAdapter.textOnly(provider)

        let capabilities = adapter.capabilities

        #expect(capabilities.contains(.conversationMessages))
        #expect(capabilities.contains(.responseContinuation))
        #expect(capabilities.contains(.streamingToolCalls) == false)
    }

    @Test("Messages-only providers emulate tool calling without flattening history")
    func messagesOnlyProvidersEmulateToolCallingWithoutFlattening() async throws {
        let provider = MessagesOnlyEmulationProvider()
        let agent = try Agent(
            tools: [StringTool()],
            instructions: "Use tools when helpful.",
            inferenceProvider: provider
        )

        let result = try await agent.run("Uppercase hello.")

        #expect(result.output == "Final answer: HELLO")
        let calls = await provider.recordedMessageCalls()
        #expect(calls.count == 2)
        #expect(calls[0].contains { $0.role == .user && $0.content.contains("Uppercase") })
        #expect(calls[0].contains { $0.role == .system && $0.content.contains("\"swarm_tool_call\"") })
        #expect(calls[1].contains { $0.role == .tool })
        #expect(calls.allSatisfy { turn in
            !turn.contains { $0.content.contains("[User]:") }
        })
    }

    @Test("Four-argument default still forwards to a native three-argument override")
    func fourArgumentDefaultForwardsToNativeThreeArgumentOverride() async throws {
        let provider = NativeThreeArgProvider()
        let response = try await provider.generateWithToolCalls(
            messages: [.user("hi")],
            tools: [StringTool().schema],
            options: .default,
            toolExecutor: ToolCallExecutor { _, _ in .string("unused") }
        )
        #expect(response.content == "native")
    }
}

private struct ReportingTextBackend: TextOnlyBackend {
    let capabilities: InferenceProviderCapabilities

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "ok"
    }
}

private actor MessagesOnlyEmulationProvider: InferenceProvider {
    private var invocationCount = 0
    private var calls: [[InferenceMessage]] = []

    func recordedMessageCalls() -> [[InferenceMessage]] {
        calls
    }

    func generate(messages: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        calls.append(messages)
        invocationCount += 1
        if invocationCount == 1 {
            let blob = messages.map(\.content).joined(separator: "\n")
            let nonce = extractNonce(from: blob) ?? "missing-nonce"
            return """
            {"swarm_tool_call": {"nonce": "\(nonce)", "tool": "string", "arguments": {"operation": "uppercase", "input": "hello"}}}
            """
        }
        return "Final answer: HELLO"
    }

    private func extractNonce(from prompt: String) -> String? {
        let marker = #""swarm_tool_call": {"nonce": ""#
        guard let range = prompt.range(of: marker) else {
            return nil
        }
        let nonceStart = range.upperBound
        guard let nonceEnd = prompt[nonceStart...].firstIndex(of: "\"") else {
            return nil
        }
        return String(prompt[nonceStart..<nonceEnd])
    }
}

private struct NativeThreeArgProvider: InferenceProvider {
    func generate(messages _: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        "should-not-run"
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: "native", finishReason: .completed)
    }
}
