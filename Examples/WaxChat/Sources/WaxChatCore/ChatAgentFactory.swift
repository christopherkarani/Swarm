// ChatAgentFactory.swift
// WaxChat — agent construction: Foundation Models / demo provider, websearch, Wax memory.

import Foundation
import Swarm

/// Configuration for building a WaxChat agent.
public struct ChatAgentConfiguration: Sendable {
    /// When true, use the deterministic scripted inference provider.
    public var demoMode: Bool
    /// Persistent Wax memory store URL.
    public var waxStoreURL: URL
    /// WebSearchTool local artifact store URL.
    public var webSearchStoreURL: URL
    /// Optional Tavily API key for live websearch. Falls back to `TAVILY_API_KEY`.
    /// Pass `""` to force offline websearch (no env fallback).
    public var webSearchAPIKey: String?
    /// System instructions for the agent.
    public var instructions: String
    /// Display name for agent configuration.
    public var agentName: String

    public init(
        demoMode: Bool,
        waxStoreURL: URL,
        webSearchStoreURL: URL,
        webSearchAPIKey: String? = nil,
        instructions: String = ChatAgentConfiguration.defaultInstructions,
        agentName: String = "WaxChat"
    ) {
        self.demoMode = demoMode
        self.waxStoreURL = waxStoreURL
        self.webSearchStoreURL = webSearchStoreURL
        self.webSearchAPIKey = webSearchAPIKey
        self.instructions = instructions
        self.agentName = agentName
    }

    public static let defaultInstructions = """
    You are a helpful on-device assistant with durable Wax memory and websearch.
    Prefer the websearch tool when the user needs current or external information.
    Recall facts from Wax memory when the user asks about earlier conversation.
    """

    /// Builds configuration with per-run temporary store paths (tests / isolated demos).
    ///
    /// Demo mode forces an empty websearch key so the tool path stays offline-deterministic
    /// (local/empty results) even if `TAVILY_API_KEY` is present in the environment.
    public static func temporary(demoMode: Bool) -> ChatAgentConfiguration {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaxChat-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ChatAgentConfiguration(
            demoMode: demoMode,
            waxStoreURL: root.appendingPathComponent("wax-memory.mv2s"),
            webSearchStoreURL: root.appendingPathComponent("WebMemory", isDirectory: true),
            webSearchAPIKey: demoMode ? "" : ProcessInfo.processInfo.environment["TAVILY_API_KEY"]
        )
    }

    /// Application Support store for interactive live use.
    public static func appSupport(demoMode: Bool) -> ChatAgentConfiguration {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = base
            .appendingPathComponent("WaxChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ChatAgentConfiguration(
            demoMode: demoMode,
            waxStoreURL: root.appendingPathComponent("wax-memory.mv2s"),
            webSearchStoreURL: root.appendingPathComponent("WebMemory", isDirectory: true),
            webSearchAPIKey: ProcessInfo.processInfo.environment["TAVILY_API_KEY"]
        )
    }
}

/// Resolved wiring produced by ``ChatAgentFactory``.
public struct ChatAgentBundle: Sendable {
    public let agent: Agent
    /// Concrete Wax store used as the agent's explicit memory (durable path).
    public let waxMemory: WaxMemory
    public let modeLabel: String
    public let waxStoreURL: URL
    public let webSearchStoreURL: URL
    public let toolNames: [String]
    public let usesWaxMemory: Bool
    public let usesWebSearch: Bool
    public let isDemoMode: Bool
}

/// Builds Swarm agents for on-device chat with Foundation Models, websearch, and Wax memory.
public enum ChatAgentFactory {
    /// Creates the inference provider for the given mode.
    ///
    /// - Demo: always returns ``DemoScriptedProvider``.
    /// - Live: uses ``FoundationModelsInferenceProvider`` when available; otherwise throws.
    public static func makeProvider(
        demoMode: Bool,
        instructions: String = ChatAgentConfiguration.defaultInstructions
    ) throws -> (provider: any InferenceProvider, modeLabel: String) {
        if demoMode {
            return (DemoScriptedProvider(), "demo (scripted)")
        }

        #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                if let fm = FoundationModelsInferenceProvider.ifAvailable(
                    configuration: .init(instructions: instructions)
                ) {
                    return (fm, "foundation-models (live)")
                }
                throw ChatAgentFactoryError.foundationModelsUnavailable(
                    "Foundation Models system model is not available. Re-run with --demo or enable Apple Intelligence."
                )
            } else {
                throw ChatAgentFactoryError.foundationModelsUnavailable(
                    "This OS is below Foundation Models availability. Use --demo."
                )
            }
        #else
            throw ChatAgentFactoryError.foundationModelsUnavailable(
                "FoundationModels is not importable on this platform. Use --demo."
            )
        #endif
    }

    /// Explicit websearch tool with a controllable local store (and optional live key).
    ///
    /// When `webSearchAPIKey` is non-nil (including empty string for demo), that value is used
    /// as-is. When nil, falls back to `TAVILY_API_KEY` for live interactive runs.
    public static func makeWebSearchTool(configuration: ChatAgentConfiguration) -> WebSearchTool {
        let resolvedKey: String?
        if let configured = configuration.webSearchAPIKey {
            let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedKey = trimmed.isEmpty ? nil : trimmed
        } else {
            let env = ProcessInfo.processInfo.environment["TAVILY_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedKey = (env?.isEmpty == false) ? env : nil
        }

        try? FileManager.default.createDirectory(
            at: configuration.webSearchStoreURL,
            withIntermediateDirectories: true
        )

        return WebSearchTool(
            configuration: WebSearchTool.Configuration(
                apiKey: resolvedKey,
                persistFetchedArtifacts: resolvedKey != nil,
                storeURL: configuration.webSearchStoreURL,
                enabled: true
            )
        )
    }

    /// Wax-backed durable memory at the configured store URL.
    public static func makeWaxMemory(url: URL) async throws -> WaxMemory {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return try await WaxMemory(url: url)
    }

    /// Full agent construction: provider + websearch tool + Wax memory.
    public static func makeAgent(configuration: ChatAgentConfiguration) async throws -> ChatAgentBundle {
        let (provider, modeLabel) = try makeProvider(
            demoMode: configuration.demoMode,
            instructions: configuration.instructions
        )
        return try await makeAgent(configuration: configuration, provider: provider, modeLabel: modeLabel)
    }

    /// Agent construction with an injected provider (used by tests).
    public static func makeAgent(
        configuration: ChatAgentConfiguration,
        provider: any InferenceProvider,
        modeLabel: String
    ) async throws -> ChatAgentBundle {
        let waxMemory = try await makeWaxMemory(url: configuration.waxStoreURL)
        let webSearch = makeWebSearchTool(configuration: configuration)

        // WebSearchTool is AnyJSONTool; pass it via the tools array init so the
        // tool is explicitly registered (ToolBuilder's AnyJSONTool expression is internal).
        //
        // Explicit memory disables Swarm's defaultMemory auto-persist path, so
        // ChatSession always pairs this agent with an InMemorySession and syncs
        // session turns into `waxMemory` after each run.
        let agent = try Agent(
            tools: [webSearch],
            instructions: configuration.instructions,
            configuration: .default.name(configuration.agentName),
            memory: waxMemory,
            inferenceProvider: provider
        )

        let toolNames = agent.tools.map(\.name)
        let usesWebSearch = toolNames.contains { $0.lowercased() == "websearch" }

        return ChatAgentBundle(
            agent: agent,
            waxMemory: waxMemory,
            modeLabel: modeLabel,
            waxStoreURL: configuration.waxStoreURL,
            webSearchStoreURL: configuration.webSearchStoreURL,
            toolNames: toolNames,
            usesWaxMemory: true,
            usesWebSearch: usesWebSearch,
            isDemoMode: configuration.demoMode
        )
    }
}

public enum ChatAgentFactoryError: Error, CustomStringConvertible, Sendable {
    case foundationModelsUnavailable(String)

    public var description: String {
        switch self {
        case let .foundationModelsUnavailable(message):
            message
        }
    }
}
