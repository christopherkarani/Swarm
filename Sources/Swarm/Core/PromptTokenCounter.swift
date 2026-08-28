// PromptTokenCounter.swift
// Swarm Framework
//
// Shared prompt token counting abstraction for runtime budgeting.

import Foundation

/// A type that can count prompt tokens for an arbitrary text payload.
///
/// This is the shared runtime surface used by prompt budgeting, memory
/// retrieval, and prompt-envelope enforcement. It is intentionally narrow:
/// Swarm only needs text counting at the runtime boundary, not full model
/// encoding APIs.
public protocol PromptTokenCounter: Sendable {
    /// Counts tokens in a text payload.
    ///
    /// - Parameter text: The text to count.
    /// - Returns: The token count for the text.
    func countTokens(in text: String) async throws -> Int
}

public extension PromptTokenCounter {
    /// Counts tokens across multiple text fragments.
    func countTokens(in texts: [String]) async throws -> Int {
        var total = 0
        for text in texts {
            total += try await countTokens(in: text)
        }
        return total
    }
}

/// Default prompt token counter backed by Swarm's heuristic token estimator.
///
/// This is the fallback path when a provider-native counter is unavailable.
public struct EstimatedPromptTokenCounter: PromptTokenCounter, Sendable {
    public static let shared = EstimatedPromptTokenCounter()

    private let estimator: any TokenEstimator

    public init(estimator: any TokenEstimator = CharacterBasedTokenEstimator.shared) {
        self.estimator = estimator
    }

    public func countTokens(in text: String) async throws -> Int {
        estimator.estimateTokens(for: text)
    }
}

enum PromptTokenBudgeting {
    static func counter(_ fallback: (any PromptTokenCounter)? = nil) -> any PromptTokenCounter {
        fallback ?? AgentEnvironmentValues.current.promptTokenCounter
    }

    static func countTokens(
        in text: String,
        using counter: (any PromptTokenCounter)? = nil
    ) async -> Int {
        let resolvedCounter = Self.counter(counter)
        do {
            return try await resolvedCounter.countTokens(in: text)
        } catch {
            Log.memory.warning("PromptTokenBudgeting: token counting failed, falling back to heuristic: \(error.localizedDescription)")
            return CharacterBasedTokenEstimator.shared.estimateTokens(for: text)
        }
    }

    static func prefix(
        _ text: String,
        maxTokens: Int,
        using counter: (any PromptTokenCounter)? = nil
    ) async -> String {
        guard maxTokens > 0 else { return "" }

        if await countTokens(in: text, using: counter) <= maxTokens {
            return text
        }

        var lower = 0
        var upper = text.count
        var best = ""

        while lower <= upper {
            let mid = (lower + upper) / 2
            let candidate = prefix(text, maxCharacters: mid)
            if await countTokens(in: candidate, using: counter) <= maxTokens {
                best = candidate
                lower = mid + 1
            } else {
                upper = mid - 1
            }
        }

        return best
    }

    static func suffix(
        _ text: String,
        maxTokens: Int,
        using counter: (any PromptTokenCounter)? = nil
    ) async -> String {
        guard maxTokens > 0 else { return "" }

        if await countTokens(in: text, using: counter) <= maxTokens {
            return text
        }

        var lower = 0
        var upper = text.count
        var best = ""

        while lower <= upper {
            let mid = (lower + upper) / 2
            let candidate = suffix(text, maxCharacters: mid)
            if await countTokens(in: candidate, using: counter) <= maxTokens {
                best = candidate
                lower = mid + 1
            } else {
                upper = mid - 1
            }
        }

        return best
    }

    private static func prefix(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<end])
    }

    private static func suffix(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else { return text }
        let start = text.index(text.endIndex, offsetBy: -maxCharacters)
        return String(text[start...])
    }
}
