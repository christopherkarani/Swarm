import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Foundation Models owned-loop snapshot")
struct FoundationModelsOwnedLoopSnapshotTests {
    @Test("snapshot captures instructions and option knobs")
    func snapshotCapturesTurnInputs() {
        var options = InferenceOptions()
        options.temperature = 0.2
        options.maxTokens = 512
        options.toolChoice = ToolChoice.required
        let snapshot = FoundationModelsOwnedLoopSnapshot(
            instructions: "Be brief.",
            options: options,
            reasoning: .light
        )
        #expect(snapshot.instructions == "Be brief.")
        #expect(snapshot.temperature == 0.2)
        #expect(snapshot.maxTokens == 512)
        #expect(snapshot.reasoning == .light)
        #expect(snapshot.toolChoice == ToolChoice.required)
    }

    @Test("nil instructions snapshot as empty")
    func nilInstructionsSnapshotAsEmpty() {
        let snapshot = FoundationModelsOwnedLoopSnapshot(
            instructions: nil,
            options: InferenceOptions(),
            reasoning: nil
        )
        #expect(snapshot.instructions.isEmpty)
        #expect(snapshot.temperature == 1.0)
        #expect(snapshot.maxTokens == nil)
        #expect(snapshot.reasoning == nil)
        #expect(snapshot.toolChoice == nil)
    }

    @Test("snapshots compare by value")
    func snapshotsCompareByValue() {
        let left = FoundationModelsOwnedLoopSnapshot(
            instructions: "a",
            options: InferenceOptions(),
            reasoning: nil
        )
        let right = FoundationModelsOwnedLoopSnapshot(
            instructions: "a",
            options: InferenceOptions(),
            reasoning: nil
        )
        let other = FoundationModelsOwnedLoopSnapshot(
            instructions: "b",
            options: InferenceOptions(),
            reasoning: nil
        )
        #expect(left == right)
        #expect(left != other)
    }

    #if canImport(FoundationModels)
    @Test("native profile type-checks as an Apple DynamicProfile")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func nativeProfileConformsToAppleDynamicProfile() {
        let profile = FoundationModelsNativeDynamicProfile(
            snapshot: FoundationModelsOwnedLoopSnapshot(
                instructions: "Be brief.",
                options: InferenceOptions(),
                reasoning: nil
            ),
            model: SystemLanguageModel.default,
            tools: []
        )
        acceptsAppleDynamicProfile(profile)
    }

    @Test("profile session builds with and without history")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func profileSessionBuildsWithAndWithoutHistory() {
        guard FoundationModelsInferenceProvider.isAvailable else { return }
        let model = FoundationModelsSessionModel.system()
        let snapshot = FoundationModelsOwnedLoopSnapshot(
            instructions: "Be brief.",
            options: InferenceOptions(),
            reasoning: nil
        )
        let fresh = model.makeProfileSession(tools: [], snapshot: snapshot, history: nil)
        #expect(fresh.transcript.count == 1)
        guard case .instructions = fresh.transcript.first else {
            Issue.record("profile session transcript should start with instructions")
            return
        }
        let seeded = model.makeProfileSession(
            tools: [],
            snapshot: snapshot,
            history: Transcript(entries: [])
        )
        #expect(seeded.transcript.count == 1)
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    private func acceptsAppleDynamicProfile(_ profile: some LanguageModelSession.DynamicProfile) {}
    #endif
}
