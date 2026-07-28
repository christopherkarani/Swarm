// DefaultInferenceProviderFactory.swift
// Swarm Framework
//
// Opinionated default inference provider selection.
//
// Prefers Apple Foundation Models when the system model is available.

import Foundation

enum DefaultInferenceProviderFactory {
    /// Returns an on-device Foundation Models provider when the system model is available.
    ///
    /// This is the only built-in inference backend. Custom backends inject
    /// ``InferenceProvider`` explicitly or via `Swarm.configure(provider:)`.
    static func makeFoundationModelsProviderIfAvailable() -> (any InferenceProvider)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            return FoundationModelsInferenceProvider.ifAvailable()
        }
        #endif
        return nil
    }
}
