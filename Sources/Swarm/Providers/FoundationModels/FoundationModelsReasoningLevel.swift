import Foundation

/// Swarm overlay for Apple `ContextOptions.ReasoningLevel` (OS 27).
///
/// This is **not** Apple's `ContextOptions` type. Capture mode ignores the
/// value today. Owned-loop ``FoundationModelsInferenceProvider`` maps it onto
/// `session.respond(..., contextOptions:)` when the OS is 27 or later.
public enum FoundationModelsReasoningLevel: String, Sendable, Equatable, CaseIterable {
    /// Short reasoning before the visible answer.
    case light
    /// Balanced reasoning.
    case moderate
    /// Longest reasoning, highest context cost.
    case deep
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension FoundationModelsReasoningLevel {
    /// Apple `ContextOptions.ReasoningLevel` for this Swarm case.
    var appleReasoningLevel: ContextOptions.ReasoningLevel {
        switch self {
        case .light:
            return .light
        case .moderate:
            return .moderate
        case .deep:
            return .deep
        }
    }

    /// OS 27 context options carrying only this reasoning level.
    var contextOptions: ContextOptions {
        ContextOptions(reasoningLevel: appleReasoningLevel)
    }
}
#endif
