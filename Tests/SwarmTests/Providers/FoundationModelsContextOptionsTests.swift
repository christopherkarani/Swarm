import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Foundation Models context options")
struct FoundationModelsContextOptionsTests {
    @Test("default configuration leaves reasoningLevel nil and prewarm off")
    func defaultConfigurationLeavesReasoningNil() {
        let config = FoundationModelsProviderConfiguration()
        #expect(config.reasoningLevel == nil)
        #expect(config.prewarmOnInit == false)
        #expect(FoundationModelsProviderConfiguration.default.reasoningLevel == nil)
    }

    @Test("existing two-argument initializer still compiles without reasoningLevel")
    func existingTwoArgumentInitStillCompiles() {
        let config = FoundationModelsProviderConfiguration(
            instructions: "Be brief.",
            prewarmOnInit: false
        )
        #expect(config.instructions == "Be brief.")
        #expect(config.prewarmOnInit == false)
        #expect(config.reasoningLevel == nil)
    }

    @Test(
        "configuration stores each Swarm reasoning level",
        arguments: FoundationModelsReasoningLevel.allCases
    )
    func configurationStoresEachSwarmLevel(_ level: FoundationModelsReasoningLevel) {
        let config = FoundationModelsProviderConfiguration(reasoningLevel: level)
        #expect(config.reasoningLevel == level)
        #expect(config.prewarmOnInit == false)
    }

    @Test("Swarm reasoning level exposes light, moderate, and deep only")
    func swarmReasoningLevelHasNoCustomCase() {
        #expect(FoundationModelsReasoningLevel.allCases == [.light, .moderate, .deep])
    }

    #if canImport(FoundationModels)
    @Test("nil reasoning builds ContextOptions without forcing a reasoning level")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func nilReasoningDoesNotForceLevel() {
        let options = FoundationModelsContextOptions.text(reasoningLevel: nil)
        #expect(options.reasoningLevel == nil)
        #expect(options.includeSchemaInPrompt == nil)
    }

    @Test(
        "Swarm reasoning levels map onto Apple ContextOptions.ReasoningLevel",
        arguments: [
            (FoundationModelsReasoningLevel.light, ContextOptions.ReasoningLevel.light),
            (.moderate, .moderate),
            (.deep, .deep),
        ] as [(FoundationModelsReasoningLevel, ContextOptions.ReasoningLevel)]
    )
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func mapsOntoAppleReasoningLevel(
        swarm: FoundationModelsReasoningLevel,
        apple: ContextOptions.ReasoningLevel
    ) {
        let options = FoundationModelsContextOptions.text(reasoningLevel: swarm)
        #expect(options.reasoningLevel == apple)
        #expect(options.includeSchemaInPrompt == nil)
    }

    @Test("27 structured helper puts includeSchemaInPrompt on ContextOptions (respond uses contextOptions:)")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func structuredUsesContextOptionsNotIncludeSchemaArgument() {
        // generateStructured on 27 calls FoundationModelsContextOptions.respond(..., schema:),
        // which passes this ContextOptions instead of the includeSchemaInPrompt: argument.
        let withReasoning = FoundationModelsContextOptions.structured(reasoningLevel: .moderate)
        #expect(withReasoning.includeSchemaInPrompt == true)
        #expect(withReasoning.reasoningLevel == .moderate)

        let withoutReasoning = FoundationModelsContextOptions.structured(reasoningLevel: nil)
        #expect(withoutReasoning.includeSchemaInPrompt == true)
        #expect(withoutReasoning.reasoningLevel == nil)
    }
    #endif
}
