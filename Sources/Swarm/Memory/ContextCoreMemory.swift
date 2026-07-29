#if SWARM_INTEGRATIONS && canImport(ContextCore)
// ContextCoreMemory.swift
// Swarm Framework
//
// ContextCore-backed memory implementation used by default in Swarm.
// Apple-only: ContextCore is trait-linked only on Apple platforms (Metal/CoreML).

import ContextCore
import Foundation

// MARK: - ContextCoreMemoryConfiguration

/// Configuration for the default ContextCore-backed memory store.
public struct ContextCoreMemoryConfiguration: Sendable {
    public static let `default` = ContextCoreMemoryConfiguration()

    public var contextConfiguration: ContextCore.ContextConfiguration
    public var promptTitle: String
    public var promptGuidance: String?
    public var allowsAutomaticSessionSeeding: Bool

    public init(
        contextConfiguration: ContextCore.ContextConfiguration = .default,
        promptTitle: String = "ContextCore Memory Context (primary)",
        promptGuidance: String? = "Use ContextCore memory context as the primary working memory source.",
        allowsAutomaticSessionSeeding: Bool = true
    ) {
        self.contextConfiguration = contextConfiguration
        self.promptTitle = promptTitle
        self.promptGuidance = promptGuidance
        self.allowsAutomaticSessionSeeding = allowsAutomaticSessionSeeding
    }
}

// MARK: - ContextCoreMemory

/// Swarm memory adapter backed by ContextCore's agent context engine.
///
/// Swarm uses this implementation as the primary working-memory layer inside
/// its default composite memory stack.
public actor ContextCoreMemory: Memory, MemoryPromptDescriptor, MemorySessionLifecycle, MemorySessionImportPolicy, MemorySessionReplayAware {
    public nonisolated let memoryPromptTitle: String
    public nonisolated let memoryPromptGuidance: String?
    public nonisolated let memoryPriority: MemoryPriorityHint = .primary
    public nonisolated let allowsAutomaticSessionSeeding: Bool

    public var count: Int {
        messages.count
    }

    public var isEmpty: Bool {
        messages.isEmpty
    }

    public init(configuration: ContextCoreMemoryConfiguration = .default) throws {
        try self.init(
            configuration: configuration,
            endSession: { context in
                try await context.endSession()
            }
        )
    }

    init(
        configuration: ContextCoreMemoryConfiguration = .default,
        endSession: @escaping @Sendable (ContextCore.AgentContext) async throws -> Void
    ) throws {
        self.configuration = configuration
        self.memoryPromptTitle = configuration.promptTitle
        self.memoryPromptGuidance = configuration.promptGuidance
        self.allowsAutomaticSessionSeeding = configuration.allowsAutomaticSessionSeeding
        self.contextFactory = {
            try ContextCore.AgentContext(configuration: configuration.contextConfiguration)
        }
        self.context = try contextFactory()
        self.endSession = endSession
    }

    public func add(_ message: MemoryMessage) async {
        messages.append(message)
        if sessionIsReady {
            await append(message)
        }
    }

    public func context(for query: String, tokenLimit: Int) async -> String {
        guard tokenLimit > 0 else {
            return ""
        }

        await ensureSessionReady()

        do {
            let window = try await context.buildWindow(
                currentTask: query,
                maxTokens: tokenLimit
            )
            return window.formatted(style: .custom(template: "[{role}]: {content}"))
        } catch {
            return MemoryMessage.formatContext(messages, tokenLimit: tokenLimit)
        }
    }

    public func allMessages() async -> [MemoryMessage] {
        messages
    }

    public func clear() async {
        if sessionIsReady {
            do {
                try await endSession(context)
            } catch {
                // Best-effort shutdown. Clearing Swarm's local buffer remains authoritative.
            }
        }

        messages.removeAll()
        sessionIsReady = false
    }

    public func beginMemorySession() async {
        await ensureSessionReady()
    }

    public func endMemorySession() async {
        guard sessionIsReady else {
            return
        }

        do {
            try await endSession(context)
        } catch {
            // Best-effort shutdown. The local buffer stays authoritative.
        }

        sessionIsReady = false
    }

    public func importSessionHistory(_ messages: [MemoryMessage]) async {
        guard !messages.isEmpty else { return }
        for message in messages {
            await add(message)
        }
    }

    private let configuration: ContextCoreMemoryConfiguration
    private let contextFactory: @Sendable () throws -> ContextCore.AgentContext
    private let endSession: @Sendable (ContextCore.AgentContext) async throws -> Void
    private var context: ContextCore.AgentContext
    private var sessionIsReady = false
    private var messages: [MemoryMessage] = []

    private func ensureSessionReady() async {
        guard sessionIsReady == false else {
            return
        }

        do {
            context = try contextFactory()
            try await context.beginSession()
            for message in messages {
                try await context.append(turn: makeTurn(from: message))
            }
            sessionIsReady = true
        } catch {
            sessionIsReady = false
        }
    }

    private func append(_ message: MemoryMessage) async {
        do {
            try await context.append(turn: makeTurn(from: message))
        } catch {
            sessionIsReady = false
        }
    }

    private func makeTurn(from message: MemoryMessage) -> ContextCore.Turn {
        let role: ContextCore.TurnRole = switch message.role {
        case .user: .user
        case .assistant: .assistant
        case .system: .system
        case .tool: .tool
        }

        return ContextCore.Turn(
            id: message.id,
            role: role,
            content: message.content,
            timestamp: message.timestamp,
            tokenCount: 0,
            embedding: nil,
            metadata: message.metadata
        )
    }
}
#endif
