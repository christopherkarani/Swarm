// SemanticCompactorTool.swift
// Swarm Framework
//
// A tool for compacting and summarizing text using on-device Foundation Models.

import Foundation

/// A tool that uses Apple's on-device Foundation Models to summarize or compact text.
///
/// This tool is ideal for:
/// - Summarizing long web search results.
/// - Compacting conversation history to save tokens for cloud LLMs.
/// - Extracting key bullet points from long documents.
///
/// On supported Apple devices (iOS 18+ / macOS 15+), it runs entirely on-device,
/// ensuring privacy and low latency.
///
/// Implemented as ``AnyJSONTool`` so it compiles without the Macros trait.
/// Prefer ``FunctionTool`` or `@Tool` in application code.
public struct SemanticCompactorTool: AnyJSONTool, Sendable {
    public let name = "semantic_compactor"
    public let description = "Compacts or summarizes a piece of text to its essential information."
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "text",
            description: "The long text or content to compact",
            type: .string
        ),
        ToolParameter(
            name: "strategy",
            description: """
            The compaction strategy: 'summary' (concise paragraph), \
            'key_points' (bullet list), or 'semantic_core' (most minimal version).
            """,
            type: .string,
            isRequired: false,
            defaultValue: .string("summary")
        ),
        ToolParameter(
            name: "maxLength",
            description: "The maximum length of the output in characters (approximate).",
            type: .int,
            isRequired: false,
            defaultValue: .int(500)
        ),
    ]

    /// The long text or content to compact.
    public var text: String = ""

    /// The compaction strategy: `summary`, `key_points`, or `semantic_core`.
    public var strategy: String = "summary"

    /// The maximum length of the output in characters (approximate).
    public var maxLength: Int = 500

    private let summarizer: any Summarizer

    /// Creates a new semantic compactor tool.
    ///
    /// - Parameter summarizer: The summarization engine to use.
    ///   Defaults to a fallback chain that tries Foundation Models first, then truncates.
    public init(summarizer: (any Summarizer)? = nil) {
        self.text = ""
        self.strategy = "summary"
        self.maxLength = 500

        if let summarizer {
            self.summarizer = summarizer
        } else {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                self.summarizer = FallbackSummarizer(
                    primary: FoundationModelsSummarizer(),
                    fallback: TruncatingSummarizer.shared
                )
            } else {
                self.summarizer = TruncatingSummarizer.shared
            }
            #else
            self.summarizer = TruncatingSummarizer.shared
            #endif
        }
    }

    public func execute() async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No text provided to compact."
        }

        let prompt: String
        switch strategy.lowercased() {
        case "key_points", "bullets":
            prompt = """
            Extract the key points from the following text as a bulleted list. Be concise and factual.

            Text:
            \(text)

            Key Points:
            """
        case "semantic_core", "compact":
            prompt = """
            Condense the following text to its absolute semantic core. \
            Remove all filler words while preserving all names, dates, figures, and critical facts. \
            Use as few words as possible.

            Text:
            \(text)

            Core Info:
            """
        default:
            prompt = text
        }

        let maxTokens = maxLength / 4

        do {
            return try await summarizer.summarize(prompt, maxTokens: maxTokens)
        } catch {
            return try await TruncatingSummarizer.shared.summarize(text, maxTokens: maxTokens)
        }
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let text = arguments["text"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'text'"
            )
        }
        var copy = self
        copy.text = text
        copy.strategy = arguments["strategy"]?.stringValue ?? "summary"
        copy.maxLength = arguments["maxLength"]?.intValue ?? 500
        return .string(try await copy.execute())
    }
}
