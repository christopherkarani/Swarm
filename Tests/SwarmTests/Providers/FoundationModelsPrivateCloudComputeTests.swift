import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Foundation Models Private Cloud Compute")
struct FoundationModelsPrivateCloudComputeTests {
    #if canImport(FoundationModels)
    @Test("PCC availability requires availability plus quota headroom")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func pccAvailabilityRequiresQuotaHeadroom() {
        let model = PrivateCloudComputeLanguageModel()
        #expect(
            FoundationModelsInferenceProvider.isPrivateCloudComputeAvailable(model)
                == (model.availability == .available && !model.quotaUsage.isLimitReached)
        )
    }

    @Test("PCC ifAvailable is nil exactly when unavailable")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func pccIfAvailableMatchesAvailability() {
        let model = PrivateCloudComputeLanguageModel()
        let provider = FoundationModelsInferenceProvider.privateCloudComputeIfAvailable(model: model)
        #expect(
            (provider != nil)
                == FoundationModelsInferenceProvider.isPrivateCloudComputeAvailable(model)
        )
        if let provider {
            #expect(provider.modelName == "privateCloudComputeLanguageModel")
        }
    }

    @Test("PCC dot-syntax reports the PCC model name")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func pccDotSyntaxReportsModelName() {
        let provider: FoundationModelsInferenceProvider = .privateCloudCompute()
        #expect(provider.modelName == "privateCloudComputeLanguageModel")
        #expect(provider.capabilities.contains(.privateInference) == false)
    }

    @Test("PCC factory agrees with availability")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func pccFactoryAgreesWithAvailability() {
        let provider = DefaultInferenceProviderFactory.makePrivateCloudComputeProviderIfAvailable()
        #expect(
            (provider != nil) == FoundationModelsInferenceProvider.isPrivateCloudComputeAvailable()
        )
    }

    @Test("PCC session model uses the fallback context budget")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func pccSessionModelUsesFallbackContextBudget() {
        let size = FoundationModelsSessionModel.contextSize(
            for: PrivateCloudComputeLanguageModel()
        )
        #expect(size == FoundationModelsContextBudget.fallbackContextSize)
    }
    #endif
}
