import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Foundation Models OS 27 adapter")
struct FoundationModelsOS27AdapterTests {
    @Test("context budget uses the model context size, not platform 4k/8k defaults")
    func contextBudgetUsesProvidedContextSize() {
        let profile = FoundationModelsContextBudget.profile(contextSize: 32768)
        #expect(profile.budget.maxInputTokens == 32768)
        #expect(profile.budget.maxInputTokens != ContextProfile.platformDefault.budget.maxInputTokens)
    }

    @Test("fallback context size is the documented 26.0…26.3 back-deploy value")
    func fallbackContextSizeIs4096() {
        #expect(FoundationModelsContextBudget.fallbackContextSize == 4096)
        let profile = FoundationModelsContextBudget.profile(
            contextSize: FoundationModelsContextBudget.fallbackContextSize
        )
        #expect(profile.budget.maxInputTokens == 4096)
    }

    @Test("PCC context size is the documented 32K window")
    func privateCloudComputeContextSizeIs32768() {
        #expect(FoundationModelsContextBudget.privateCloudComputeContextSize == 32768)
        let profile = FoundationModelsContextBudget.profile(
            contextSize: FoundationModelsContextBudget.privateCloudComputeContextSize
        )
        #expect(profile.budget.maxInputTokens == 32768)
    }

    @Test("quota limit strings map independently of Apple error types")
    func quotaLimitStringsMatch() {
        #expect(FoundationModelsQuotaLimit.stringMatches(FakeError("quotaLimitReached")))
        #expect(FoundationModelsQuotaLimit.stringMatches(FakeError("Usage limit exceeded")))
        #expect(FoundationModelsQuotaLimit.stringMatches(FakeError("usage limit reached")))
        #expect(FoundationModelsQuotaLimit.stringMatches(FakeError("boom")) == false)
    }

    @Test("Linux configuration stays instructions and prewarm only")
    func configurationSurfaceStaysInstructionsAndPrewarm() {
        var configuration = FoundationModelsProviderConfiguration(
            instructions: "Be brief.",
            prewarmOnInit: true
        )
        #expect(configuration.instructions == "Be brief.")
        #expect(configuration.prewarmOnInit)
        configuration.prewarmOnInit = false
        #expect(configuration.prewarmOnInit == false)
    }

    #if canImport(FoundationModels)
    @Test("injected SystemLanguageModel drives availability and the capture envelope")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func injectedModelDrivesAvailabilityAndEnvelope() {
        let model = SystemLanguageModel.default
        #expect(
            FoundationModelsInferenceProvider.isAvailable(model)
                == (model.availability == .available)
        )
        if FoundationModelsInferenceProvider.isAvailable(model) {
            let provider = FoundationModelsInferenceProvider(configuration: .default, model: model)
            let expected = FoundationModelsContextBudget.profile(contextSize: model.contextSize)
            #expect(provider.envelopeProfile.budget.maxInputTokens == expected.budget.maxInputTokens)
            #expect(FoundationModelsInferenceProvider.ifAvailable(model: model) != nil)
        } else {
            #expect(FoundationModelsInferenceProvider.ifAvailable(model: model) == nil)
        }
    }
    #endif

    @Test("required tool choice is prompt-injected only before OS 27")
    func requiredToolChoicePromptInjectionIsVersionGated() {
        let schema = ToolSchema(name: "lookup", description: "Look up", parameters: [])
        var options = InferenceOptions()
        options.toolChoice = .required
        let prompt = FoundationModelsPromptFlattening.flatten(
            messages: [.user("hi")],
            tools: [schema],
            options: options
        )
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            #expect(prompt.contains(FoundationModelsPromptFlattening.requiredToolGuidance) == false)
            #expect(FoundationModelsPromptFlattening.shouldPromptInjectToolChoice == false)
        } else {
            #expect(prompt.contains(FoundationModelsPromptFlattening.requiredToolGuidance))
            #expect(FoundationModelsPromptFlattening.shouldPromptInjectToolChoice)
        }
    }

    @Test("configuration carries an optional Swarm reasoning level")
    func configurationCarriesReasoningLevel() {
        let empty = FoundationModelsProviderConfiguration()
        #expect(empty.reasoningLevel == nil)
        let deep = FoundationModelsProviderConfiguration(reasoningLevel: .deep)
        #expect(deep.reasoningLevel == .deep)
        #expect(FoundationModelsReasoningLevel.allCases.map(\.rawValue) == [
            "light", "moderate", "deep",
        ])
    }

    @Test("specific tool choice still names the tool in the prompt")
    func specificToolChoiceStaysInPrompt() {
        let schema = ToolSchema(name: "lookup", description: "Look up", parameters: [])
        var options = InferenceOptions()
        options.toolChoice = .specific(toolName: "lookup")
        let prompt = FoundationModelsPromptFlattening.flatten(
            messages: [.user("hi")],
            tools: [schema],
            options: options
        )
        #expect(prompt.contains("call \"lookup\""))
    }

    @Test("string overflow descriptions still map to contextWindowExceeded")
    func stringOverflowStillMaps() {
        let error = FoundationModelsContextOverflow.map(FakeError("model context size exceeded"))
        guard case .contextWindowExceeded = error else {
            Issue.record("expected contextWindowExceeded, got \(error)")
            return
        }
    }

    #if canImport(FoundationModels)
    @Test("OS 27 contextSizeExceeded carries token counts")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func os27ContextOverflowCarriesCounts() {
        let appleError = LanguageModelError.contextSizeExceeded(
            .init(contextSize: 4096, tokenCount: 5120, debugDescription: "overflow")
        )
        let mapped = FoundationModelsErrorMapping.map(appleError)
        #expect(mapped == .contextWindowExceeded(tokenCount: 5120, limit: 4096))
        #expect(FoundationModelsErrorMapping.isContextOverflow(appleError))
    }

    @Test("OS 27 rateLimited maps onto rateLimitExceeded")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func os27RateLimitedMaps() throws {
        let reset = Date().addingTimeInterval(30)
        let appleError = LanguageModelError.rateLimited(
            .init(resetDate: reset, debugDescription: "slow down")
        )
        let mapped = FoundationModelsErrorMapping.map(appleError)
        guard case let .rateLimitExceeded(retryAfter) = mapped else {
            Issue.record("expected rateLimitExceeded, got \(mapped)")
            return
        }
        let delay = try #require(retryAfter)
        #expect(delay > 0)
        #expect(delay <= 30)
    }

    @Test("quota host strings map onto rateLimitExceeded")
    func quotaHostStringsMapThroughErrorMapping() {
        let mapped = FoundationModelsErrorMapping.map(FakeError("quotaLimitReached"))
        guard case .rateLimitExceeded(let retryAfter) = mapped else {
            Issue.record("expected rateLimitExceeded, got \(mapped)")
            return
        }
        #expect(retryAfter == nil)
    }

    @Test("PCC quotaLimitReached maps onto rateLimitExceeded")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func pccQuotaLimitReachedMaps() throws {
        let reset = Date().addingTimeInterval(45)
        let appleError = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: reset, debugDescription: "daily quota")
        )
        let mapped = FoundationModelsErrorMapping.map(appleError)
        guard case let .rateLimitExceeded(retryAfter) = mapped else {
            Issue.record("expected rateLimitExceeded, got \(mapped)")
            return
        }
        let delay = try #require(retryAfter)
        #expect(delay > 0)
        #expect(delay <= 45)
    }

    @Test("ifAvailable(model:) follows the concrete LanguageModel, with no on-device fallback")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func languageModelIfAvailableDoesNotFallback() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let model = PrivateCloudComputeLanguageModel()
        let available = FoundationModelsSessionModel.isAvailable(model)
        #expect(available == (model.availability == .available))
        if available {
            #expect(FoundationModelsInferenceProvider.ifAvailable(model: model) != nil)
        } else {
            #expect(FoundationModelsInferenceProvider.ifAvailable(model: model) == nil)
        }
        #endif
    }

    @Test("OS 27 concurrentRequests is not treated as overflow")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func os27ConcurrentRequestsAreNotOverflow() {
        let appleError = LanguageModelSession.Error.concurrentRequests
        #expect(FoundationModelsErrorMapping.isContextOverflow(appleError) == false)
        let mapped = FoundationModelsErrorMapping.map(appleError)
        guard case let .generationFailed(reason) = mapped else {
            Issue.record("expected generationFailed, got \(mapped)")
            return
        }
        #expect(reason.contains("concurrent"))
    }

    @Test("OS 27 usage maps input and output totals")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func os27UsageMapsTotals() {
        let usage = LanguageModelSession.Usage(
            input: .init(totalTokenCount: 12, cachedTokenCount: 3),
            output: .init(totalTokenCount: 8, reasoningTokenCount: 2)
        )
        let mapped = FoundationModelsUsageMapping.tokenUsage(from: usage)
        #expect(mapped == TokenUsage(inputTokens: 12, outputTokens: 8))
    }

    @Test("OS 27 required tool choice sets toolCallingMode")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func os27RequiredToolChoiceSetsToolCallingMode() {
        #expect(FoundationModelsGenerationOptions.toolCallingMode(for: .required) == .required)
        #expect(FoundationModelsGenerationOptions.toolCallingMode(for: ToolChoice.none) == .disallowed)
        #expect(FoundationModelsGenerationOptions.toolCallingMode(for: .auto) == .allowed)
        var options = InferenceOptions(temperature: 0)
        options.toolChoice = .required
        let generation = FoundationModelsGenerationOptions.make(from: options)
        #expect(generation.toolCallingMode == .required)
        #expect(generation.samplingMode == .greedy)
    }

    @Test("specific tool choice maps to allowed because Apple has no specific mode")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func specificToolChoiceMapsToAllowed() {
        #expect(
            FoundationModelsGenerationOptions.toolCallingMode(for: .specific(toolName: "lookup"))
                == .allowed
        )
    }

    @Test("Swarm reasoning levels map onto Apple ContextOptions.ReasoningLevel")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func reasoningLevelsMapToAppleContextOptions() {
        #expect(FoundationModelsReasoningLevel.light.appleReasoningLevel == .light)
        #expect(FoundationModelsReasoningLevel.moderate.appleReasoningLevel == .moderate)
        #expect(FoundationModelsReasoningLevel.deep.appleReasoningLevel == .deep)
        #expect(FoundationModelsReasoningLevel.deep.contextOptions.reasoningLevel == .deep)
    }

    @Test("owned-loop reads reasoningLevel from configuration")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func ownedLoopReadsReasoningLevel() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(
            configuration: .init(reasoningLevel: .moderate),
            ownsToolLoop: true
        )
        #expect(provider.ownedLoopReasoningLevel == .moderate)
        let capture = FoundationModelsInferenceProvider()
        #expect(capture.ownedLoopReasoningLevel == nil)
        #endif
    }
    #endif
}

private struct FakeError: Error, LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}
