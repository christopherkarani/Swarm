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
