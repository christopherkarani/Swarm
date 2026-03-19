import Foundation
import Testing
@testable import Swarm

actor CertifiedTextOnlyProvider: InferenceProvider {
    enum Mode: Sendable {
        case alwaysToolEnvelope
        case toolThenAnswer
        case toolThenStructuredAnswer(String)
        case finalAnswer(String)
    }

    private let mode: Mode
    private var prompts: [String] = []
    private var invocationCount: Int = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func generate(prompt: String, options _: InferenceOptions) async throws -> String {
        prompts.append(prompt)
        invocationCount += 1

        switch mode {
        case .alwaysToolEnvelope:
            return toolEnvelopeResponse(for: prompt)
        case .toolThenAnswer:
            if invocationCount == 1 {
                return toolEnvelopeResponse(for: prompt)
            }
            return "Final answer: HELLO"
        case .toolThenStructuredAnswer(let answer):
            if invocationCount == 1 {
                return toolEnvelopeResponse(for: prompt)
            }
            return answer
        case .finalAnswer(let answer):
            return answer
        }
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        Task {
            do {
                let response = try await generate(prompt: prompt, options: options)
                continuation.yield(response)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    func recordedPrompts() -> [String] {
        prompts
    }

    private func toolEnvelopeResponse(for prompt: String) -> String {
        let nonce = extractNonce(from: prompt) ?? "missing-nonce"
        return """
        {"swarm_tool_call": {"nonce": "\(nonce)", "tool": "string", "arguments": {"operation": "uppercase", "input": "hello"}}}
        """
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

final class CertifiedPromptToolStreamingProvider: @preconcurrency ToolCallStreamingInferenceProvider,
    CapabilityReportingInferenceProvider,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let scripts: [[InferenceStreamUpdate]]
    private var index: Int = 0

    let capabilities: InferenceProviderCapabilities

    init(
        scripts: [[InferenceStreamUpdate]],
        capabilities: InferenceProviderCapabilities = [.streamingToolCalls]
    ) {
        self.scripts = scripts
        self.capabilities = capabilities
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        throw AgentError.generationFailed(reason: "Unexpected call to generate() in certification fixture")
    }

    func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.generationFailed(reason: "Unexpected call to stream() in certification fixture"))
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        throw AgentError.generationFailed(reason: "Expected streaming tool-call path in certification fixture")
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

    private func nextScript() -> [InferenceStreamUpdate] {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        return scripts[min(index, scripts.count - 1)]
    }
}

enum ProviderCertificationHarness {
    struct TranscriptReplayOutcome: Sendable {
        let transcript: SwarmTranscript
        let replayMessages: [InferenceMessage]
    }

    static func certifyTextOnlyToolLoop(using provider: any InferenceProvider) async throws -> AgentResult {
        let agent = try Agent(
            tools: [StringTool()],
            instructions: "Use tools when helpful.",
            inferenceProvider: provider
        )

        let result = try await agent.run("Uppercase hello.")
        #expect(result.output == "Final answer: HELLO")
        return result
    }

    static func certifyMalformedToolArguments(using provider: any InferenceProvider) async throws -> AgentError {
        let agent = try Agent(
            tools: [StringTool()],
            configuration: .default.maxIterations(2).stopOnToolError(true),
            inferenceProvider: provider
        )

        do {
            _ = try await agent.run("Use the string tool.")
            Issue.record("Expected malformed tool arguments to fail")
            return .internalError(reason: "Malformed tool arguments unexpectedly succeeded")
        } catch let error as AgentError {
            return error
        }
    }

    static func certifyPromptToolCallStreaming(using provider: any InferenceProvider) async throws -> [AgentEvent] {
        let agent = try Agent(
            tools: [StringTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        var events: [AgentEvent] = []
        for try await event in agent.stream("Uppercase hello.") {
            events.append(event)
        }

        let partialIndex = events.firstIndex { event in
            if case .tool(.partial) = event { return true }
            return false
        }
        let startedIndex = events.firstIndex { event in
            if case .tool(.started) = event { return true }
            return false
        }

        #expect(partialIndex != nil)
        #expect(startedIndex != nil)
        if let partialIndex, let startedIndex {
            #expect(partialIndex < startedIndex)
        }

        if let completedEvent = events.last(where: { if case .lifecycle(.completed) = $0 { true } else { false } }),
           case let .lifecycle(.completed(result: result)) = completedEvent
        {
            #expect(result.output == "All done")
            #expect(result.toolCalls.first?.toolName == "string")
        } else {
            Issue.record("Missing expected completed event in provider certification stream")
        }

        return events
    }

    static func runTwoTurnsWithAutoContinuation(using provider: any InferenceProvider) async throws -> (AgentResponse, AgentResponse) {
        let session = InMemorySession(sessionId: "provider-certification-\(UUID().uuidString)")
        let agent = try Agent(
            configuration: .default.autoPreviousResponseId(true),
            inferenceProvider: provider
        )

        let first = try await agent.runWithResponse("first prompt", session: session, observer: nil)
        let second = try await agent.runWithResponse("second prompt", session: session, observer: nil)
        return (first, second)
    }

    static func certifyTranscriptReplay(
        using provider: any InferenceProvider,
        backing backingProvider: MockInferenceProvider
    ) async throws -> TranscriptReplayOutcome {
        let session = InMemorySession(sessionId: "provider-transcript-\(UUID().uuidString)")
        let agent = try Agent(
            tools: [StringTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        await backingProvider.setToolCallResponses([
            InferenceResponse(
                content: "Calling string",
                toolCalls: [
                    .init(
                        id: "call_1",
                        name: "string",
                        arguments: [
                            "operation": .string("uppercase"),
                            "input": .string("hello"),
                        ]
                    ),
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "Final answer: HELLO", finishReason: .completed),
            InferenceResponse(content: "Second turn ready", finishReason: .completed),
        ])

        _ = try await agent.run("Uppercase hello.", session: session)
        _ = try await agent.run("Continue.", session: session)

        let transcript = SwarmTranscript(memoryMessages: try await session.getAllItems())
        try transcript.validateReplayCompatibility()

        let messageCalls = await backingProvider.toolCallMessageCalls
        let replayMessages = try #require(messageCalls.last?.messages)
        return TranscriptReplayOutcome(transcript: transcript, replayMessages: replayMessages)
    }

    static func certifyTimeout(using provider: any InferenceProvider) async throws -> AgentError {
        let agent = try Agent(
            configuration: .default.timeout(.milliseconds(50)),
            inferenceProvider: provider
        )

        do {
            _ = try await agent.run("This should time out.")
            Issue.record("Expected timeout but run completed successfully")
            return .internalError(reason: "Timeout unexpectedly succeeded")
        } catch let error as AgentError {
            return error
        }
    }

    static func certifyCancellation(using provider: any InferenceProvider) async throws -> AgentError {
        let agent = try Agent(inferenceProvider: provider)
        let task = Task {
            try await agent.run("Please wait.")
        }

        try await Task.sleep(for: .milliseconds(50))
        await agent.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation but run completed successfully")
            return .internalError(reason: "Cancellation unexpectedly succeeded")
        } catch let error as AgentError {
            return error
        }
    }
}
