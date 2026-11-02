@testable import Swarm
import Testing

/// Pins the durable agent-configuration signature to the 0.6 layout so
/// checkpoints written before the 0.7 configuration consolidation still resume.
@Suite("Workflow configuration signature compatibility")
struct WorkflowConfigurationSignatureTests {
    /// The 0.6 `contextProfile` component for the default configuration. The
    /// default profile is sized per platform (8192 tokens on macOS, 4096 elsewhere).
    private static var balancedProfile: String {
        let tokens = ContextProfile.PlatformDefaults.current.maxContextTokens
        let body = "Swarm.ContextProfile(preset: Swarm.ContextProfile.Preset.balanced, "
            + "maxContextTokens: \(tokens), maxTotalContextTokens: \(tokens), workingTokenRatio: 0.55, "
            + "memoryTokenRatio: 0.3, toolIOTokenRatio: 0.15, summaryTokenRatio: 0.5, maxToolOutputTokens: 1000, "
            + "maxRetrievedItems: 3, maxRetrievedItemTokens: 400, summaryCadenceTurns: 3, "
            + "summaryTriggerUtilization: 0.65, outputReserveTokens: 0, protocolOverheadReserveTokens: 0, "
            + "safetyMarginTokens: 0, bucketCaps: nil)"
        return "\(body.utf8.count)#\(body)"
    }

    /// The 0.6 `modelSettings` component for `ModelSettings().toolChoice(.required)`.
    private static let legacyRequiredToolChoiceSettings = "45#Optional(ModelSettings(toolChoice: required))"

    private static func legacySignature(sampling: String, modelSettings: String = "3#nil") -> String {
        "name=5#Agent;maxIterations=10;timeout=60:0;\(sampling);modelSettings=\(modelSettings);"
            + "contextProfile=\(balancedProfile);contextMode=26#Swarm.ContextMode.adaptive;inferencePolicy=3#nil;"
            + "enableStreaming=true;includeToolCallDetails=true;stopOnToolError=false;includeReasoning=true;"
            + "sessionHistoryLimit=50;parallelToolCalls=false;previousResponseId=3#nil;autoPreviousResponseId=false;"
            + "defaultTracingEnabled=true;graphRunOptionsOverride=3#nil"
    }

    @Test("default configuration keeps its 0.6 signature")
    func defaultConfigurationMatchesLegacySignature() {
        #expect(
            workflowConfigurationSignature(AgentConfiguration())
                == Self.legacySignature(sampling: "temperature=1.0;maxTokens=nil;stopSequences=2#[]")
        )
    }

    @Test("sampling builders keep their 0.6 signature after moving into modelSettings")
    func samplingBuildersMatchLegacySignature() {
        let configuration = AgentConfiguration()
            .temperature(0.2)
            .maxTokens(100)
            .stopSequences(["END"])

        #expect(
            workflowConfigurationSignature(configuration)
                == Self.legacySignature(sampling: "temperature=0.2;maxTokens=100;stopSequences=7#[\"END\"]")
        )
    }

    @Test("sampling builders followed by modelSettings keep their 0.6 signature")
    func samplingBuildersThenModelSettingsMatchLegacySignature() {
        let configuration = AgentConfiguration()
            .temperature(0.2)
            .maxTokens(500)
            .stopSequences(["END"])
            .modelSettings(ModelSettings().toolChoice(.required))

        #expect(
            workflowConfigurationSignature(configuration)
                == Self.legacySignature(
                    sampling: "temperature=0.2;maxTokens=500;stopSequences=7#[\"END\"]",
                    modelSettings: Self.legacyRequiredToolChoiceSettings
                )
        )
    }

    @Test("an explicit empty modelSettings signs the same as the default")
    func emptyModelSettingsSignsAsDefault() {
        #expect(
            workflowConfigurationSignature(AgentConfiguration().modelSettings(ModelSettings()))
                == workflowConfigurationSignature(AgentConfiguration())
        )
    }

    @Test("non-sampling model settings still change the signature")
    func residualModelSettingsChangeSignature() {
        let base = workflowConfigurationSignature(AgentConfiguration())
        let tuned = workflowConfigurationSignature(AgentConfiguration().modelSettings(ModelSettings(topP: 0.5)))
        #expect(base != tuned)
    }
}
