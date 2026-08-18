// TextOnlyConversationInferenceProviderAdapter.swift
// Swarm Framework
//
// Generic text-only inference fallbacks for structured conversation transport and
// prompt-based tool calling emulation.

import Foundation

/// Adapts a plain prompt-oriented provider to Swarm's structured conversation protocols.
///
/// This preserves `Swarm` as the owner of tool orchestration while allowing custom
/// providers that only implement prompt/text generation to participate in the
/// structured conversation path.
///
/// ## History flattening
///
/// Role-capable providers receive ``InferenceMessage`` arrays intact. This adapter
/// is the **only** supported flatten site for genuinely text-only backends: it
/// serializes the full structured history into a single prompt with explicit role
/// labels (`[System]`, `[User]`, `[Assistant]`, `[Assistant Tool Calls]`,
/// `[Tool Result - name]`). The conversion is lossless-by-construction — every
/// message contributes one labeled block, including assistant tool-call metadata
/// and tool-result bodies. Nothing is dropped.
public struct TextOnlyConversationInferenceProviderAdapter: InferenceProvider {
    public let base: any InferenceProvider

    public init(base: any InferenceProvider) {
        self.base = base
    }

    public var capabilities: InferenceProviderCapabilities {
        var capabilities = InferenceProviderCapabilities.resolved(for: base)
        capabilities.remove(.streamingToolCalls)
        capabilities.insert(.conversationMessages)
        return capabilities
    }

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await base.generate(prompt: prompt, options: options)
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await base.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        base.stream(prompt: prompt, options: options)
    }

    /// Serializes structured history into a labeled prompt for text-only backends.
    ///
    /// Every message is preserved as a role-tagged block. This is the supported
    /// flatten entry point; role-capable providers must not go through it.
    public static func prompt(from messages: [InferenceMessage]) -> String {
        InferenceMessage.flattenPrompt(messages)
    }

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await base.generate(prompt: Self.prompt(from: messages), options: options)
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(
            prompt: Self.prompt(from: messages),
            tools: tools,
            options: options
        )
    }

    public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        base.stream(prompt: Self.prompt(from: messages), options: options)
    }
}

public extension InferenceProvider {
    /// Default tool-calling behavior for prompt/text-only providers.
    ///
    /// Providers with native tool calling should override this requirement.
    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await LanguageModelSessionToolCallingEmulation.generateResponse(
            prompt: prompt,
            tools: tools,
            options: options
        ) { toolPrompt, options in
            try await generate(prompt: toolPrompt, options: options)
        }
    }
}

extension TextOnlyConversationInferenceProviderAdapter: PromptTokenCountingInferenceProvider {
    public func countTokens(in text: String) async throws -> Int {
        if let countingBase = base as? any PromptTokenCountingInferenceProvider {
            return try await countingBase.countTokens(in: text)
        }
        return CharacterBasedTokenEstimator.shared.estimateTokens(for: text)
    }
}
