// AgentConfiguration+InferenceOptions.swift
// Swarm Framework
//
// Bridges AgentConfiguration + ModelSettings to InferenceOptions.

import Foundation

package extension AgentConfiguration {
    /// Resolves this agent configuration into provider-facing inference options.
    ///
    /// ``modelSettings`` is the only source for sampling parameters; `nil`
    /// fields fall back to the ``InferenceOptions`` defaults.
    var inferenceOptions: InferenceOptions {
        let defaults = InferenceOptions.default
        let settings = modelSettings
        return InferenceOptions(
            temperature: settings.temperature ?? defaults.temperature,
            maxTokens: settings.maxTokens ?? defaults.maxTokens,
            stopSequences: settings.stopSequences ?? defaults.stopSequences,
            topP: settings.topP,
            topK: settings.topK,
            presencePenalty: settings.presencePenalty,
            frequencyPenalty: settings.frequencyPenalty,
            toolChoice: settings.toolChoice,
            seed: settings.seed,
            parallelToolCalls: settings.parallelToolCalls ?? parallelToolCalls,
            truncation: settings.truncation,
            verbosity: settings.verbosity,
            providerSettings: settings.providerSettings,
            // AgentTurnDependencyResolver.inferenceOptions owns continuation.
            previousResponseId: nil,
            reasoning: settings.reasoning
        )
    }
}
