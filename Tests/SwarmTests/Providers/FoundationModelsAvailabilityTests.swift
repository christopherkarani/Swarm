import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Foundation Models availability")
struct FoundationModelsAvailabilityTests {
    @Test("frameworkUnavailable is the documented no-framework case")
    func frameworkUnavailableIsDocumentedNoFrameworkCase() {
        let missing = FoundationModelsAvailability.unavailable(.frameworkUnavailable)
        #expect(missing != .available)
        #expect(missing == .unavailable(.frameworkUnavailable))
    }

    @Test("unrecognized exists for Apple unknown default")
    func unrecognizedExistsForUnknownDefault() {
        #expect(FoundationModelsAvailability.unavailable(.unrecognized) != .available)
        #expect(
            FoundationModelsAvailability.unavailable(.unrecognized)
                == .unavailable(.unrecognized)
        )
    }

    @Test("unavailable reasons are the five documented cases (no PCC quota)")
    func unavailableReasonsAreTheFiveDocumentedCases() {
        #expect(
            FoundationModelsAvailability.UnavailableReason.allCases == [
                .deviceNotEligible,
                .appleIntelligenceNotEnabled,
                .modelNotReady,
                .frameworkUnavailable,
                .unrecognized,
            ]
        )
    }

    #if canImport(FoundationModels)
    @Test("isAvailable is true iff availability is available")
    func isAvailableIsTrueIffAvailabilityIsAvailable() {
        let availability = FoundationModelsInferenceProvider.availability
        #expect(FoundationModelsInferenceProvider.isAvailable == (availability == .available))
        #expect(
            availability
                == FoundationModelsAvailabilityMapping.map(
                    SystemLanguageModel.default.availability
                )
        )
    }

    @Test("mapper sends Apple available to Swarm available")
    func mapsAppleAvailableToSwarmAvailable() {
        #expect(FoundationModelsAvailabilityMapping.map(.available) == .available)
    }

    @Test(
        "mapper sends Apple unavailable reasons to matching Swarm reasons",
        arguments: [
            (
                SystemLanguageModel.Availability.unavailable(.deviceNotEligible),
                FoundationModelsAvailability.unavailable(.deviceNotEligible)
            ),
            (
                .unavailable(.appleIntelligenceNotEnabled),
                .unavailable(.appleIntelligenceNotEnabled)
            ),
            (
                .unavailable(.modelNotReady),
                .unavailable(.modelNotReady)
            ),
        ] as [(SystemLanguageModel.Availability, FoundationModelsAvailability)]
    )
    func mapsAppleUnavailableReasons(
        apple: SystemLanguageModel.Availability,
        swarm: FoundationModelsAvailability
    ) {
        #expect(FoundationModelsAvailabilityMapping.map(apple) == swarm)
    }

    @Test("ifAvailable returns nil when isAvailable is false")
    func ifAvailableAgreesWithIsAvailable() {
        let optional = FoundationModelsInferenceProvider.ifAvailable()
        if FoundationModelsInferenceProvider.isAvailable {
            #expect(optional != nil)
            #expect(FoundationModelsInferenceProvider.availability == .available)
        } else {
            #expect(optional == nil)
            #expect(FoundationModelsInferenceProvider.availability != .available)
        }
    }
    #endif
}
