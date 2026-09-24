import Foundation

/// Resolved owned-loop turn inputs that an Apple profile session needs.
///
/// Pure Swarm value (no `FoundationModels` import) so mapping stays unit
/// testable on every platform. ``FoundationModelsNativeDynamicProfile``
/// (OS 27) renders this onto one Apple `Profile`.
struct FoundationModelsOwnedLoopSnapshot: Sendable, Equatable {
    /// Resolved instructions for this turn. Empty means no `Instructions`.
    var instructions: String
    /// Resolved temperature (mirrors `InferenceOptions.temperature`).
    var temperature: Double
    /// Resolved maximum response tokens, when the caller set one.
    var maxTokens: Int?
    /// Resolved Swarm reasoning overlay, when configured.
    var reasoning: FoundationModelsReasoningLevel?
    /// Resolved tool choice, when the caller set one.
    var toolChoice: ToolChoice?

    /// Snapshots a resolved turn. `instructions` may be nil (no instructions).
    init(
        instructions: String?,
        options: InferenceOptions,
        reasoning: FoundationModelsReasoningLevel?
    ) {
        self.instructions = instructions ?? ""
        self.temperature = options.temperature
        self.maxTokens = options.maxTokens
        self.reasoning = reasoning
        self.toolChoice = options.toolChoice
    }
}
