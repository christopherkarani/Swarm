import Testing
@testable import Swarm

@Suite("Inference Provider Capability Contract")
struct InferenceProviderCapabilityContractTests {
    @Test("Resolved capabilities trust explicit reporting while preserving conversation support")
    func resolvedCapabilitiesPreferExplicitReporting() {
        let provider = MockInferenceProvider(
            responses: ["ok"],
            capabilities: [.responseContinuation]
        )

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)

        #expect(capabilities == [.conversationMessages, .responseContinuation])
    }

    @Test("Text-only conversation adapter strips streaming tool-call capability")
    func textOnlyAdapterStripsStreamingToolCalls() {
        let base = CertifiedPromptToolStreamingProvider(
            scripts: [[]],
            capabilities: [.streamingToolCalls, .responseContinuation]
        )
        let adapter = TextOnlyConversationInferenceProviderAdapter(base: base)

        #expect(adapter.capabilities.contains(.conversationMessages))
        #expect(adapter.capabilities.contains(.streamingToolCalls) == false)
        #expect(adapter.capabilities.contains(.responseContinuation))
        #expect(adapter.capabilities.contains(.nativeToolCalling) == false)
    }

    @Test("MockInferenceProvider reports conversation support and explicit capabilities")
    func mockProviderReportsConversationAndExplicitCapabilities() {
        let provider = MockInferenceProvider(
            responses: ["ok"],
            capabilities: [.responseContinuation]
        )

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        #expect(capabilities.contains(.conversationMessages))
        #expect(capabilities.contains(.responseContinuation))
    }

    @Test("MultiProvider capabilities follow the selected route while preserving wrapper conversation support")
    func multiProviderCapabilitiesFollowSelectedRoute() async throws {
        let defaultProvider = CertifiedTextOnlyProvider(mode: .finalAnswer("ok"))
        let continuationProvider = MockInferenceProvider(
            responses: ["first", "second"],
            capabilities: [.responseContinuation]
        )
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        #expect(multiProvider.capabilities == [.conversationMessages])

        try await multiProvider.register(prefix: "mock", provider: continuationProvider)
        #expect(multiProvider.capabilities == [.conversationMessages])

        await multiProvider.setModel("mock/model")
        #expect(multiProvider.capabilities == [.conversationMessages, .responseContinuation])
    }
}

@Suite("Inference Provider Certification")
struct InferenceProviderCertificationTests {
    @Test("Mock provider passes text-only tool emulation certification")
    func mockProviderCertifiesTextOnlyToolEmulation() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .toolThenAnswer)

        _ = try await ProviderCertificationHarness.certifyTextOnlyToolLoop(using: provider)

        let prompts = await provider.recordedPrompts()
        #expect(prompts.count == 2)
        #expect(prompts[0].contains("\"swarm_tool_call\""))
        #expect(prompts[1].contains("[Tool Result - string]: HELLO"))
    }

    @Test("MultiProvider selected route passes text-only tool emulation certification")
    func multiProviderCertifiesSelectedTextOnlyToolEmulation() async throws {
        let defaultProvider = CertifiedTextOnlyProvider(mode: .finalAnswer("default"))
        let selectedProvider = CertifiedTextOnlyProvider(mode: .toolThenAnswer)
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        try await multiProvider.register(prefix: "local", provider: selectedProvider)
        await multiProvider.setModel("local/mock")

        _ = try await ProviderCertificationHarness.certifyTextOnlyToolLoop(using: multiProvider)

        let prompts = await selectedProvider.recordedPrompts()
        #expect(prompts.count == 2)
        #expect(prompts[0].contains("\"swarm_tool_call\""))
        #expect(prompts[1].contains("[Tool Result - string]: HELLO"))
    }

    @Test("MockInferenceProvider forwards auto continuation")
    func mockProviderForwardsAutoContinuation() async throws {
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )

        let (first, _) = try await ProviderCertificationHarness.runTwoTurnsWithAutoContinuation(using: provider)
        let calls = await provider.generateMessageCalls

        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == first.responseId)
        }
    }

    @Test("MultiProvider selected route forwards auto continuation")
    func multiProviderForwardsAutoContinuationOnSelectedRoute() async throws {
        let defaultProvider = CertifiedTextOnlyProvider(mode: .finalAnswer("default"))
        let selectedProvider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)
        try await multiProvider.register(prefix: "mock", provider: selectedProvider)
        await multiProvider.setModel("mock/model")

        let (first, _) = try await ProviderCertificationHarness.runTwoTurnsWithAutoContinuation(using: multiProvider)
        let calls = await selectedProvider.generateMessageCalls

        #expect(calls.count == 2)
        if calls.count == 2 {
            #expect(calls[0].options.previousResponseId == nil)
            #expect(calls[1].options.previousResponseId == first.responseId)
        }
    }

    @Test("Mock providers fail malformed native tool arguments safely")
    func mockProvidersFailMalformedToolArgumentsSafely() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    .init(id: "call_1", name: "string", arguments: ["input": "hello"])
                ],
                finishReason: .toolCall
            )
        ])

        let error = try await ProviderCertificationHarness.certifyMalformedToolArguments(using: provider)

        if case let .toolExecutionFailed(toolName, underlyingError) = error {
            #expect(toolName == "string")
            #expect(underlyingError.contains("operation"))
        } else {
            Issue.record("Expected toolExecutionFailed for malformed tool arguments, got: \(error)")
        }
    }

    @Test("MultiProvider selected route preserves prompt tool-call streaming assembly")
    func multiProviderCertifiesPromptToolCallStreaming() async throws {
        let partial = PartialToolCallUpdate(
            providerCallId: "call_1",
            toolName: "string",
            index: 0,
            argumentsFragment: #"{"operation":"uppercase","input":"hello"}"#
        )
        let completed = [
            InferenceResponse.ParsedToolCall(
                id: "call_1",
                name: "string",
                arguments: ["operation": .string("uppercase"), "input": .string("hello")]
            )
        ]

        let defaultProvider = CertifiedTextOnlyProvider(mode: .finalAnswer("default"))
        let selectedProvider = CertifiedPromptToolStreamingProvider(scripts: [
            [
                .toolCallPartial(partial),
                .toolCallsCompleted(completed),
            ],
            [
                .outputChunk("All done"),
            ],
        ])
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)
        try await multiProvider.register(prefix: "stream", provider: selectedProvider)
        await multiProvider.setModel("stream/mock")

        let events = try await ProviderCertificationHarness.certifyPromptToolCallStreaming(using: multiProvider)

        #expect(events.contains { event in
            if case .tool(.partial) = event { return true }
            return false
        })
    }

    @Test("MockInferenceProvider preserves transcript replay compatibility")
    func mockProviderCertifiesTranscriptReplay() async throws {
        let provider = MockInferenceProvider()

        let outcome = try await ProviderCertificationHarness.certifyTranscriptReplay(
            using: provider,
            backing: provider
        )

        #expect(outcome.transcript.schemaVersion == .current)
        #expect(outcome.transcript.entries.contains { entry in
            entry.role == .assistant && entry.toolCalls.first?.id == "call_1"
        })
        #expect(outcome.transcript.entries.contains { entry in
            entry.role == .tool && entry.toolCallID == "call_1" && entry.toolName == "string"
        })

        let replayAssistant = outcome.replayMessages.first { message in
            message.role == .assistant && message.toolCalls.first?.id == "call_1"
        }
        let replayTool = outcome.replayMessages.first { $0.role == .tool }
        #expect(replayAssistant != nil)
        #expect(replayTool?.toolCallID == "call_1")
    }

    @Test("MultiProvider selected route preserves transcript replay compatibility")
    func multiProviderCertifiesTranscriptReplay() async throws {
        let defaultProvider = CertifiedTextOnlyProvider(mode: .finalAnswer("default"))
        let selectedProvider = MockInferenceProvider()
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)
        try await multiProvider.register(prefix: "mock", provider: selectedProvider)
        await multiProvider.setModel("mock/model")

        let outcome = try await ProviderCertificationHarness.certifyTranscriptReplay(
            using: multiProvider,
            backing: selectedProvider
        )

        #expect(outcome.transcript.schemaVersion == .current)
        #expect(outcome.replayMessages.contains { message in
            message.role == .assistant && message.toolCalls.first?.name == "string"
        })
        #expect(outcome.replayMessages.contains { message in
            message.role == .tool && message.toolCallID == "call_1"
        })
    }

    @Test("MockInferenceProvider fails with timeout when provider exceeds contract timeout")
    func mockProviderTimesOutSafely() async throws {
        let provider = MockInferenceProvider(responses: ["slow reply"])
        await provider.setDelay(.milliseconds(200))

        let error = try await ProviderCertificationHarness.certifyTimeout(using: provider)

        if case let .timeout(duration) = error {
            #expect(duration == .milliseconds(50))
        } else {
            Issue.record("Expected timeout error, got: \(error)")
        }
    }

    @Test("MultiProvider selected route surfaces cancellation through wrapped provider")
    func multiProviderCancelsSafely() async throws {
        let defaultProvider = CertifiedTextOnlyProvider(mode: .finalAnswer("default"))
        let selectedProvider = MockInferenceProvider(responses: ["slow reply"])
        await selectedProvider.setDelay(.milliseconds(200))

        let multiProvider = MultiProvider(defaultProvider: defaultProvider)
        try await multiProvider.register(prefix: "mock", provider: selectedProvider)
        await multiProvider.setModel("mock/model")

        let error = try await ProviderCertificationHarness.certifyCancellation(using: multiProvider)
        #expect(error == .cancelled)
    }
}
