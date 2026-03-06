// MemoryOption.swift
// Swarm Framework
//
// Memory configuration enum with dot-syntax for ergonomic agent setup.

import Foundation

/// Memory configuration for an agent, using dot-syntax.
///
/// ```swift
/// agent.memory(.conversation(limit: 50))
/// agent.memory(.vector(dimensions: 384))
/// agent.memory(.none)
/// ```
public enum MemoryOption: Sendable {
    /// No memory.
    case none

    /// Rolling conversation buffer with message limit.
    case conversation(limit: Int = 50)

    /// Fixed message count window.
    case slidingWindow(count: Int = 20)

    /// Embedding-based semantic retrieval.
    case vector(dimensions: Int = 384, topK: Int = 5)

    /// LLM-compressed conversation history.
    case summary(maxTokens: Int = 2000)

    /// SwiftData-backed persistent storage.
    case persistent(storeName: String = "SwarmMemory")

    /// Hybrid multi-strategy composition.
    case hybrid([MemoryOption])

    /// Custom Memory protocol conformance.
    case custom(any Memory)
}

// MARK: - Resolution

extension MemoryOption {
    /// Resolves this option to a concrete `Memory` instance, or `nil` for `.none`.
    ///
    /// Some cases (`.vector`, `.summary`, `.persistent`) require additional
    /// dependencies and return `nil` from this basic resolver — the runtime
    /// handles full resolution with dependency injection.
    public func resolve() -> (any Memory)? {
        switch self {
        case .none:
            return nil
        case .conversation(let limit):
            return ConversationMemory(maxMessages: limit)
        case .slidingWindow(let count):
            return SlidingWindowMemory(maxTokens: count * 200) // ~200 tokens per message estimate
        case .custom(let memory):
            return memory
        case .hybrid(let options):
            let resolved = options.compactMap { $0.resolve() }
            guard !resolved.isEmpty else { return nil }
            return resolved.first // Simplified — full HybridMemory in future
        default:
            return nil
        }
    }
}
