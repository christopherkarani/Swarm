@testable import Swarm
import Testing

/// Pins the durable agent-configuration signature to the 0.6 layout so
/// checkpoints written before the 0.7 configuration consolidation still resume.
@Suite("Workflow configuration signature compatibility")
struct WorkflowConfigurationSignatureTests {
    private static let balancedProfile = "448#Swarm.ContextProfile(preset: Swarm.ContextProfile.Preset.balanced, "
        + "maxContextTokens: 8192, maxTotalContextTokens: 8192, workingTokenRatio: 0.55, memoryTokenRatio: 0.3, "
        + "toolIOTokenRatio: 0.15, summaryTokenRatio: 0.5, maxToolOutputTokens: 1000, maxRetrievedItems: 3, "
        + "maxRetrievedItemTokens: 400, summaryCadenceTurns: 3, summaryTriggerUtilization: 0.65, "
        + "outputReserveTokens: 0, protocolOverheadReserveTokens: 0, safetyMarginTokens: 0, bucketCaps: nil)"

    private static func legacySignature(sampling: String) -> String {
        "name=5#Agent;maxIterations=10;timeout=60:0;\(sampling);modelSettings=3#nil;"
            + "contextProfile=\(balancedProfile);contextMode=26#Swarm.ContextMode.adaptive;inferencePolicy=3#nil;"
            + "enableStreaming=true;includeToolCallDetails=true;stopOnToolError=false;includeReasoning=true;"
            + "sessionHistoryLimit=50;parallelToolCalls=false;previousResponseId=3#nil;autoPreviousResponseId=false;"
            + "defaultTracingEnabled=true;graphRunOptionsOverride=3#nil"
    }

    @Test("default configuration keeps its 0.6 signature")
    func defaultConfigurationMatchesLegacySignature() throws {
        try #require(ContextProfile.platformDefault == .balanced)
        #expect(
            workflowConfigurationSignature(AgentConfiguration())
                == Self.legacySignature(sampling: "temperature=1.0;maxTokens=nil;stopSequences=2#[]")
        )
    }

    @Test("sampling builders keep their 0.6 signature after moving into modelSettings")
    func samplingBuildersMatchLegacySignature() throws {
        try #require(ContextProfile.platformDefault == .balanced)
        let configuration = AgentConfiguration()
            .temperature(0.2)
            .maxTokens(100)
            .stopSequences(["END"])

        #expect(
            workflowConfigurationSignature(configuration)
                == Self.legacySignature(sampling: "temperature=0.2;maxTokens=100;stopSequences=7#[\"END\"]")
        )
    }

    @Test("non-sampling model settings still change the signature")
    func residualModelSettingsChangeSignature() {
        let base = workflowConfigurationSignature(AgentConfiguration())
        let tuned = workflowConfigurationSignature(AgentConfiguration().modelSettings(ModelSettings(topP: 0.5)))
        #expect(base != tuned)
    }
}
