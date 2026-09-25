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
    /// set this bit must implement the `toolExecutor` method; the protocol
    /// default throws ``AgentError/providerOwnedToolLoopRequiresExecutor``.
    public static let providerOwnedToolLoop = Self(rawValue: 1 << 6)

    /// Provider accepts audio ``InferenceMessage/Attachment`` values.
    ///
    /// Providers without this bit must omit or reject audio attachments.
    public static let multimodalAudio = Self(rawValue: 1 << 7)

    /// Reserved for image attachments (Foundation Models vision). Unused in
    /// the default VoiceSession text path.
    public static let multimodalImage = Self(rawValue: 1 << 8)
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
    ///
    /// This deprecated forwarding helper remains available for source
    /// compatibility until a future breaking boundary is explicitly
    /// documented.
    @available(*, deprecated, message: "Use resolved(for:)")
    static func inferred(from provider: any InferenceProvider) -> Self {
        resolved(for: provider)
    }
}

/// Optional protocol for providers that can report which advanced features they actually support.
@available(*, deprecated, message: "Declare capabilities on InferenceProvider")
public protocol CapabilityReportingInferenceProvider: InferenceProvider {}

/// A provider-facing conversation message used by structured inference integrations.
///
/// The payload is a closed ``Body``: system text, user text, assistant text with
/// optional tool calls, or a named tool result. Historical ``role``, ``content``,
/// ``name``, ``toolCallID``, and ``toolCalls`` remain as computed projections of
/// ``body``.
public struct InferenceMessage: Sendable, Equatable {
    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
        case tool
    }

    /// Closed payload of one provider conversation item.
    ///
    /// Each case carries only the fields that role allows. A user or system
    /// message cannot store tool calls; a tool result always has a name.
    public enum Body: Sendable, Equatable {
        /// System instruction text.
        case system(String)
        /// User turn text.
        case user(String)
        /// Assistant text with optional native tool calls.
        case assistant(String, toolCalls: [ToolCall] = [])
        /// Named tool result with optional provider call id.
        case tool(name: String, content: String, toolCallID: String?)
    }

    /// Tool-call metadata attached to assistant messages so providers can continue native tool loops.
    public struct ToolCall: Sendable, Equatable {
        public let id: String?
        public let name: String
        public let arguments: [String: SendableValue]
        /// Provider thought signature (Gemini thinking models). Echoed back verbatim.
        public let thoughtSignature: String?

        public init(
            id: String? = nil,
            name: String,
            arguments: [String: SendableValue],
            thoughtSignature: String? = nil
        ) {
            self.id = id
            self.name = name
            self.arguments = arguments
            self.thoughtSignature = thoughtSignature
        }
    }

    /// Optional multimodal sidecar. ``content`` stays text.
    ///
    /// Persist ``id`` and ``mimeType`` only — never PCM. Providers without
    /// ``InferenceProviderCapabilities/multimodalAudio`` must omit audio.
    public struct Attachment: Sendable, Equatable {
        /// Attachment family.
        public enum Kind: String, Sendable, Equatable {
            case audio
            case image
        }

        /// Host-stable identifier. Safe to store.
        public let id: String
        /// Audio or image.
        public let kind: Kind
        /// MIME type such as `audio/wav`. Safe to store.
        public let mimeType: String
        /// In-memory bytes. Do not log.
        public let data: Data?
        /// Optional file URL. Do not log contents.
        public let fileURL: URL?

        /// Creates an attachment.
        public init(
            id: String,
            kind: Kind,
            mimeType: String,
            data: Data? = nil,
            fileURL: URL? = nil
        ) {
            self.id = id
            self.kind = kind
            self.mimeType = mimeType
            self.data = data
            self.fileURL = fileURL
        }
    }

    /// System, user, assistant, or tool payload.
    public let body: Body

    /// Optional audio or image sidecars. Default empty. Token counting uses
    /// ``content`` only.
    public let attachments: [Attachment]

    /// Role projected from ``body``.
    public var role: Role {
        switch body {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        case .tool:
            .tool
        }
    }

    /// Text content projected from ``body``.
    public var content: String {
        switch body {
        case let .system(text), let .user(text):
            text
        case let .assistant(text, _):
            text
        case let .tool(_, content, _):
            content
        }
    }

    /// Tool name when ``body`` is ``Body/tool(name:content:toolCallID:)``; otherwise `nil`.
    public var name: String? {
        switch body {
        case let .tool(name, _, _):
            name
        case .system, .user, .assistant:
            nil
        }
    }

    /// Provider call id when ``body`` is ``Body/tool(name:content:toolCallID:)``; otherwise `nil`.
    public var toolCallID: String? {
        switch body {
        case let .tool(_, _, id):
            id
        case .system, .user, .assistant:
            nil
        }
    }

    /// Tool calls when ``body`` is ``Body/assistant(_:toolCalls:)``; otherwise `[]`.
    public var toolCalls: [ToolCall] {
        switch body {
        case let .assistant(_, toolCalls):
            toolCalls
        case .system, .user, .tool:
            []
        }
    }

    /// Creates a message from a closed body.
    ///
    /// - Parameters:
    ///   - body: System, user, assistant, or tool payload.
    ///   - attachments: Optional multimodal sidecars. Default empty.
    public init(body: Body, attachments: [Attachment] = []) {
        self.body = body
        self.attachments = attachments
    }

    /// Creates a message from independent role and payload fields.
    ///
    /// Mapping: ``Role/system`` becomes ``Body/system(_:)`` and drops `name`,
    /// `toolCallID`, and `toolCalls`. ``Role/user`` becomes ``Body/user(_:)``
    /// and drops the same extra fields. ``Role/assistant`` becomes
    /// ``Body/assistant(_:toolCalls:)`` and drops `name` and `toolCallID`.
    /// ``Role/tool`` becomes ``Body/tool(name:content:toolCallID:)`` using
    /// `name ?? "tool"` and drops `toolCalls`.
    ///
    /// - Parameters:
    ///   - role: Historical role used to choose the body case.
    ///   - content: Text stored on that case.
    ///   - name: Tool name. Used only for ``Role/tool``; absent values become `"tool"`.
    ///   - toolCallID: Provider call id. Used only for ``Role/tool``.
    ///   - toolCalls: Native tool calls. Used only for ``Role/assistant``.
    @available(*, deprecated, message: "Use init(body:) or the role factories.")
    public init(
        role: Role,
        content: String,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [ToolCall] = []
    ) {
        switch role {
        case .system:
            body = .system(content)
        case .user:
            body = .user(content)
        case .assistant:
            body = .assistant(content, toolCalls: toolCalls)
        case .tool:
            body = .tool(name: name ?? "tool", content: content, toolCallID: toolCallID)
        }
        attachments = []
    }

    public static func system(_ content: String) -> InferenceMessage {
        InferenceMessage(body: .system(content))
    }

    public static func user(
        _ content: String,
        attachments: [Attachment] = []
    ) -> InferenceMessage {
        InferenceMessage(body: .user(content), attachments: attachments)
    }

    public static func assistant(_ content: String, toolCalls: [ToolCall] = []) -> InferenceMessage {
        InferenceMessage(body: .assistant(content, toolCalls: toolCalls))
    }

    public static func tool(
        name: String,
        content: String,
        toolCallID: String? = nil
    ) -> InferenceMessage {
        InferenceMessage(body: .tool(name: name, content: content, toolCallID: toolCallID))
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

    var promptTokenCounter: (any PromptTokenCounter)? { nil }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await generate(messages: [.user(prompt)], options: options)
    }

    func stream(
        prompt: String,
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        stream(messages: [.user(prompt)], options: options)
    }

    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let text = try await generate(messages: messages, options: options)
            if !text.isEmpty {
                continuation.yield(text)
            }
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await generateWithToolCalls(
            messages: [.user(prompt)],
            tools: tools,
            options: options
        )
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await PromptToolCallingEmulation.generateResponse(
            messages: messages,
            tools: tools,
            options: options
        ) { messages, options in
            try await generate(messages: messages, options: options)
        }
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
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        streamWithToolCalls(
            messages: [.user(prompt)],
            tools: tools,
            options: options
        )
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        streamWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: nil
        )
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        streamFinishedToolTurn {
            try await generateWithToolCalls(
                messages: messages,
                tools: tools,
                options: options,
                toolExecutor: toolExecutor
            )
        }
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let instructed = StructuredOutputPromptBuilder.appendInstruction(
            to: messages,
            request: request
        )
        let text = try await generate(messages: instructed, options: options)
        return try StructuredOutputParser.parse(text, request: request, source: .promptFallback)
    }

    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await generateStructured(
            messages: [.user(prompt)],
            request: request,
            options: options
        )
    }
}

/// Degrades a finished, non-streaming turn into the canonical
/// ``InferenceStreamUpdate`` sequence.
///
/// Shared adapter toolkit for in-package backends that cannot stream natively:
/// route the finished turn through this helper so update ordering stays
/// identical across adapters — `outputChunk`, then `toolCallsCompleted`, then
/// `usage`, then `finishedTurn` (only when the turn carries a provider-owned
/// inner transcript), then finish.
///
/// Out-of-package providers need nothing: they inherit this exact sequence via
/// the `streamWithToolCalls(messages:tools:options:toolExecutor:)` protocol
/// default as long as they do not override that requirement.
package func streamFinishedToolTurn(
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
