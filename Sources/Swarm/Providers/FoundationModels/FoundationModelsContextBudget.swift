import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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

#if canImport(FoundationModels)
/// Counts prompt tokens with the on-device model's own tokenizer.
///
/// Backs ``FoundationModelsInferenceProvider/promptTokenCounter`` for
/// `SystemLanguageModel` sessions on OS 26.4 and later, so memory and prompt
/// budgeting use exact counts instead of the character heuristic. When
/// counting throws, ``PromptTokenBudgeting`` falls back to the heuristic.
@available(macOS 26.4, iOS 26.4, visionOS 26.4, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsPromptTokenCounter: PromptTokenCounter {
    let model: SystemLanguageModel

    func countTokens(in text: String) async throws -> Int {
        try await model.tokenCount(for: Prompt(text))
    }
}
#endif
