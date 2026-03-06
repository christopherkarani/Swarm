// ProviderFactories.swift
// Swarm Framework
//
// V3 dot-syntax provider factories.
// Most factories already exist in LLM.swift (line 160+).
// This file adds the missing .ollama entry point.

import Foundation

// MARK: - Ollama dot-syntax on ConduitProviderSelection

public extension InferenceProvider where Self == ConduitProviderSelection {
    /// Ollama local inference provider.
    ///
    /// ```swift
    /// let agent = AgentV3("assistant")
    ///     .provider(.ollama(model: "llama3.2"))
    /// ```
    static func ollama(
        model: String = "llama3.2",
        settings: OllamaSettings = .default
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model, settings: settings)
    }
}
