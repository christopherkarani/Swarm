// TextOnlyConversationInferenceProviderAdapter.swift
// Swarm Framework
//
// Text-only backend seam and the InferenceProvider adapter that flattens roles.

import Foundation

/// A prompt-shaped inner type: generate, stream, and tool-calling on a `String`.
///
/// It cannot take ``InferenceMessage`` roles. Wrap with
/// ``TextOnlyConversationInferenceProviderAdapter/textOnly(_:)`` before passing
/// to ``Agent``.
public protocol TextOnlyBackend: Sendable {
    /// Advertised features of the string backend. The text-only adapter strips
    /// ``InferenceProviderCapabilities/streamingToolCalls`` and
    /// ``InferenceProviderCapabilities/providerOwnedToolLoop``.
    var capabilities: InferenceProviderCapabilities { get }

    /// Native prompt token counter for this backend, if any.
    var promptTokenCounter: (any PromptTokenCounter)? { get }

    func generate(prompt: String, options: InferenceOptions) async throws -> String

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error>

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse
}

public extension TextOnlyBackend {
    var capabilities: InferenceProviderCapabilities { [] }

    var promptTokenCounter: (any PromptTokenCounter)? { nil }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let response = try await generate(prompt: prompt, options: options)
            if !response.isEmpty {
                continuation.yield(response)
            }
            continuation.finish()
        }
    }

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

/// Adapts a ``TextOnlyBackend`` to ``InferenceProvider`` by flattening
/// ``InferenceMessage`` history into a labeled prompt.
///
/// Role-capable providers receive ``InferenceMessage`` arrays intact. This adapter
/// is the **only** supported flatten site for genuinely text-only backends: it
/// serializes the full structured history into a single prompt with explicit role
/// labels (`[System]`, `[User]`, `[Assistant]`, `[Assistant Tool Calls]`,
/// `[Tool Result - name]`). The conversion is lossless-by-construction — every
/// message contributes one labeled block, including assistant tool-call metadata
/// and tool-result bodies. Nothing is dropped.
public struct TextOnlyConversationInferenceProviderAdapter: InferenceProvider {
    public let backend: any TextOnlyBackend

    /// Wraps a text-only backend as an ``InferenceProvider``.
    public static func textOnly(_ backend: some TextOnlyBackend) -> TextOnlyConversationInferenceProviderAdapter {
        TextOnlyConversationInferenceProviderAdapter(backend: backend)
    }

    public init(backend: any TextOnlyBackend) {
        self.backend = backend
    }

    public var capabilities: InferenceProviderCapabilities {
        var capabilities = backend.capabilities
        capabilities.remove(.streamingToolCalls)
        capabilities.remove(.providerOwnedToolLoop)
        capabilities.insert(.conversationMessages)
        return capabilities
    }

    public var promptTokenCounter: (any PromptTokenCounter)? {
        backend.promptTokenCounter
    }

    /// Serializes structured history into a labeled prompt for text-only backends.
    ///
    /// Every message is preserved as a role-tagged block. This is the supported
    /// flatten entry point; role-capable providers must not go through it.
    public static func prompt(from messages: [InferenceMessage]) -> String {
        InferenceMessage.flattenPrompt(messages)
    }

    public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await backend.generate(prompt: Self.prompt(from: messages), options: options)
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: nil
        )
    }

    public func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return try await backend.generateWithToolCalls(
            prompt: Self.prompt(from: messages),
            tools: tools,
            options: options
        )
    }

    public func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        backend.stream(prompt: Self.prompt(from: messages), options: options)
    }

    public func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let prompt = StructuredOutputPromptBuilder.appendInstruction(
            to: Self.prompt(from: messages),
            request: request
        )
        let text = try await backend.generate(prompt: prompt, options: options)
        return try StructuredOutputParser.parse(text, request: request, source: .promptFallback)
    }
}

public extension InferenceProvider where Self == TextOnlyConversationInferenceProviderAdapter {
    /// Wraps a text-only backend as an ``InferenceProvider``.
    static func textOnly(_ backend: some TextOnlyBackend) -> TextOnlyConversationInferenceProviderAdapter {
        .textOnly(backend)
    }
}
