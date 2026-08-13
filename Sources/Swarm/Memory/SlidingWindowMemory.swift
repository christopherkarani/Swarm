// SlidingWindowMemory.swift
// Swarm Framework
//
// Token-aware memory that maintains messages within a token budget.

import Foundation

// MARK: - SlidingWindowMemory

/// A token-aware memory that maintains messages within a token budget.
///
/// `SlidingWindowMemory` automatically manages the context window by
/// removing the oldest messages when the total token count exceeds
/// the configured limit. This ensures the memory always fits within
/// the LLM's context window.
///
/// ## Usage
///
/// ```swift
/// let memory = SlidingWindowMemory(maxTokens: 4000)
/// await memory.add(.user("Long message..."))
/// // Automatically removes old messages if tokens exceed 4000
/// ```
///
/// ## Token Estimation
///
/// By default uses character-based estimation (chars / 4).
/// For production use with specific models, provide a custom `TokenEstimator`.
public actor SlidingWindowMemory: Memory {
    // MARK: Public

    /// Maximum tokens to retain.
    public let maxTokens: Int

    public var count: Int {
        messages.count
    }

    /// Whether the memory contains no messages.
    public var isEmpty: Bool { messages.isEmpty }

    // MARK: - Token Information

    /// Current estimated total token count.
    public var tokenCount: Int {
        currentTokenCount
    }

    /// Remaining token budget.
    public var remainingTokens: Int {
        max(0, maxTokens - currentTokenCount)
    }

    /// Whether the memory is at or near capacity (>90% full).
    public var isNearCapacity: Bool {
        Double(currentTokenCount) / Double(maxTokens) > 0.9
    }

    /// Creates a new sliding window memory.
    ///
    /// - Parameters:
    ///   - maxTokens: Maximum tokens to retain (default: 4000).
    ///     Estimated with ``CharacterBasedTokenEstimator`` (~4 characters per
    ///     token) unless `tokenEstimator` is overridden.
    ///   - tokenEstimator: Estimator for token counting.
    public init(
        maxTokens: Int = 4000,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) {
        self.maxTokens = max(100, maxTokens)
        self.tokenEstimator = tokenEstimator
    }

    // MARK: - AgentMemory Conformance

    public func add(_ message: MemoryMessage) async {
        let messageTokens = tokenEstimator.estimateTokens(for: message.formattedContent)

        messages.append(message)
        currentTokenCount += messageTokens

        // Remove oldest messages until within budget
        while currentTokenCount > maxTokens, messages.count > 1 {
            let removed = messages.removeFirst()
            let removedTokens = tokenEstimator.estimateTokens(for: removed.formattedContent)
            currentTokenCount -= removedTokens
        }

        if currentTokenCount > maxTokens, let latest = messages.last {
            let truncated = truncate(latest, toFit: maxTokens)
            messages[messages.count - 1] = truncated
            currentTokenCount = tokenEstimator.estimateTokens(for: truncated.formattedContent)
        }

        // Periodic recalibration to prevent token count drift
        operationsSinceRecalibration += 1
        if operationsSinceRecalibration >= recalibrationInterval {
            recalibrateTokenCount()
            operationsSinceRecalibration = 0
        }
    }

    public func context(for _: String, tokenLimit: Int) async -> String {
        let effectiveLimit = min(tokenLimit, maxTokens)
        return MemoryMessage.formatContext(messages, tokenLimit: effectiveLimit, tokenEstimator: tokenEstimator)
    }

    public func allMessages() async -> [MemoryMessage] {
        messages
    }

    public func clear() async {
        messages.removeAll()
        currentTokenCount = 0
        operationsSinceRecalibration = 0
    }

    private func truncate(_ message: MemoryMessage, toFit tokenLimit: Int) -> MemoryMessage {
        var lowerBound = 0
        var upperBound = message.content.count
        var bestContent = ""

        while lowerBound <= upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            let candidateContent = String(message.content.prefix(midpoint))
            let candidate = MemoryMessage(
                id: message.id,
                role: message.role,
                content: candidateContent,
                timestamp: message.timestamp,
                metadata: message.metadata
            )

            if tokenEstimator.estimateTokens(for: candidate.formattedContent) <= tokenLimit {
                bestContent = candidateContent
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint - 1
            }
        }

        return MemoryMessage(
            id: message.id,
            role: message.role,
            content: bestContent,
            timestamp: message.timestamp,
            metadata: message.metadata
        )
    }

    // MARK: Private

    /// Token estimator for counting.
    private let tokenEstimator: any TokenEstimator

    /// Internal message storage.
    private var messages: [MemoryMessage] = []

    /// Current estimated token count.
    private var currentTokenCount: Int = 0

    /// Number of add operations since last recalibration.
    private var operationsSinceRecalibration: Int = 0

    /// How often to recalibrate token count to prevent drift.
    private let recalibrationInterval: Int = 100

    /// Recalibrates token count by recalculating from all messages.
    ///
    /// Called automatically to prevent drift from cumulative estimation errors.
    private func recalibrateTokenCount() {
        currentTokenCount = messages.reduce(0) { total, message in
            total + tokenEstimator.estimateTokens(for: message.formattedContent)
        }
    }
}

// MARK: - Batch Operations

public extension SlidingWindowMemory {
    /// Adds multiple messages at once.
    ///
    /// - Parameter newMessages: Messages to add in order.
    func addAll(_ newMessages: [MemoryMessage]) async {
        for message in newMessages {
            await add(message)
        }
    }

    /// Returns messages that would fit within a specific token budget.
    ///
    /// - Parameter tokenBudget: Maximum tokens to include.
    /// - Returns: Recent messages fitting within the budget.
    func getMessages(withinTokenBudget tokenBudget: Int) async -> [MemoryMessage] {
        var result: [MemoryMessage] = []
        var usedTokens = 0

        for message in messages.reversed() {
            let messageTokens = tokenEstimator.estimateTokens(for: message.formattedContent)
            if usedTokens + messageTokens <= tokenBudget {
                result.append(message)
                usedTokens += messageTokens
            } else {
                break
            }
        }

        return result.reversed()
    }
}

// MARK: - Diagnostic Information

public extension SlidingWindowMemory {
    /// Returns diagnostic information about memory state.
    func diagnostics() async -> SlidingWindowDiagnostics {
        SlidingWindowDiagnostics(
            messageCount: messages.count,
            currentTokens: currentTokenCount,
            maxTokens: maxTokens,
            utilizationPercent: Double(currentTokenCount) / Double(maxTokens) * 100,
            remainingTokens: remainingTokens,
            averageTokensPerMessage: messages.isEmpty ? 0 : Double(currentTokenCount) / Double(messages.count)
        )
    }
}

// MARK: - SlidingWindowDiagnostics

/// Diagnostic information for sliding window memory.
public struct SlidingWindowDiagnostics: Sendable {
    /// Current number of messages stored.
    public let messageCount: Int
    /// Current estimated token count.
    public let currentTokens: Int
    /// Maximum tokens allowed.
    public let maxTokens: Int
    /// Percentage of token capacity used.
    public let utilizationPercent: Double
    /// Tokens remaining before eviction starts.
    public let remainingTokens: Int
    /// Average tokens per message.
    public let averageTokensPerMessage: Double
}

// MARK: - Recalculation

public extension SlidingWindowMemory {
    /// Recalculates the token count from scratch.
    ///
    /// Useful if the token estimator has changed or if you suspect
    /// the count has drifted due to estimation errors.
    func recalculateTokenCount() async {
        currentTokenCount = messages.reduce(0) { total, message in
            total + tokenEstimator.estimateTokens(for: message.formattedContent)
        }
    }
}
