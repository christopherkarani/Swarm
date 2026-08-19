// ConversationInferenceProvider.swift
// Swarm Framework
//
// Structured conversation-facing inference protocols and provider capabilities.

import Foundation

/// Advertised provider features used by Swarm when selecting inference transport behavior.
public struct InferenceProviderCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Provider accepts structured message history rather than only a flattened prompt string.
    public static let conversationMessages = Self(rawValue: 1 << 0)

    /// Provider supports native/provider-managed tool calling for structured requests.
    public static let nativeToolCalling = Self(rawValue: 1 << 1)

    /// Provider can stream partial/completed tool calls during generation.
    public static let streamingToolCalls = Self(rawValue: 1 << 2)

    /// Provider supports continuing a prior response using a provider-issued response identifier.
    public static let responseContinuation = Self(rawValue: 1 << 3)

    /// Provider can satisfy structured output requests.
    public static let structuredOutputs = Self(rawValue: 1 << 4)

    /// Provider performs inference locally without sending prompt content to a remote model service.
    public static let privateInference = Self(rawValue: 1 << 5)

    /// Adapter owns the tool loop: it executes Swarm tools inside
    /// `generateWithToolCalls` / `streamWithToolCalls` using the call's
    /// ``ToolCallExecutor``. Agent skips inference retries on that path so a
    /// side-effecting tool is not replayed. OpenAI-compatible backends that
    /// only *return* tool calls must not advertise this bit. Conformers that
    /// set this bit must implement the `toolExecutor` overloads; the protocol
    /// default throws ``AgentError/providerOwnedToolLoopRequiresExecutor``.
    public static let providerOwnedToolLoop = Self(rawValue: 1 << 6)
}

public extension InferenceProviderCapabilities {
    /// Effective provider capabilities. Conversation messages are always on;
    /// other bits come from the adapter's advertised set.
    static func resolved(for provider: any InferenceProvider) -> Self {
        var capabilities = provider.capabilities
        capabilities.insert(.conversationMessages)
        return capabilities
    }

    /// Use ``resolved(for:)``.
    @available(*, deprecated, message: "Use resolved(for:)")
    static func inferred(from provider: any InferenceProvider) -> Self {
        resolved(for: provider)
    }
}

/// Optional protocol for providers that can report which advanced features they actually support.
@available(*, deprecated, message: "Declare capabilities on InferenceProvider")
public protocol CapabilityReportingInferenceProvider: InferenceProvider {}

/// A provider-facing conversation message used by structured inference integrations.
public struct InferenceMessage: Sendable, Equatable {
    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
        case tool
    }

    /// Tool-call metadata attached to assistant messages so providers can continue native tool loops.
    public struct ToolCall: Sendable, Equatable {
        public let id: String?
        public let name: String
        public let arguments: [String: SendableValue]

        public init(id: String? = nil, name: String, arguments: [String: SendableValue]) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
    }

    public let role: Role
    public let content: String
    public let name: String?
    public let toolCallID: String?
    public let toolCalls: [ToolCall]

    public init(
        role: Role,
        content: String,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [ToolCall] = []
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    public static func system(_ content: String) -> InferenceMessage {
        InferenceMessage(role: .system, content: content)
    }

    public static func user(_ content: String) -> InferenceMessage {
        InferenceMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String, toolCalls: [ToolCall] = []) -> InferenceMessage {
        InferenceMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    public static func tool(
        name: String,
        content: String,
        toolCallID: String? = nil
    ) -> InferenceMessage {
        InferenceMessage(role: .tool, content: content, name: name, toolCallID: toolCallID)
    }
}

/// Optional protocol for providers that can consume structured conversation history directly.
@available(*, deprecated, renamed: "InferenceProvider")
public protocol ConversationInferenceProvider: InferenceProvider {}

/// Structured conversation streaming for plain text responses.
@available(*, deprecated, renamed: "InferenceProvider")
public protocol StreamingConversationInferenceProvider: ConversationInferenceProvider {}

/// Structured conversation streaming for tool-call capable providers.
@available(*, deprecated, renamed: "InferenceProvider")
public protocol ToolCallStreamingConversationInferenceProvider: ConversationInferenceProvider {}

extension InferenceMessage.ToolCall {
    init(_ parsed: InferenceResponse.ParsedToolCall) {
        self.init(id: parsed.id, name: parsed.name, arguments: parsed.arguments)
    }
}

extension InferenceMessage {
    package var flattenedPromptLine: String {
        switch role {
        case .system:
            return "[System]: \(content)"
        case .user:
            return "[User]: \(content)"
        case .assistant:
            if toolCalls.isEmpty {
                return "[Assistant]: \(content)"
            }

            let summary = toolCalls
                .map { "Calling tool: \($0.name)" }
                .joined(separator: ", ")

            if content.isEmpty {
                return "[Assistant]: \(summary)"
            }

            return "[Assistant]: \(content)\n[Assistant Tool Calls]: \(summary)"
        case .tool:
            let label = name ?? "tool"
            return "[Tool Result - \(label)]: \(content)"
        }
    }

    /// Labeled serialization used by ``TextOnlyConversationInferenceProviderAdapter``.
    ///
    /// Role-capable providers must consume ``InferenceMessage`` arrays directly.
    /// Flattening with role labels is reserved for text-only backends.
    package static func flattenPrompt(_ messages: [InferenceMessage]) -> String {
        messages.map(\.flattenedPromptLine).joined(separator: "\n\n")
    }
}

public extension InferenceProvider {
    var capabilities: InferenceProviderCapabilities { [.conversationMessages] }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }

    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        stream(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }

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

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        if capabilities.contains(.providerOwnedToolLoop) {
            throw AgentError.providerOwnedToolLoopRequiresExecutor
        }
        _ = toolExecutor
        return try await generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        if let promptStreamer = self as? any ToolCallStreamingInferenceProvider {
            return promptStreamer.streamWithToolCalls(
                prompt: InferenceMessage.flattenPrompt(messages),
                tools: tools,
                options: options
            )
        }
        return streamFinishedToolTurn {
            try await generateWithToolCalls(messages: messages, tools: tools, options: options)
        }
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        if capabilities.contains(.providerOwnedToolLoop) {
            return streamFinishedToolTurn {
                try await generateWithToolCalls(
                    messages: messages,
                    tools: tools,
                    options: options,
                    toolExecutor: toolExecutor
                )
            }
        }
        _ = toolExecutor
        return streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let prompt = InferenceMessage.flattenPrompt(messages)
        // Prompt structured output is a StructuredOutputInferenceProvider requirement, not InferenceProvider.
        if let structuredProvider = self as? any StructuredOutputInferenceProvider {
            return try await structuredProvider.generateStructured(
                prompt: prompt,
                request: request,
                options: options
            )
        }
        return try await generateStructured(prompt: prompt, request: request, options: options)
    }
}

private func streamFinishedToolTurn(
    _ generate: @escaping @Sendable () async throws -> InferenceResponse
) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
    StreamHelper.makeTrackedStream { continuation in
        let response = try await generate()
        if let content = response.content, !content.isEmpty {
            continuation.yield(.outputChunk(content))
        }
        if !response.toolCalls.isEmpty {
            continuation.yield(.toolCallsCompleted(response.toolCalls))
        }
        if let usage = response.usage {
            continuation.yield(.usage(usage))
        }
        if !response.transcriptMessages.isEmpty {
            continuation.yield(.finishedTurn(response))
        }
        continuation.finish()
    }
}
