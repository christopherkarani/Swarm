// InferenceProviderSummarizer.swift
// Swarm Framework
//
// LLM-based summarizer using any InferenceProvider.

import Foundation

// MARK: - InferenceProviderSummarizer

/// LLM-based summarizer using any ``InferenceProvider``.
///
/// This is the real summarizer: it sends conversation text to an inference
/// provider and returns the model's summary. Contrast with
/// ``TruncatingSummarizer``, which only **truncates** (drops) content to fit a
/// token budget and never calls a model.
///
/// Token budgets passed to ``summarize(_:maxTokens:)`` are forwarded as
/// ``InferenceOptions/maxTokens``. The provider's tokenizer may differ from
/// Swarm's default ``CharacterBasedTokenEstimator`` (~4 characters per token).
///
/// ## Usage
///
/// ```swift
/// let summarizer = InferenceProviderSummarizer.conversationSummarizer(
///     provider: myInferenceProvider
/// )
/// let memory: SummaryMemory = .summary(summarizer: summarizer)
/// ```
///
/// Factory convenience via ``MemorySummarizer``:
///
/// ```swift
/// let memory: SummaryMemory = .summary(
///     summarizer: .inferenceProvider(myInferenceProvider)
/// )
///
/// // On-device Apple Foundation Models when available; otherwise truncates:
/// let memory: SummaryMemory = .summary(summarizer: .foundationModels)
/// ```
///
/// ## Customization
///
/// The summarization prompt can be customized:
///
/// ```swift
/// let summarizer = InferenceProviderSummarizer(
///     provider: myInferenceProvider,
///     systemPrompt: "Create a brief summary focusing on action items:"
/// )
/// ```
public actor InferenceProviderSummarizer: Summarizer {
    // MARK: Public

    public var isAvailable: Bool {
        get async { true }
    }

    /// Creates a new inference provider-based summarizer.
    ///
    /// - Parameters:
    ///   - provider: The inference provider to use for summarization.
    ///   - systemPrompt: The prompt prefix for summarization requests.
    ///   - temperature: Temperature for generation (default: 0.3 for consistency).
    public init(
        provider: any InferenceProvider,
        systemPrompt: String = "Summarize the following conversation concisely, preserving key information and context:",
        temperature: Double = 0.3
    ) {
        self.provider = provider
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }

    // MARK: - Summarizer Protocol

    public func summarize(_ text: String, maxTokens: Int) async throws -> String {
        // Truncate input to prevent excessive token usage
        let maxInputLength = 50000 // Reasonable limit for most LLMs
        let truncatedText = text.count > maxInputLength
            ? String(text.prefix(maxInputLength)) + "\n[...truncated]"
            : text

        // Escape XML special characters in user content to prevent tag injection.
        // Without escaping, user text containing "</text_to_summarize>" could corrupt
        // the summarizer prompt (prompt injection).
        let escapedText = truncatedText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let prompt = """
        \(systemPrompt)

        <text_to_summarize>
        \(escapedText)
        </text_to_summarize>

        Summary:
        """

        let options = InferenceOptions.default
            .temperature(temperature)
            .maxTokens(maxTokens)

        let response = try await provider.generate(prompt: prompt, options: options)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw PersistentMemoryError.fetchFailed("Summarizer returned empty response")
        }

        return trimmed
    }

    // MARK: Private

    private let provider: any InferenceProvider
    private let systemPrompt: String
    private let temperature: Double
}

// MARK: - Convenience Extensions

public extension InferenceProviderSummarizer {
    /// Creates a summarizer optimized for conversation summaries.
    ///
    /// - Parameter provider: The inference provider to use.
    /// - Returns: A summarizer configured for conversation summarization.
    static func conversationSummarizer(
        provider: any InferenceProvider
    ) -> InferenceProviderSummarizer {
        InferenceProviderSummarizer(
            provider: provider,
            systemPrompt: """
            Summarize this conversation, capturing:
            - Main topics discussed
            - Key decisions or conclusions
            - Any action items or next steps
            - Important context for future reference

            Be concise but preserve essential information:
            """,
            temperature: 0.2
        )
    }

    /// Creates a summarizer optimized for agent reasoning traces.
    ///
    /// - Parameter provider: The inference provider to use.
    /// - Returns: A summarizer configured for reasoning trace summarization.
    static func reasoningSummarizer(
        provider: any InferenceProvider
    ) -> InferenceProviderSummarizer {
        InferenceProviderSummarizer(
            provider: provider,
            systemPrompt: """
            Summarize this agent reasoning trace, capturing:
            - The original goal or question
            - Key observations and findings
            - Tools used and their results
            - Current state and next steps needed

            Format as a brief status report:
            """,
            temperature: 0.1
        )
    }
}

public extension Summarizer where Self == InferenceProviderSummarizer {
    /// Leading-dot factory for ``conversationSummarizer(provider:)``.
    ///
    /// Prefer ``MemorySummarizer/inferenceProvider(_:)`` at the
    /// ``Memory/summary(configuration:summarizer:)`` call site:
    /// `.summary(summarizer: .inferenceProvider(provider))`.
    static func conversationSummarizer(
        provider: any InferenceProvider
    ) -> InferenceProviderSummarizer {
        InferenceProviderSummarizer.conversationSummarizer(provider: provider)
    }
}
