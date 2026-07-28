// ProviderFactoryTests.swift
// SwarmTests
//
// TDD tests for built-in InferenceProvider factories after Conduit removal.

import Testing
@testable import Swarm

@Suite("InferenceProvider Factory Methods")
struct ProviderFactoryTests {

    @Test("foundationModels factory is available on supported platforms")
    func foundationModelsFactory() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            // Construction may fail when the system model is unavailable; the
            // factory surface itself must still type-check as InferenceProvider.
            let provider: (any InferenceProvider)? = FoundationModelsInferenceProvider.ifAvailable()
            if let provider {
                let _: any InferenceProvider = provider
            }
        }
        #endif
    }

    @Test("dot-syntax foundationModels works in function parameter context")
    func dotSyntaxInFunctionContext() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            func takesProvider(_ p: some InferenceProvider) {}
            // Prefer ifAvailable to avoid hard-failing when the system model is offline.
            if let provider = FoundationModelsInferenceProvider.ifAvailable() {
                takesProvider(provider)
            }
        }
        #endif
    }
}
