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

/// Optional prompt metadata for memory-backed context.
///
/// ``Memory`` now includes these properties with defaults. This marker remains
/// for source compatibility.
@available(*, deprecated, message: "Prompt labeling properties are defaulted Memory requirements")
public protocol MemoryPromptDescriptor: Sendable {}
