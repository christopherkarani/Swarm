// TokenUsage.swift
// Swarm Framework
//
// Token usage statistics for inference calls.

import Foundation

// MARK: - TokenUsage

/// Token usage statistics for a generation.
///
/// Tracks input and output token counts for monitoring
/// and cost estimation purposes.
///
/// ``cachedInputTokens`` and ``reasoningTokens`` are breakdowns that only some
/// providers report. They are `nil` when the provider did not report them;
/// Swarm never estimates them.
///
/// ```swift
/// if let usage = result.tokenUsage {
///     print(usage.inputTokens, usage.cachedInputTokens ?? 0)
///     print(usage.outputTokens, usage.reasoningTokens ?? 0)
/// }
/// ```
public struct TokenUsage: Sendable, Equatable, Codable {
    /// Number of tokens in the input/prompt.
    public let inputTokens: Int

    /// Number of tokens in the output/response.
    public let outputTokens: Int

    /// How many of ``inputTokens`` the provider served from its prompt cache.
    ///
    /// Already counted in ``inputTokens``. `nil` when the provider did not
    /// report a cache breakdown. Sources: Apple Foundation Models
    /// `usage.input.cachedTokenCount` (OS 27) and OpenAI-compatible
    /// `usage.prompt_tokens_details.cached_tokens`.
    public let cachedInputTokens: Int?

    /// How many of ``outputTokens`` the model spent on reasoning.
    ///
    /// Already counted in ``outputTokens``. `nil` when the provider did not
    /// report a reasoning breakdown. Sources: Apple Foundation Models
    /// `usage.output.reasoningTokenCount` (OS 27) and OpenAI-compatible
    /// `usage.completion_tokens_details.reasoning_tokens`.
    public let reasoningTokens: Int?

    /// Total tokens used (input + output).
    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    /// Creates token usage statistics.
    /// - Parameters:
    ///   - inputTokens: Input token count.
    ///   - outputTokens: Output token count.
    ///   - cachedInputTokens: Input tokens served from the provider's prompt
    ///     cache, or `nil` when not reported.
    ///   - reasoningTokens: Output tokens spent on reasoning, or `nil` when
    ///     not reported.
    public init(
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningTokens = reasoningTokens
    }

    /// Returns the sum of this usage and `other`.
    ///
    /// Use this to accumulate provider-reported usage across tool-loop iterations
    /// or handoffs. Swarm never invents counts; callers should only merge values
    /// the provider actually returned.
    ///
    /// A breakdown (``cachedInputTokens``, ``reasoningTokens``) stays `nil`
    /// only when neither side reported it; otherwise a missing side counts
    /// as zero.
    public func merging(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cachedInputTokens: Self.sum(cachedInputTokens, other.cachedInputTokens),
            reasoningTokens: Self.sum(reasoningTokens, other.reasoningTokens)
        )
    }

    private static func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case let (lhs, rhs): (lhs ?? 0) + (rhs ?? 0)
        }
    }
}

// MARK: - TokenUsage + CustomStringConvertible

extension TokenUsage: CustomStringConvertible {
    public var description: String {
        var parts = ["input: \(inputTokens)"]
        if let cachedInputTokens {
            parts.append("cached: \(cachedInputTokens)")
        }
        parts.append("output: \(outputTokens)")
        if let reasoningTokens {
            parts.append("reasoning: \(reasoningTokens)")
        }
        parts.append("total: \(totalTokens)")
        return "TokenUsage(\(parts.joined(separator: ", ")))"
    }
}
