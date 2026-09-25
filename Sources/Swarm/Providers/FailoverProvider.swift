// FailoverProvider.swift
// Swarm Framework
//
// Ordered provider failover for inference resilience.

import Foundation

/// An inference provider that fails over across an ordered chain.
///
/// `FailoverProvider` tries `primary` first, then each provider in
/// `fallbacks` in order, advancing only when the failure passes
/// `shouldFailover` (default: ``InferenceRetryability/isRetryable(_:)``).
/// Permanent failures — bad credentials, invalid input, guardrail
/// rejections — rethrow immediately without touching the next provider,
/// because repeating the same request elsewhere cannot help. Cancelled
/// tasks never advance, even under a custom `shouldFailover`.
///
/// When every provider fails, the **last** error rethrows, preserving its
/// type and retryability for upstream handling — for example, an
/// ``Agent``-level ``RetryPolicy`` that retries the whole chain after a
/// backoff.
///
/// Only the core message-based methods fail over directly; prompt,
/// streaming, and prompt-structured variants inherit failover through the
/// ``InferenceProvider`` protocol defaults, which funnel into them.
///
/// ## Example
///
/// ```swift
/// let provider = FailoverProvider(
///     primary: groqProvider,
///     fallbacks: [geminiProvider],
///     onFailover: { index, error in
///         print("provider \(index) failed (\(error)); trying next")
///     }
/// )
/// let agent = try Agent("Be concise.", inferenceProvider: provider)
/// ```
public struct FailoverProvider: InferenceProvider, Sendable {
    /// The provider tried first.
    public let primary: any InferenceProvider

    /// Providers tried in order after `primary` fails retryably.
    public let fallbacks: [any InferenceProvider]

    /// Decides whether a failure advances to the next provider.
    ///
    /// Default: ``InferenceRetryability/isRetryable(_:)``. A custom
    /// predicate may widen failover, but cancelled tasks still rethrow
    /// immediately and never advance.
    public let shouldFailover: @Sendable (Error) -> Bool

    /// Called before advancing past a failed provider.
    ///
    /// Receives the failed provider's index (`0` is `primary`) and the
    /// error that triggered the advance.
    public let onFailover: (@Sendable (Int, Error) async -> Void)?

    /// Advertised features of `primary`.
    ///
    /// Failover preserves the primary contract; fallbacks should satisfy
    /// the same capabilities.
    public var capabilities: InferenceProviderCapabilities {
        primary.capabilities
    }

    /// Token counter of `primary`, when it has one.
    public var promptTokenCounter: (any PromptTokenCounter)? {
        primary.promptTokenCounter
    }

    /// Creates a failover chain.
    ///
    /// - Parameters:
    ///   - primary: The provider tried first.
    ///   - fallbacks: Providers tried in order after retryable failures. Default: `[]`.
    ///   - shouldFailover: Failover gate. Default: ``InferenceRetryability/isRetryable(_:)``.
    ///   - onFailover: Optional callback invoked before each advance.
    public init(
        primary: any InferenceProvider,
        fallbacks: [any InferenceProvider] = [],
        shouldFailover: @escaping @Sendable (Error) -> Bool = InferenceRetryability.isRetryable,
        onFailover: (@Sendable (Int, Error) async -> Void)? = nil
    ) {
        self.primary = primary
        self.fallbacks = fallbacks
        self.shouldFailover = shouldFailover
        self.onFailover = onFailover
    }

    /// Generates text, failing over across the chain on retryable errors.
    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await attempt {
            try await $0.generate(messages: messages, options: options)
        }
    }

    /// Generates with tool calls, failing over across the chain on retryable errors.
    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await attempt {
            try await $0.generateWithToolCalls(messages: messages, tools: tools, options: options)
        }
    }

    /// Generates with tool calls and an executor, failing over across the chain on retryable errors.
    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        try await attempt {
            try await $0.generateWithToolCalls(
                messages: messages,
                tools: tools,
                options: options,
                toolExecutor: toolExecutor
            )
        }
    }

    /// Generates structured output natively per provider, failing over across the chain.
    ///
    /// Each provider's native implementation runs (no prompt fallback),
    /// so native JSON-schema support survives failover.
    public func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await attempt {
            try await $0.generateStructured(messages: messages, request: request, options: options)
        }
    }

    /// Runs one operation against each provider in order until one succeeds.
    private func attempt<T: Sendable>(
        _ operation: @Sendable (any InferenceProvider) async throws -> T
    ) async throws -> T {
        let chain = [primary] + fallbacks
        var lastError: Error?
        for (index, provider) in chain.enumerated() {
            do {
                return try await operation(provider)
            } catch {
                lastError = error
                if error is CancellationError || Task.isCancelled {
                    throw error
                }
                let isLast = index == chain.count - 1
                guard !isLast, shouldFailover(error) else {
                    throw error
                }
                await onFailover?(index, error)
            }
        }
        throw lastError ?? AgentError.internalError(reason: "FailoverProvider has no providers")
    }
}
