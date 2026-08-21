// MemoryPromptDescriptor.swift
// Swarm Framework
//
// Optional prompt metadata for memory implementations.

import Foundation

/// Priority hint for memory context usage in prompts.
public enum MemoryPriorityHint: Sendable {
    case primary
    case secondary
}

/// Prompt metadata describing how a memory's retrieved context should be
/// presented to the model.
///
/// Return this from ``Memory/memoryPromptMetadata`` to label memory context in
/// system prompts and to instruct the model on how to treat it.
public struct MemoryPromptMetadata: Sendable {
    /// The label/title to display above memory context in prompts.
    public var title: String

    /// Optional guidance text to instruct how memory should be used.
    public var guidance: String?

    /// Whether this memory should be treated as primary or secondary context.
    public var priority: MemoryPriorityHint

    public init(title: String, guidance: String?, priority: MemoryPriorityHint) {
        self.title = title
        self.guidance = guidance
        self.priority = priority
    }
}

public extension Memory {
    /// Default prompt metadata: `nil`, which renders memory context under the
    /// generic "Relevant Context from Memory" heading with no guidance text.
    nonisolated var memoryPromptMetadata: MemoryPromptMetadata? { nil }
}

/// Optional prompt metadata for memory-backed context.
///
/// Prompt metadata is now a defaulted requirement on ``Memory``; return it from
/// ``Memory/memoryPromptMetadata`` instead of conforming to this protocol.
@available(*, deprecated, message: "Return MemoryPromptMetadata from your Memory conformance's memoryPromptMetadata instead.")
public protocol MemoryPromptDescriptor: Sendable {
    /// The label/title to display above memory context in prompts.
    var memoryPromptTitle: String { get }

    /// Optional guidance text to instruct how memory should be used.
    var memoryPromptGuidance: String? { get }

    /// Whether this memory should be treated as primary or secondary context.
    var memoryPriority: MemoryPriorityHint { get }
}

public extension Memory where Self: MemoryPromptDescriptor {
    /// Bridges deprecated ``MemoryPromptDescriptor`` conformances onto the
    /// defaulted ``Memory/memoryPromptMetadata`` requirement so existing
    /// conformers keep their prompt labels without source changes.
    nonisolated var memoryPromptMetadata: MemoryPromptMetadata? {
        MemoryPromptMetadata(
            title: memoryPromptTitle,
            guidance: memoryPromptGuidance,
            priority: memoryPriority
        )
    }
}
