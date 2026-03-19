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
public struct TextOnlyConversationInferenceProviderAdapter:
    InferenceProvider,
    CapabilityReportingInferenceProvider,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider
{
    public let base: any InferenceProvider

    public init(base: any InferenceProvider) {
        self.base = base
    }

    public var capabilities: InferenceProviderCapabilities {
        var capabilities = InferenceProviderCapabilities.resolved(for: base)
        capabilities.insert(.conversationMessages)
        return capabilities
    }

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await base.generate(prompt: prompt, options: options)
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        base.stream(prompt: prompt, options: options)
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

public extension ConversationInferenceProvider {
    /// Default structured message generation by flattening to the legacy prompt path.
    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }

    /// Default structured tool-calling behavior by flattening structured history and
    /// reusing the provider's prompt-oriented tool-calling implementation.
    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(
            prompt: InferenceMessage.flattenPrompt(messages),
            tools: tools,
            options: options
        )
    }
}

public extension StreamingConversationInferenceProvider {
    /// Default structured streaming by flattening to the prompt-oriented streaming path.
    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        stream(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }
}
