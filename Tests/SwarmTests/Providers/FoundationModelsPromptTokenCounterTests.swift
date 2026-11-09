import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels

/// The provider exposes Apple's exact tokenizer only for on-device sessions.
/// Construction never touches the model, so these run without Apple
/// Intelligence; live counting is covered by the opt-in live suites.
@Suite("Foundation Models prompt token counter")
struct FoundationModelsPromptTokenCounterTests {
    @Test("on-device provider exposes the native counter on OS 26.4+, nil before")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func onDeviceCounterFollowsOSVersion() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider()
        if #available(macOS 26.4, iOS 26.4, visionOS 26.4, *) {
            #expect(provider.promptTokenCounter is FoundationModelsPromptTokenCounter)
        } else {
            #expect(provider.promptTokenCounter == nil)
        }
        #endif
    }

    @Test("SystemLanguageModel passed as a LanguageModel keeps the native counter")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func languageModelSystemBackingKeepsCounter() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(model: SystemLanguageModel.default)
        #expect(provider.promptTokenCounter is FoundationModelsPromptTokenCounter)
        #endif
    }

    @Test("Private Cloud Compute keeps the environment heuristic counter")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func privateCloudComputeHasNoNativeCounter() {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let provider = FoundationModelsInferenceProvider(model: PrivateCloudComputeLanguageModel())
        #expect(provider.promptTokenCounter == nil)
        #endif
    }
}
#endif
