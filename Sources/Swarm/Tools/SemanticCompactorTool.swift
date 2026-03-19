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
@Tool("Compacts or summarizes a piece of text to its essential information.")
public struct SemanticCompactorTool {
    // MARK: - Parameters
    
    @Parameter("The long text or content to compact")
    var text: String
    
    @Parameter("The compaction strategy: 'summary' (concise paragraph), 'key_points' (bullet list), or 'semantic_core' (most minimal version).", default: "summary")
    var strategy: String = "summary"
    
    @Parameter("The maximum length of the output in characters (approximate).", default: 500)
    var maxLength: Int = 500
    
    // MARK: - Properties
    
    private let summarizer: any Summarizer
    
    // MARK: - Initialization
    
    /// Creates a new semantic compactor tool.
    ///
    /// - Parameter summarizer: The summarization engine to use. 
    ///   Defaults to a fallback chain that tries Foundation Models first, then truncates.
    public init(summarizer: (any Summarizer)? = nil) {
        // Initialize @Parameter properties with defaults
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
    
    // MARK: - Execution
    
    /// Compacts or summarizes the input text using the configured summarizer.
    ///
    /// Uses on-device Foundation Models when available, falling back to truncation
    /// on unsupported platforms or when the summarizer fails.
    ///
    /// - Returns: A compacted version of the input text according to the specified strategy.
    /// - Throws: An error if summarization fails (though typically falls back to truncation).
    public func execute() async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No text provided to compact."
        }
        
        // Adjust prompt based on strategy
        let prompt: String
        switch strategy.lowercased() {
        case "key_points", "bullets":
            prompt = "Extract the key points from the following text as a bulleted list. Be concise and factual.\n\nText:\n\(text)\n\nKey Points:"
        case "semantic_core", "compact":
            prompt = "Condense the following text to its absolute semantic core. Remove all filler words while preserving all names, dates, figures, and critical facts. Use as few words as possible.\n\nText:\n\(text)\n\nCore Info:"
        default:
            // Standard summary
            prompt = text
        }
        
        // Use the summarizer
        // Since the current Summarizer protocol in the codebase handles its own internal prompts 
        // for FoundationModelsSummarizer, we pass the text. 
        // If it's a specialized strategy, we wrap the text in a prompt if the summarizer is just a 
        // generic LLM wrapper, but FoundationModelsSummarizer has its own internal conversational 
        // prompt. 
        
        // For the sake of this tool's flexibility, we'll try to use the summarizer 
        // but respect the maxTokens (approx characters / 4)
        let maxTokens = maxLength / 4
        
        do {
            // Note: In a real implementation we might pass the 'prompt' instead of 'text' 
            // if the summarizer supports arbitrary prompts, but the current protocol 
            // is designed for memory summarization.
            return try await summarizer.summarize(prompt, maxTokens: maxTokens)
        } catch {
            // Fallback to basic truncation if the summarizer fails
            return try await TruncatingSummarizer.shared.summarize(text, maxTokens: maxTokens)
        }
    }
}
