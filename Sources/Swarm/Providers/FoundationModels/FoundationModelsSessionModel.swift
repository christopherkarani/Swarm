import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Session-backing model for ``FoundationModelsInferenceProvider``.
///
/// OS 26 sessions always use ``SystemLanguageModel``. OS 27 can wrap any
/// Apple `LanguageModel`, including ``PrivateCloudComputeLanguageModel``.
/// This is not a Swarm ``DynamicProfile``.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsSessionModel: Sendable {
    let contextSize: Int
    let displayName: String
    let isAvailable: Bool
    /// True only for on-device `SystemLanguageModel` backing (never PCC).
    let runsOnDevice: Bool

    private let build: @Sendable (
        _ tools: [any FoundationModels.Tool],
        _ instructions: String?,
        _ transcript: Transcript?
    ) -> LanguageModelSession

    /// OS 27 profile builder. The signature stays OS 26-safe (snapshot is a
    /// Swarm value); the closure body gates Apple profile APIs internally.
    private let buildProfile: @Sendable (
        _ tools: [any FoundationModels.Tool],
        _ snapshot: FoundationModelsOwnedLoopSnapshot,
        _ history: Transcript?
    ) -> LanguageModelSession

    static func system(_ model: SystemLanguageModel = .default) -> Self {
        let legacy: @Sendable (
            [any FoundationModels.Tool],
            String?,
            Transcript?
        ) -> LanguageModelSession = { tools, instructions, transcript in
            if let transcript {
                return LanguageModelSession(model: model, tools: tools, transcript: transcript)
            }
            if let instructions, !instructions.isEmpty {
                return LanguageModelSession(model: model, tools: tools, instructions: instructions)
            }
            return LanguageModelSession(model: model, tools: tools)
        }
        return Self(
            contextSize: model.contextSize,
            displayName: "systemLanguageModel",
            isAvailable: model.availability == .available,
            runsOnDevice: true,
            build: legacy,
            buildProfile: { tools, snapshot, history in
                if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
                    let profile = FoundationModelsNativeDynamicProfile(
                        snapshot: snapshot,
                        model: model,
                        tools: tools
                    )
                    if let history {
                        return LanguageModelSession(profile: profile, history: history)
                    }
                    return LanguageModelSession(profile: profile)
                }
                let instructions = snapshot.instructions.isEmpty ? nil : snapshot.instructions
                return legacy(tools, instructions, history)
            }
        )
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func languageModel(
        _ model: some LanguageModel,
        displayName: String? = nil
    ) -> Self {
        let boxed: any LanguageModel = model
        let name = displayName ?? Self.displayName(for: boxed)
        let legacy: @Sendable (
            [any FoundationModels.Tool],
            String?,
            Transcript?
        ) -> LanguageModelSession = { tools, instructions, transcript in
            if let transcript {
                return LanguageModelSession(model: boxed, tools: tools, transcript: transcript)
            }
            if let instructions, !instructions.isEmpty {
                return LanguageModelSession(model: boxed, tools: tools, instructions: instructions)
            }
            return LanguageModelSession(model: boxed, tools: tools)
        }
        return Self(
            contextSize: Self.contextSize(for: boxed),
            displayName: name,
            isAvailable: Self.isAvailable(boxed),
            runsOnDevice: boxed is SystemLanguageModel,
            build: legacy,
            buildProfile: { tools, snapshot, history in
                let profile = FoundationModelsNativeDynamicProfile(
                    snapshot: snapshot,
                    model: boxed,
                    tools: tools
                )
                if let history {
                    return LanguageModelSession(profile: profile, history: history)
                }
                return LanguageModelSession(profile: profile)
            }
        )
    }

    func makeSession(
        tools: [any FoundationModels.Tool],
        instructions: String?
    ) -> LanguageModelSession {
        build(tools, instructions, nil)
    }

    func makeSession(
        tools: [any FoundationModels.Tool],
        transcript: Transcript
    ) -> LanguageModelSession {
        build(tools, nil, transcript)
    }

    /// Owned-loop session from a resolved turn snapshot.
    ///
    /// OS 27 builds `LanguageModelSession(profile:history:)` so instructions,
    /// tools, and knobs flow through one Apple session. Older systems use the
    /// same legacy `model:tools:` construction as ``makeSession(tools:instructions:)``.
    func makeProfileSession(
        tools: [any FoundationModels.Tool],
        snapshot: FoundationModelsOwnedLoopSnapshot,
        history: Transcript?
    ) -> LanguageModelSession {
        buildProfile(tools, snapshot, history)
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func isAvailable(_ model: some LanguageModel) -> Bool {
        if let system = model as? SystemLanguageModel {
            return system.availability == .available
        }
        if let pcc = model as? PrivateCloudComputeLanguageModel {
            return pcc.availability == .available
        }
        return true
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func contextSize(for model: some LanguageModel) -> Int {
        if let system = model as? SystemLanguageModel {
            return system.contextSize
        }
        if model is PrivateCloudComputeLanguageModel {
            // Current SDKs expose PCC `contextSize` as async/throws; this factory stays sync.
            return FoundationModelsContextBudget.fallbackContextSize
        }
        return FoundationModelsContextBudget.fallbackContextSize
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func displayName(for model: some LanguageModel) -> String {
        if model is PrivateCloudComputeLanguageModel {
            return "privateCloudComputeLanguageModel"
        }
        if model is SystemLanguageModel {
            return "systemLanguageModel"
        }
        return String(describing: type(of: model))
    }
}
#endif
