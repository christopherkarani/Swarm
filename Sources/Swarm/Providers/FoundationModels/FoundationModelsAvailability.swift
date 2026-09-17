import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Foundation Models availability.
///
/// Prefer ``FoundationModelsInferenceProvider/availability`` over the boolean
/// ``FoundationModelsInferenceProvider/isAvailable`` when you need the reason
/// the model is missing. `isAvailable` is `true` exactly when this value is
/// ``FoundationModelsAvailability/available``.
///
/// This type compiles on Linux and in builds without FoundationModels. There is
/// no `FoundationModelsInferenceProvider` in those environments; treat
/// availability as ``UnavailableReason/frameworkUnavailable``.
///
/// PCC reasons (`systemNotReady`, quota) are not part of this enum.
public enum FoundationModelsAvailability: Sendable, Equatable {
    /// The on-device system language model is ready.
    case available
    /// The on-device system language model is not ready.
    case unavailable(UnavailableReason)

    /// Why on-device Foundation Models are unavailable.
    public enum UnavailableReason: Sendable, Equatable, CaseIterable {
        /// The device cannot run Apple Intelligence.
        case deviceNotEligible
        /// Apple Intelligence is turned off.
        case appleIntelligenceNotEnabled
        /// The model is still downloading or otherwise not ready.
        case modelNotReady
        /// The FoundationModels framework is not present (Linux, or a build
        /// without the module). Callers without the framework should use this
        /// case; Swarm does not ship a Linux `FoundationModelsInferenceProvider`.
        case frameworkUnavailable
        /// Apple reported a reason this SDK does not know (`@unknown default`).
        case unrecognized
    }
}

#if canImport(FoundationModels)
/// Maps Apple `SystemLanguageModel.Availability` onto ``FoundationModelsAvailability``.
enum FoundationModelsAvailabilityMapping: Sendable {
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    static func map(
        _ apple: SystemLanguageModel.Availability
    ) -> FoundationModelsAvailability {
        switch apple {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            .unavailable(.modelNotReady)
        @unknown default:
            .unavailable(.unrecognized)
        }
    }
}
#endif
