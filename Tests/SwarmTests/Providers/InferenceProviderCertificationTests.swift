import Testing
@testable import Swarm

@Suite("Inference Provider Capability Contract")
struct InferenceProviderCapabilityContractTests {
    @Test("Resolved capabilities merge explicit reporting with inferred protocol support")
    func resolvedCapabilitiesMergeReportingAndInferredSupport() {
        let provider = MockInferenceProvider(
            responses: ["ok"],
            capabilities: [.responseContinuation]
        )

        let capabilities = InferenceProviderCapabilities.resolved(for: provider)

        #expect(capabilities == [.conversationMessages, .responseContinuation])
    }

    @Test("Text-only conversation adapter preserves base streaming and continuation capabilities")
    func textOnlyAdapterPreservesBaseCapabilities() {
        let base = CertifiedPromptToolStreamingProvider(
            scripts: [[]],
            capabilities: [.streamingToolCalls, .responseContinuation]
        )
        let adapter = TextOnlyConversationInferenceProviderAdapter(base: base)

        #expect(adapter.capabilities.contains(.conversationMessages))
        #expect(adapter.capabilities.contains(.streamingToolCalls))
        #expect(adapter.capabilities.contains(.responseContinuation))
        #expect(adapter.capabilities.contains(.nativeToolCalling) == false)
    }

    @Test("ConduitProviderSelection reports wrapper conversation support and forwarded continuation capability")
    func conduitProviderSelectionReportsWrappedCapabilities() {
        let provider = MockInferenceProvider(
            responses: ["ok"],
            capabilities: [.responseContinuation]
        )
        let wrapper = ConduitProviderSelection.provider(provider)

        #expect(wrapper.capabilities == [.conversationMessages, .responseContinuation])
    }

    @Test("LLM reports Conduit-backed conversation, native tools, and streaming tool capabilities")
    func llmReportsConduitBridgeCapabilities() {
        let provider = LLM.openAI(key: "test-key", model: "gpt-4o-mini")

        #expect(provider.capabilities.contains(.conversationMessages))
        #expect(provider.capabilities.contains(.nativeToolCalling))
        #expect(provider.capabilities.contains(.streamingToolCalls))
        #expect(provider.capabilities.contains(.responseContinuation) == false)
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
    @Test("ConduitProviderSelection passes text-only tool emulation certification")
    func conduitProviderSelectionCertifiesTextOnlyToolEmulation() async throws {
        let provider = CertifiedTextOnlyProvider(mode: .toolThenAnswer)
        let wrapper = ConduitProviderSelection.provider(provider)

        _ = try await ProviderCertificationHarness.certifyTextOnlyToolLoop(using: wrapper)

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

    @Test("ConduitProviderSelection forwards auto continuation through wrapped providers")
    func conduitProviderSelectionForwardsAutoContinuation() async throws {
        let provider = MockInferenceProvider(
            responses: ["first reply", "second reply"],
            capabilities: [.responseContinuation]
        )
        let wrapper = ConduitProviderSelection.provider(provider)

        let (first, _) = try await ProviderCertificationHarness.runTwoTurnsWithAutoContinuation(using: wrapper)
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

    @Test("Wrapped providers fail malformed native tool arguments safely")
    func wrappedProvidersFailMalformedToolArgumentsSafely() async throws {
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
        let wrapper = ConduitProviderSelection.provider(provider)

        let error = try await ProviderCertificationHarness.certifyMalformedToolArguments(using: wrapper)

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

    @Test("ConduitProviderSelection preserves transcript replay compatibility")
    func conduitProviderSelectionCertifiesTranscriptReplay() async throws {
        let provider = MockInferenceProvider()
        let wrapper = ConduitProviderSelection.provider(provider)

        let outcome = try await ProviderCertificationHarness.certifyTranscriptReplay(
            using: wrapper,
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

    @Test("ConduitProviderSelection fails with timeout when wrapped provider exceeds contract timeout")
    func conduitProviderSelectionTimesOutSafely() async throws {
        let provider = MockInferenceProvider(responses: ["slow reply"])
        await provider.setDelay(.milliseconds(200))
        let wrapper = ConduitProviderSelection.provider(provider)

        let error = try await ProviderCertificationHarness.certifyTimeout(using: wrapper)

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
