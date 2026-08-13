// Summarizer.swift
// Swarm Framework
//
// LLM summarization abstraction for memory compression.

import Foundation

// MARK: - Summarizer

/// Protocol for text summarization services.
///
/// Abstracts the summarization capability to support multiple backends
/// including Foundation Models, remote APIs, or mock implementations for testing.
public protocol Summarizer: Sendable {
    /// Whether this summarizer is currently available.
    var isAvailable: Bool { get async }

    /// Summarizes the given text.
    ///
    /// - Parameters:
    ///   - text: The text to summarize.
    ///   - maxTokens: Target maximum tokens for the summary. When the
    ///     implementation uses ``CharacterBasedTokenEstimator``, this is a
    ///     heuristic of ~4 characters per token, not a model tokenizer count.
    /// - Returns: A summarized version of the text.
    /// - Throws: `SummarizerError` if summarization fails.
    func summarize(_ text: String, maxTokens: Int) async throws -> String
}

// MARK: - SummarizerError

/// Error types for summarization operations.
public enum SummarizerError: Error, Sendable, CustomStringConvertible {
    // MARK: Public

    public var description: String {
        switch self {
        case .unavailable:
            "Summarizer is not available"
        case let .summarizationFailed(error):
            "Summarization failed: \(error.localizedDescription)"
        case .inputTooShort:
            "Input text is too short to summarize"
        case .timeout:
            "Summarization operation timed out"
        }
    }

    /// The summarizer is not available (e.g., no LLM access).
    case unavailable
    /// Summarization failed with an underlying error.
    case summarizationFailed(underlying: Error)
    /// The input text is too short to meaningfully summarize.
    case inputTooShort
    /// The operation timed out.
    case timeout
}

// MARK: - TruncatingSummarizer

/// A fallback that **truncates** (drops) text instead of summarizing it.
///
/// This type does **not** produce a summary. It cuts the input to fit
/// `maxTokens` using ``CharacterBasedTokenEstimator`` (~4 characters per
/// token), preferring a sentence, newline, or word boundary. Older content
/// past that budget is discarded.
///
/// Used as the factory default for ``Memory/summary(configuration:summarizer:)``
/// and ``Memory/hybrid(configuration:summarizer:)`` because those factories
/// are synchronous and cannot await ``Swarm/defaultProvider`` the way
/// ``Agent`` does. For real summarization, pass
/// ``InferenceProviderSummarizer`` or ``MemorySummarizer/foundationModels``.
///
/// ## Usage
///
/// ```swift
/// let summarizer = TruncatingSummarizer.shared
/// let truncated = try await summarizer.summarize(longText, maxTokens: 500)
/// ```
public struct TruncatingSummarizer: Summarizer, Sendable {
    // MARK: Public

    /// Shared instance for convenience.
    public static let shared = TruncatingSummarizer()

    public var isAvailable: Bool {
        get async { true }
    }

    /// Creates a truncating summarizer.
    ///
    /// - Parameter tokenEstimator: Token estimator for measuring text length.
    public init(tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared) {
        self.tokenEstimator = tokenEstimator
    }

    public func summarize(_ text: String, maxTokens: Int) async throws -> String {
        let currentTokens = tokenEstimator.estimateTokens(for: text)

        // If already within limit, return as-is
        guard currentTokens > maxTokens else { return text }

        // Estimate target character count (chars/4 ≈ tokens)
        let targetChars = maxTokens * 4
        let truncated = String(text.prefix(targetChars))

        // Try to find a clean break point
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        } else if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[..<lastNewline])
        } else if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }

        return truncated + "..."
    }

    // MARK: Private

    private let tokenEstimator: any TokenEstimator
}

// MARK: - Foundation Models Summarizer

#if canImport(FoundationModels)
    import FoundationModels

    /// Foundation Models-based summarizer.
    ///
    /// Uses Apple's on-device language models for summarization.
    /// Only available on physical devices with iOS/macOS 26+.
    ///
    /// ## Availability
    ///
    /// This summarizer checks for model availability before each operation.
    /// If models are unavailable (e.g., on simulator), use `TruncatingSummarizer` as fallback.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let summarizer = FoundationModelsSummarizer()
    /// if await summarizer.isAvailable {
    ///     let summary = try await summarizer.summarize(longText, maxTokens: 500)
    /// }
    /// ```
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    actor FoundationModelsSummarizer: Summarizer {
        // MARK: Internal

        var isAvailable: Bool {
            get async {
                let model = SystemLanguageModel.default
                let availability = model.availability
                return availability == .available
            }
        }

        /// Creates a Foundation Models summarizer.
        init() {}

        func summarize(_ text: String, maxTokens _: Int) async throws -> String {
            guard await isAvailable else {
                throw SummarizerError.unavailable
            }

            // Initialize session if needed
            if session == nil {
                session = LanguageModelSession()
            }

            guard let session else {
                throw SummarizerError.unavailable
            }

            let prompt = """
            Summarize the following conversation concisely, preserving key information and context. \
            Keep the summary brief and focused on the most important points.

            Conversation:
            \(text)

            Summary:
            """

            do {
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                throw SummarizerError.summarizationFailed(underlying: error)
            }
        }

        /// Resets the language model session.
        func resetSession() {
            session = nil
        }

        // MARK: Private

        private var session: LanguageModelSession?
    }
#endif

// MARK: - FallbackSummarizer

/// A summarizer that tries multiple summarizers in order.
///
/// Attempts the primary summarizer first, falling back to alternatives
/// if the primary fails or is unavailable.
struct FallbackSummarizer: Summarizer, Sendable {
    // MARK: Internal

    var isAvailable: Bool {
        get async {
            let primaryAvailable = await primary.isAvailable
            let fallbackAvailable = await fallback.isAvailable
            return primaryAvailable || fallbackAvailable
        }
    }

    /// Creates a fallback summarizer.
    ///
    /// - Parameters:
    ///   - primary: The preferred summarizer to try first.
    ///   - fallback: The backup summarizer if primary fails.
    init(primary: any Summarizer, fallback: any Summarizer = TruncatingSummarizer.shared) {
        self.primary = primary
        self.fallback = fallback
    }

    func summarize(_ text: String, maxTokens: Int) async throws -> String {
        // Try primary first
        if await primary.isAvailable {
            do {
                return try await primary.summarize(text, maxTokens: maxTokens)
            } catch {
                // Fall through to fallback
            }
        }

        // Use fallback
        if await fallback.isAvailable {
            return try await fallback.summarize(text, maxTokens: maxTokens)
        }

        throw SummarizerError.unavailable
    }

    // MARK: Private

    private let primary: any Summarizer
    private let fallback: any Summarizer
}

// MARK: - MemorySummarizer

/// Built-in summarizer presets for ``Memory/summary(configuration:summarizer:)``
/// and ``Memory/hybrid(configuration:summarizer:)``.
///
/// ```swift
/// // Default factory still truncates (does not summarize).
/// let truncated: SummaryMemory = .summary()
///
/// // Real LLM summarization.
/// let llm: SummaryMemory = .summary(summarizer: .inferenceProvider(myProvider))
///
/// // On-device Foundation Models when available; otherwise truncates.
/// let onDevice: SummaryMemory = .summary(summarizer: .foundationModels)
/// ```
///
/// These presets exist because the memory factories are synchronous:
/// they cannot await ``Swarm/defaultProvider`` or Foundation Models
/// availability the way ``Agent`` does at run time.
public struct MemorySummarizer: Sendable {
    /// Truncates (drops) old content. Does **not** summarize.
    public static var truncating: MemorySummarizer {
        MemorySummarizer(summarizer: TruncatingSummarizer.shared)
    }

    /// On-device Foundation Models via
    /// ``InferenceProviderSummarizer/conversationSummarizer(provider:)``.
    ///
    /// Resolves the provider with the same *synchronous* check Agent uses
    /// for its last fallback (`DefaultInferenceProviderFactory`). If
    /// Foundation Models are unavailable, this is ``truncating``.
    /// Environment / ``Swarm/defaultProvider`` are not consulted — those
    /// require async access that the factory call site does not have.
    public static var foundationModels: MemorySummarizer {
        if let provider = DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable() {
            return MemorySummarizer(
                summarizer: InferenceProviderSummarizer.conversationSummarizer(provider: provider)
            )
        }
        return .truncating
    }

    /// LLM summarization using ``InferenceProviderSummarizer/conversationSummarizer(provider:)``.
    ///
    /// - Parameter provider: Inference backend used for summarization.
    /// - Returns: A preset wrapping a conversation summarizer.
    public static func inferenceProvider(_ provider: any InferenceProvider) -> MemorySummarizer {
        MemorySummarizer(
            summarizer: InferenceProviderSummarizer.conversationSummarizer(provider: provider)
        )
    }

    let summarizer: any Summarizer

    private init(summarizer: any Summarizer) {
        self.summarizer = summarizer
    }
}
