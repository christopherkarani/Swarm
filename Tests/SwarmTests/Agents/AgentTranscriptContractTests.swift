import Foundation
import Testing
@testable import Swarm

private struct TranscriptEchoTool: AnyJSONTool {
    let name = "echo"
    let description = "Echoes the provided message"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "message", description: "Message to echo", type: .string),
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .string(arguments["message"]?.stringValue ?? "")
    }
}

private actor NativeStructuredConversationProvider:
    InferenceProvider,
    ConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    CapabilityReportingInferenceProvider
{
    nonisolated let capabilities: InferenceProviderCapabilities = [.conversationMessages, .structuredOutputs]

    private let structuredResult: StructuredOutputResult
    private var structuredCalls: [([InferenceMessage], StructuredOutputRequest)] = []

    init(structuredResult: StructuredOutputResult) {
        self.structuredResult = structuredResult
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        structuredResult.rawJSON
    }

    nonisolated func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AgentError.internalError(reason: "Unexpected streaming call"))
        }
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options _: InferenceOptions
    ) async throws -> StructuredOutputResult {
        structuredCalls.append((messages, request))
        return structuredResult
    }

    func recordedStructuredCalls() -> [([InferenceMessage], StructuredOutputRequest)] {
        structuredCalls
    }
}

private func metadataString(
    _ key: String,
    from metadata: [String: SendableValue]
) -> String? {
    metadata[key]?.stringValue
}

@Suite("Agent Transcript Contract")
struct AgentTranscriptContractTests {
    @Test("runStructured uses prompt fallback and persists structured transcript metadata")
    func runStructuredPromptFallbackPersistsTranscriptMetadata() async throws {
        let provider = MockInferenceProvider(responses: [#"{"answer":"ok"}"#])
        let session = InMemorySession(sessionId: "structured-prompt-fallback")
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )
        let request = StructuredOutputRequest(format: .jsonObject)

        let result = try await agent.runStructured("Return a JSON answer.", request: request, session: session)

        #expect(result.agentResult.output == #"{"answer":"ok"}"#)
        #expect(result.structuredOutput.rawJSON == #"{"answer":"ok"}"#)
        #expect(result.structuredOutput.source == .promptFallback)
        #expect(metadataString("structured_output.raw_json", from: result.agentResult.metadata) == #"{"answer":"ok"}"#)
        #expect(metadataString("structured_output.source", from: result.agentResult.metadata) == "prompt_fallback")
        #expect(metadataString("structured_output.format", from: result.agentResult.metadata) == "json_object")
        #expect(metadataString("swarm.transcript.schema_version", from: result.agentResult.metadata) == SwarmTranscriptSchemaVersion.current.rawValue)

        let messageCalls = await provider.generateMessageCalls
        #expect(messageCalls.count == 1)
        #expect(messageCalls.first?.messages.last?.content.contains("Respond with valid JSON only.") == true)

        let storedMessages = try await session.getAllItems()
        #expect(storedMessages.count == 2)
        #expect(storedMessages.allSatisfy {
            $0.metadata["swarm.transcript.schema_version"] == SwarmTranscriptSchemaVersion.current.rawValue
        })

        let transcript = SwarmTranscript(memoryMessages: storedMessages)
        try transcript.validateReplayCompatibility()
        #expect(transcript.entries.last?.structuredOutput?.result == result.structuredOutput)
        #expect(try transcript.transcriptHash().isEmpty == false)
    }

    @Test("runStructured prefers native structured conversation providers")
    func runStructuredPrefersNativeStructuredConversationProviders() async throws {
        let structuredResult = StructuredOutputResult(
            format: .jsonSchema(
                name: "Answer",
                schemaJSON: #"{"type":"object","properties":{"answer":{"type":"string"}},"required":["answer"]}"#
            ),
            rawJSON: #"{"answer":"native"}"#,
            value: .dictionary(["answer": .string("native")]),
            source: .providerNative
        )
        let provider = NativeStructuredConversationProvider(structuredResult: structuredResult)
        let session = InMemorySession(sessionId: "structured-native")
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )
        let request = StructuredOutputRequest(format: structuredResult.format)

        let result = try await agent.runStructured("Return native JSON.", request: request, session: session)

        #expect(result.agentResult.output == structuredResult.rawJSON)
        #expect(result.structuredOutput == structuredResult)
        #expect(metadataString("structured_output.source", from: result.agentResult.metadata) == "provider_native")
        #expect(metadataString("structured_output.format", from: result.agentResult.metadata) == "json_schema:Answer")

        let calls = await provider.recordedStructuredCalls()
        #expect(calls.count == 1)
        #expect(calls.first?.0.last == .user("Return native JSON."))

        let transcript = SwarmTranscript(memoryMessages: try await session.getAllItems())
        try transcript.validateReplayCompatibility()
        #expect(transcript.entries.last?.structuredOutput?.result.source == .providerNative)
    }

    @Test("InMemorySession branch keeps transcript replay-compatible and isolated")
    func inMemorySessionBranchKeepsTranscriptReplayCompatible() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: "Calling echo",
                toolCalls: [
                    .init(id: "call_1", name: "echo", arguments: ["message": "hello"])
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "done", finishReason: .completed),
        ])

        let session = InMemorySession(sessionId: "transcript-branch-in-memory")
        let agent = try Agent(
            tools: [TranscriptEchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )
        _ = try await agent.run("Echo hello.", session: session)

        let originalMessages = try await session.getAllItems()
        let originalTranscript = SwarmTranscript(memoryMessages: originalMessages)
        try originalTranscript.validateReplayCompatibility()
        let originalHash = try originalTranscript.transcriptHash()

        let branchedSession = try await session.branchConversationSession()
        let branchedMessages = try await branchedSession.getAllItems()
        let branchedTranscript = SwarmTranscript(memoryMessages: branchedMessages)
        try branchedTranscript.validateReplayCompatibility()

        #expect(branchedTranscript.firstDiff(comparedTo: originalTranscript) == nil)
        #expect(try branchedTranscript.transcriptHash() == originalHash)

        let replayProvider = MockInferenceProvider(responses: ["branch reply"])
        let replayAgent = try Agent(inferenceProvider: replayProvider)
        _ = try await replayAgent.run("Continue in branch.", session: branchedSession)

        #expect(try await session.getAllItems().count == originalMessages.count)
        #expect(try await branchedSession.getAllItems().count == originalMessages.count + 2)
    }
}

#if canImport(SwiftData)
@Suite("Persistent Transcript Contract")
struct PersistentTranscriptContractTests {
    @Test("PersistentSession in-memory branch keeps transcript replay-compatible")
    func persistentSessionBranchKeepsTranscriptReplayCompatible() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: "Calling echo",
                toolCalls: [
                    .init(id: "call_1", name: "echo", arguments: ["message": "persisted"])
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "done", finishReason: .completed),
        ])

        let session = try PersistentSession.inMemory(sessionId: "transcript-branch-persistent")
        let agent = try Agent(
            tools: [TranscriptEchoTool()],
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )
        _ = try await agent.run("Echo persisted.", session: session)

        let originalTranscript = SwarmTranscript(memoryMessages: try await session.getAllItems())
        try originalTranscript.validateReplayCompatibility()

        let branchedSession = try await session.branchConversationSession()
        let branchedTranscript = SwarmTranscript(memoryMessages: try await branchedSession.getAllItems())
        try branchedTranscript.validateReplayCompatibility()

        #expect(branchedTranscript.firstDiff(comparedTo: originalTranscript) == nil)

        let replayProvider = MockInferenceProvider(responses: ["persistent branch"])
        let replayAgent = try Agent(inferenceProvider: replayProvider)
        _ = try await replayAgent.run("Continue persisted branch.", session: branchedSession)

        #expect(try await branchedSession.getAllItems().count == originalTranscript.entries.count + 2)
        #expect(try await session.getAllItems().count == originalTranscript.entries.count)
    }
}
#endif
