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
}

public extension InferenceProviderCapabilities {
    /// Features implied by the provider's protocol conformances.
    static func inferred(from provider: any InferenceProvider) -> Self {
        var capabilities: Self = []
        if provider is any ConversationInferenceProvider {
            capabilities.insert(.conversationMessages)
        }
        if provider is any ToolCallStreamingConversationInferenceProvider
            || provider is any ToolCallStreamingInferenceProvider
        {
            capabilities.insert(.streamingToolCalls)
        }
        if provider is any StructuredOutputConversationInferenceProvider
            || provider is any StructuredOutputInferenceProvider
        {
            capabilities.insert(.structuredOutputs)
        }
        return capabilities
    }

    /// Effective provider capabilities after merging explicit reporting with protocol inference.
    static func resolved(for provider: any InferenceProvider) -> Self {
        if let reportingProvider = provider as? any CapabilityReportingInferenceProvider {
            var capabilities = reportingProvider.capabilities
            if provider is any ConversationInferenceProvider {
                capabilities.insert(.conversationMessages)
            }
            return capabilities
        }
        return inferred(from: provider)
    }
}

/// Optional protocol for providers that can report which advanced features they actually support.
public protocol CapabilityReportingInferenceProvider: InferenceProvider {
    var capabilities: InferenceProviderCapabilities { get }
}

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
public protocol ConversationInferenceProvider: InferenceProvider {
    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse
}

/// Structured conversation streaming for plain text responses.
public protocol StreamingConversationInferenceProvider: ConversationInferenceProvider {
    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error>
}

/// Structured conversation streaming for tool-call capable providers.
public protocol ToolCallStreamingConversationInferenceProvider: ConversationInferenceProvider {
    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error>
}

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

    package static func flattenPrompt(_ messages: [InferenceMessage]) -> String {
        messages.map(\.flattenedPromptLine).joined(separator: "\n\n")
    }
}
