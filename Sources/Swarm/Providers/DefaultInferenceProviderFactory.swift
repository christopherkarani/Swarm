// DefaultInferenceProviderFactory.swift
// Swarm Framework
//
// Opinionated default inference provider selection.
//
// Prefers first-class Apple Foundation Models (no Conduit) when available.

import Foundation

enum DefaultInferenceProviderFactory {
    /// Returns an on-device Foundation Models provider when the system model is available.
    ///
    /// This path is intentionally independent of the Integrations/Conduit trait so
    /// Apple-platform apps get a working default without pulling cloud provider stacks.
    static func makeFoundationModelsProviderIfAvailable() -> (any InferenceProvider)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            return FoundationModelsInferenceProvider.ifAvailable()
        }
        #endif
        return nil
    }
}
