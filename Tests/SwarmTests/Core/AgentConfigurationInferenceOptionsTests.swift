import Testing
@testable import Swarm

@Suite("AgentConfiguration Inference Options")
struct AgentConfigurationInferenceOptionsTests {
    @Test("ModelSettings execution fields propagate to InferenceOptions")
    func modelSettingsPropagation() {
        let settings = ModelSettings()
            .temperature(0.25)
            .maxTokens(321)
            .stopSequences(["A", "B"])
            .topP(0.8)
            .topK(42)
            .presencePenalty(0.3)
            .frequencyPenalty(0.4)
            .toolChoice(.required)
            .seed(99)
            .parallelToolCalls(true)
            .truncation(.auto)
            .verbosity(.high)
            .providerSettings(["openai:custom": .string("value")])

        let config = AgentConfiguration.default
            .parallelToolCalls(false)
            .modelSettings(settings)

        let options = config.inferenceOptions
        #expect(options.temperature == 0.25)
        #expect(options.maxTokens == 321)
        #expect(options.stopSequences == ["A", "B"])
        #expect(options.topP == 0.8)
        #expect(options.topK == 42)
        #expect(options.presencePenalty == 0.3)
        #expect(options.frequencyPenalty == 0.4)
        #expect(options.toolChoice == .required)
        #expect(options.seed == 99)
        #expect(options.parallelToolCalls == true)
        #expect(options.truncation == .auto)
        #expect(options.verbosity == .high)
        #expect(options.providerSettings?["openai:custom"] == .string("value"))
    }

    @Test("Sampling builders write modelSettings, the single source for inference options")
    func samplingBuildersWriteModelSettings() {
        let config = AgentConfiguration.default
            .temperature(0.5)
            .maxTokens(123)
            .stopSequences(["STOP"])
            .parallelToolCalls(true)

        #expect(config.modelSettings == ModelSettings(temperature: 0.5, maxTokens: 123, stopSequences: ["STOP"]))

        let options = config.inferenceOptions
        #expect(options.temperature == 0.5)
        #expect(options.maxTokens == 123)
        #expect(options.stopSequences == ["STOP"])
        #expect(options.parallelToolCalls == true)
        #expect(options.previousResponseId == nil)
        #expect(options.seed == nil)
        #expect(options.truncation == nil)
        #expect(options.verbosity == nil)
        #expect(options.providerSettings == nil)
    }

    @Test("modelSettings(_:) keeps earlier sampling builders the incoming value leaves unset")
    func modelSettingsKeepsEarlierSamplingBuilders() {
        let config = AgentConfiguration.default
            .temperature(0.2)
            .maxTokens(500)
            .stopSequences(["END"])
            .modelSettings(ModelSettings().toolChoice(.required))

        #expect(config.modelSettings.temperature == 0.2)
        #expect(config.modelSettings.maxTokens == 500)
        #expect(config.modelSettings.stopSequences == ["END"])
        #expect(config.modelSettings.toolChoice == .required)

        let options = config.inferenceOptions
        #expect(options.temperature == 0.2)
        #expect(options.maxTokens == 500)
        #expect(options.stopSequences == ["END"])
    }

    @Test("modelSettings(_:) sampling fields win over earlier sampling builders")
    func modelSettingsSamplingFieldsWin() {
        let config = AgentConfiguration.default
            .temperature(0.2)
            .modelSettings(.creative)

        #expect(config.modelSettings.temperature == ModelSettings.creative.temperature)
        #expect(config.modelSettings.topP == ModelSettings.creative.topP)
    }

    @Test("modelSettings(_:) keeps sampling fields from an earlier modelSettings(_:) call")
    func modelSettingsKeepsEarlierModelSettingsSampling() {
        let config = AgentConfiguration.default
            .modelSettings(.creative)
            .modelSettings(ModelSettings().toolChoice(.required))

        #expect(config.modelSettings.temperature == ModelSettings.creative.temperature)
        #expect(config.modelSettings.topP == nil)
        #expect(config.modelSettings.toolChoice == .required)

        let cleared = config.modelSettings(ModelSettings())
        #expect(cleared.modelSettings.temperature == ModelSettings.creative.temperature)
        #expect(cleared.modelSettings.toolChoice == nil)
    }

    @Test("ModelSettings reasoning config propagates to InferenceOptions")
    func reasoningConfigPropagation() {
        let reasoning = ReasoningConfig(effort: .low, maxTokens: 4096, exclude: true)
        let settings = ModelSettings().reasoning(reasoning)
        let config = AgentConfiguration.default.modelSettings(settings)

        let options = config.inferenceOptions
        #expect(options.reasoning?.effort == .low)
        #expect(options.reasoning?.maxTokens == 4096)
        #expect(options.reasoning?.exclude == true)
        #expect(options.reasoning?.enabled == nil)
    }

    @Test("Reasoning is nil when model settings absent")
    func reasoningNilWithoutModelSettings() {
        let config = AgentConfiguration.default
        #expect(config.inferenceOptions.reasoning == nil)
    }

    @Test("ReasoningEffort.none is distinct from nil")
    func reasoningEffortNoneIsExpressible() {
        // Callers need a way to explicitly disable reasoning when the
        // base/provider config has it on. `nil` means "preserve base";
        // `.none` means "off".
        let reasoning = ReasoningConfig(effort: ReasoningEffort.none)
        let settings = ModelSettings().reasoning(reasoning)
        let config = AgentConfiguration.default.modelSettings(settings)

        #expect(config.inferenceOptions.reasoning?.effort == ReasoningEffort.none)
        #expect(ReasoningEffort.none.rawValue == "none")
    }

    @Test("Unset model settings fall back to InferenceOptions defaults")
    func unsetModelSettingsUseInferenceDefaults() {
        let options = AgentConfiguration.default.inferenceOptions
        #expect(options.temperature == InferenceOptions.default.temperature)
        #expect(options.maxTokens == nil)
        #expect(options.stopSequences.isEmpty)
    }

    @Test("contextProfile is the single context knob")
    func strict4kProfileIsUsedDirectly() {
        let config = AgentConfiguration.default
            .contextProfile(.heavy(maxContextTokens: 8192))
            .contextProfile(.strict4k)

        #expect(config.contextProfile.preset == .strict4k)
        #expect(config.contextProfile.maxTotalContextTokens == 4096)
        #expect(config.contextProfile.maxContextTokens == 3412)
    }
}
