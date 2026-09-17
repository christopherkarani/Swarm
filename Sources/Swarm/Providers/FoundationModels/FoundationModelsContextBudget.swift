import Foundation

/// Context envelope for Apple Foundation Models capture prompts.
///
/// Uses the model's `contextSize` when the caller supplies it. Other
/// providers keep ``ContextProfile/platformDefault`` (4k iOS / 8k macOS).
enum FoundationModelsContextBudget: Sendable {
    /// Documented back-deployed size on OS 26.0…26.3.
    static let fallbackContextSize = 4096

    /// Documented `PrivateCloudComputeLanguageModel` context size (OS 27).
    static let privateCloudComputeContextSize = 32768

    static func profile(contextSize: Int) -> ContextProfile {
        .balanced(maxContextTokens: max(contextSize, 1))
    }
}
