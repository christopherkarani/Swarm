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
/// await Swarm.configure(provider: myCustomProvider)
/// ```
///
/// When no provider is configured, Swarm uses Apple Foundation Models when
/// available. For custom backends, inject any type that conforms to
/// ``InferenceProvider``.
public extension Swarm {
    // MARK: - Internal Storage

    actor Configuration {
        static let shared = Configuration()

        private(set) var provider: (any InferenceProvider)?
        private(set) var web: WebSearchTool.Configuration?

        func setProvider(_ provider: some InferenceProvider) {
            self.provider = provider
        }

        func setWebConfiguration(_ configuration: WebSearchTool.Configuration) {
            web = configuration
        }

        func reset() {
            provider = nil
            web = nil
        }
    }

    /// The currently configured default provider, if any.
    static var defaultProvider: (any InferenceProvider)? {
        get async { await Configuration.shared.provider }
    }

    /// The currently configured default web-search configuration, if any.
    static var webConfiguration: WebSearchTool.Configuration? {
        get async { await Configuration.shared.web }
    }

    // MARK: - Public API

    /// Sets the default inference provider for all agents.
    ///
    /// Agents resolve providers in this order:
    /// 1. Explicit provider on the agent
    /// 2. TaskLocal via `.environment(\.inferenceProvider, ...)`
    /// 3. `Swarm.defaultProvider` (set here)
    /// 4. Foundation Models (on Apple platforms when the system model is available)
    /// 5. Throw `AgentError.inferenceProviderUnavailable`
    static func configure(provider: some InferenceProvider) async {
        await Configuration.shared.setProvider(provider)
    }

    /// Sets the default web-search configuration for all agents.
    ///
    /// Agents resolve web configuration in this order:
    /// 1. Explicit `websearch` tool already attached to the agent
    /// 2. TaskLocal via `.environment(\.webSearch, ...)`
    /// 3. `Swarm.webConfiguration` (set here)
    /// 4. No ambient web tool
    static func configure(web configuration: WebSearchTool.Configuration) async {
        await Configuration.shared.setWebConfiguration(configuration)
    }

    /// Resets all configuration. Intended for testing only.
    static func reset() async {
        await Configuration.shared.reset()
    }
}
