// SwarmConfiguration.swift
// Swarm Framework
//
// Global configuration entry point for the Swarm framework.

import Foundation

/// Global configuration for the Swarm framework.
///
/// Call `Swarm.configure(provider:)` once at app launch to set the default
/// inference provider for all agents:
///
/// ```swift
/// await Swarm.configure(provider: AnthropicProvider(apiKey: key))
/// ```
///
/// For hybrid setups where a cloud provider should take priority for tool
/// calling while Foundation Models remain available as a fallback:
///
/// ```swift
/// await Swarm.configure(cloudProvider: AnthropicProvider(apiKey: key))
/// ```
public extension Swarm {
    // MARK: - Internal Storage

    actor Configuration {
        static let shared = Configuration()

        private(set) var provider: (any InferenceProvider)?
        private(set) var cloud: (any InferenceProvider)?

        func setProvider(_ provider: some InferenceProvider) {
            self.provider = provider
        }

        func setCloudProvider(_ cloudProvider: some InferenceProvider) {
            cloud = cloudProvider
        }

        func reset() {
            provider = nil
            cloud = nil
        }
    }

    /// The currently configured default provider, if any.
    static var defaultProvider: (any InferenceProvider)? {
        get async { await Configuration.shared.provider }
    }

    /// The currently configured higher-priority provider for tool-calling flows, if any.
    static var cloudProvider: (any InferenceProvider)? {
        get async { await Configuration.shared.cloud }
    }

    // MARK: - Public API

    /// Sets the default inference provider for all agents.
    ///
    /// Agents resolve providers in this order:
    /// 1. Explicit provider on the agent
    /// 2. TaskLocal via `.environment(\.inferenceProvider, ...)`
    /// 3. `Swarm.defaultProvider` (set here)
    /// 4. `Swarm.cloudProvider` (when tool calling is required and a cloud provider is configured)
    /// 5. Foundation Models (on Apple platform, including prompt-based tool emulation when selected)
    /// 6. Throw `AgentError.inferenceProviderUnavailable`
    static func configure(provider: some InferenceProvider) async {
        await Configuration.shared.setProvider(provider)
    }

    /// Sets a cloud provider for tool-calling agents.
    ///
    /// Use this to configure a higher-priority provider (Anthropic, OpenAI,
    /// Ollama) for agents that use tools when you want native/provider-managed
    /// tool calling. If no cloud provider is configured, Apple Foundation
    /// Models can still service tool requests through Swarm's prompt-based
    /// emulation path when available.
    static func configure(cloudProvider: some InferenceProvider) async {
        await Configuration.shared.setCloudProvider(cloudProvider)
    }

    /// Resets all configuration. Intended for testing only.
    static func reset() async {
        await Configuration.shared.reset()
    }
}
