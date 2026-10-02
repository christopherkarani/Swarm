import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Maps Apple Foundation Models errors onto ``AgentError``.
///
/// OS 27 uses the split `LanguageModelError` / `SystemLanguageModel.Error` /
/// `LanguageModelSession.Error` types. OS 26 still throws
/// `LanguageModelSession.GenerationError`.
enum FoundationModelsErrorMapping: Sendable {
    static func isContextOverflow(_ error: Error) -> Bool {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            if case .contextSizeExceeded = error as? LanguageModelError {
                return true
            }
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = generationError {
                return true
            }
        }
        return FoundationModelsContextOverflow.stringMatches(error)
    }

    static func map(_ error: Error) -> AgentError {
        if let cancelled = AgentErrorCauseFactory.cancelledIfApplicable(error) {
            return cancelled
        }
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            if let mapped = mapOS27(error) {
                return mapped
            }
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            return mapGenerationError(generationError)
        }
        if let fallback = stringCauseTable.first(where: {
            AgentErrorCauseFactory.descriptionMatches(error, needles: $0.needles)
        }) {
            return fallback.make()
        }
        return .generationFailed(reason: error.localizedDescription)
    }

    /// String-fallback cause table, consulted in order after typed mapping.
    ///
    /// Hosts that only surface a description (no typed error) match here.
    /// The context row precedes the quota row: a description naming both an
    /// overflow and a quota failure maps to ``AgentError/contextWindowExceeded``.
    private struct StringCause: Sendable {
        let needles: [String]
        let make: @Sendable () -> AgentError
    }

    private static let stringCauseTable: [StringCause] = [
        StringCause(needles: FoundationModelsContextOverflow.needles) {
            .contextWindowExceeded(tokenCount: 0, limit: 0)
        },
        StringCause(needles: FoundationModelsQuotaLimit.needles) {
            .rateLimitExceeded(retryAfter: nil)
        },
    ]

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    private static func mapOS27(_ error: Error) -> AgentError? {
        if let modelError = error as? LanguageModelError {
            switch modelError {
            case let .contextSizeExceeded(payload):
                return .contextWindowExceeded(
                    tokenCount: payload.tokenCount,
                    limit: payload.contextSize
                )
            case let .rateLimited(payload):
                return AgentErrorCauseFactory.rateLimitExceeded(resetDate: payload.resetDate)
            case let .guardrailViolation(payload):
                return .guardrailViolation(reason: payload.debugDescription)
            case let .refusal(payload):
                return .contentFiltered(reason: payload.debugDescription)
            case let .unsupportedLanguageOrLocale(payload):
                return .unsupportedLanguage(language: payload.languageCode.identifier)
            case let .timeout(payload):
                return .generationFailed(reason: payload.debugDescription)
            case let .unsupportedCapability(payload):
                return .generationFailed(reason: payload.debugDescription)
            case let .unsupportedTranscriptContent(payload):
                return .generationFailed(reason: payload.debugDescription)
            case let .unsupportedGenerationGuide(payload):
                return .generationFailed(reason: payload.debugDescription)
            @unknown default:
                return .generationFailed(reason: modelError.localizedDescription)
            }
        }
        if error is SystemLanguageModel.Error {
            return .modelNotAvailable(model: "Apple Foundation Models")
        }
        if let pccError = error as? PrivateCloudComputeLanguageModel.Error {
            return mapPrivateCloudComputeError(pccError)
        }
        if let sessionError = error as? LanguageModelSession.Error {
            switch sessionError {
            case .concurrentRequests:
                return .generationFailed(
                    reason: "Foundation Models does not allow concurrent requests on one session."
                )
            case .transcriptMutationWhileResponding:
                return .generationFailed(
                    reason: "Foundation Models rejected a transcript mutation while responding."
                )
            @unknown default:
                return .generationFailed(reason: sessionError.localizedDescription)
            }
        }
        return nil
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    private static func mapPrivateCloudComputeError(
        _ error: PrivateCloudComputeLanguageModel.Error
    ) -> AgentError {
        switch error {
        case let .quotaLimitReached(payload):
            return AgentErrorCauseFactory.rateLimitExceeded(resetDate: payload.resetDate)
        @unknown default:
            return .generationFailed(reason: error.localizedDescription)
        }
    }

    private static func mapGenerationError(
        _ generationError: LanguageModelSession.GenerationError
    ) -> AgentError {
        switch generationError {
        case .exceededContextWindowSize:
            return .contextWindowExceeded(tokenCount: 0, limit: 0)
        case .rateLimited:
            return .rateLimitExceeded(retryAfter: nil)
        case .guardrailViolation:
            return .guardrailViolation(reason: generationError.localizedDescription)
        case .refusal:
            return .contentFiltered(reason: generationError.localizedDescription)
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguage(language: "unknown")
        case .assetsUnavailable:
            return .modelNotAvailable(model: "Apple Foundation Models")
        case .concurrentRequests:
            return .generationFailed(
                reason: "Foundation Models does not allow concurrent requests on one session."
            )
        default:
            if FoundationModelsContextOverflow.stringMatches(generationError) {
                return .contextWindowExceeded(tokenCount: 0, limit: 0)
            }
            return .generationFailed(reason: generationError.localizedDescription)
        }
    }
}
#endif
