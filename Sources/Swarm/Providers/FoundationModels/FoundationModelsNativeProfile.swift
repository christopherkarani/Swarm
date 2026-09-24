import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Apple `LanguageModelSession.DynamicProfile` rendering one resolved Swarm turn.
///
/// This **is** Apple's type (unlike Swarm ``DynamicProfile``): the builder
/// evaluates to exactly one `Profile` — instructions plus the bound tools —
/// with the resolved model and generation knobs applied as modifiers.
/// ``FoundationModelsSessionModel`` builds owned-loop sessions from this via
/// `LanguageModelSession(profile:history:)` on OS 27 so instructions, tools,
/// and knobs flow through one Apple session instead of a recreated
/// `LanguageModelSession(model:tools:transcript:)`.
@available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
struct FoundationModelsNativeDynamicProfile: LanguageModelSession.DynamicProfile, Sendable {
    /// Resolved turn inputs (instructions plus generation knobs).
    var snapshot: FoundationModelsOwnedLoopSnapshot
    /// Boxed Apple model (`SystemLanguageModel`, PCC, or custom).
    var model: any LanguageModel
    /// Executing tools bound for this turn.
    var tools: [any FoundationModels.Tool]

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            if !snapshot.instructions.isEmpty {
                Instructions(snapshot.instructions)
            }
            tools
        }
        .model(model)
        .temperature(snapshot.temperature)
        .maximumResponseTokens(snapshot.maxTokens)
        .reasoningLevel(snapshot.reasoning?.appleReasoningLevel)
        .toolCallingMode(FoundationModelsGenerationOptions.toolCallingMode(for: snapshot.toolChoice))
    }
}
#endif
