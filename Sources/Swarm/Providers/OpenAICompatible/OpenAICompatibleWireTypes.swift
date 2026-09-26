// OpenAICompatibleWireTypes.swift
// Swarm Framework
//
// Typed Codable boundary for OpenAI-compatible chat completions.

import Foundation

/// Typed wire boundary for OpenAI-compatible chat completions.
///
/// Decode types (`Chunk` and its children) replace `[String: Any]` subscript
/// parsing of SSE events and unary responses. Every field decodes leniently:
/// unknown keys are ignored, wrong-typed values degrade to the same defaults
/// the old subscript code produced, and only a non-object top level (or
/// invalid JSON) fails the single throwing decode per payload.
///
/// Encode types (`Request` and its children) replace `[String: Any]` request
/// assembly. Optional fields encode only when set, preserving the exact key
/// presence of the previous dictionary construction.
enum OpenAICompatibleWire: Sendable {
    // MARK: - Encode entry point

    /// Encodes a wire value with sorted keys, matching the previous
    /// `JSONSerialization` body serialization.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    // MARK: - Decode

    /// One chat-completion chunk or full response object, as received.
    struct Chunk: Decodable, Sendable, Equatable {
        var id: String?
        var choices: [Choice]
        var usage: Usage?
        var error: WireError?

        private enum CodingKeys: String, CodingKey {
            case id
            case choices
            case usage
            case error
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            choices = (try? container.decodeIfPresent([Choice].self, forKey: .choices)) ?? []
            usage = try? container.decodeIfPresent(Usage.self, forKey: .usage)
            error = try? container.decodeIfPresent(WireError.self, forKey: .error)
        }
    }

    /// One entry of a chunk `choices` array.
    struct Choice: Decodable, Sendable, Equatable {
        /// Absent when the server omits `index`; the caller falls back to the
        /// choice offset.
        var index: Int?
        var finishReason: String?
        var message: Message?
        var delta: Message?

        private enum CodingKeys: String, CodingKey {
            case index
            case finishReason = "finish_reason"
            case message
            case delta
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try? container.decodeIfPresent(Int.self, forKey: .index)
            finishReason = try? container.decodeIfPresent(String.self, forKey: .finishReason)
            message = try? container.decodeIfPresent(Message.self, forKey: .message)
            delta = try? container.decodeIfPresent(Message.self, forKey: .delta)
        }
    }

    /// A `message` or `delta` payload.
    struct Message: Decodable, Sendable, Equatable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCall]

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try? container.decodeIfPresent(String.self, forKey: .role)
            content = try? container.decodeIfPresent(String.self, forKey: .content)
            toolCalls = (try? container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)) ?? []
        }
    }

    /// One streamed or complete tool call.
    struct ToolCall: Decodable, Sendable, Equatable {
        /// Absent when the server omits `index`; the caller falls back to the
        /// tool-call offset.
        var index: Int?
        var id: String?
        var function: Function?
        var extraContent: ExtraContent?

        private enum CodingKeys: String, CodingKey {
            case index
            case id
            case function
            case extraContent = "extra_content"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            index = try? container.decodeIfPresent(Int.self, forKey: .index)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            function = try? container.decodeIfPresent(Function.self, forKey: .function)
            extraContent = try? container.decodeIfPresent(ExtraContent.self, forKey: .extraContent)
        }
    }

    /// The `function` payload of a tool call.
    struct Function: Decodable, Sendable, Equatable {
        var name: String?
        /// Absent when the server omits `arguments`; the caller defaults to `""`.
        var arguments: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            arguments = try? container.decodeIfPresent(String.self, forKey: .arguments)
        }
    }

    /// Provider-specific sidecars on a tool call.
    struct ExtraContent: Decodable, Sendable, Equatable {
        var google: GoogleExtra?

        private enum CodingKeys: String, CodingKey {
            case google
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            google = try? container.decodeIfPresent(GoogleExtra.self, forKey: .google)
        }
    }

    /// Google `extra_content` sidecar (Gemini thought signatures).
    struct GoogleExtra: Decodable, Sendable, Equatable {
        var thoughtSignature: String?

        private enum CodingKeys: String, CodingKey {
            case thoughtSignature = "thought_signature"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            thoughtSignature = try? container.decodeIfPresent(String.self, forKey: .thoughtSignature)
        }
    }

    /// A `usage` payload with lenient counts.
    struct Usage: Decodable, Sendable, Equatable {
        var promptTokens: Int?
        var completionTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            promptTokens = OpenAICompatibleWire.lenientInt(from: container, forKey: .promptTokens)
            completionTokens = OpenAICompatibleWire.lenientInt(from: container, forKey: .completionTokens)
        }
    }

    /// An `error` payload on a 200 stream frame.
    struct WireError: Decodable, Sendable, Equatable {
        var message: String?

        private enum CodingKeys: String, CodingKey {
            case message
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try? container.decodeIfPresent(String.self, forKey: .message)
        }
    }

    /// Reads an integer that tolerates floating-point counts, matching the
    /// previous `NSNumber` coercion (`11.0` reads as `11`, `1.5` truncates).
    private static func lenientInt<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let double = try? container.decodeIfPresent(Double.self, forKey: key) {
            // `Int(_:)` traps out of range; degrade like any other mistyped
            // count instead of crashing on absurd server payloads.
            guard double.isFinite,
                  double < Double(Int.max),
                  double > Double(Int.min)
            else {
                return nil
            }
            return Int(double)
        }
        return nil
    }

    // MARK: - Encode

    /// A chat-completions request body. Optional fields are omitted when `nil`.
    struct Request: Encodable, Sendable, Equatable {
        var model: String
        var messages: [RequestMessage]
        var temperature: Double
        var maxTokens: Int?
        /// Set only when non-empty.
        var stop: [String]?
        var topP: Double?
        var presencePenalty: Double?
        var frequencyPenalty: Double?
        var seed: Int?
        var parallelToolCalls: Bool?
        /// Set only when non-empty.
        var tools: [RequestTool]?
        /// Set only when tools are present and a choice is configured.
        var toolChoice: RequestToolChoice?
        /// `true` when streaming, otherwise omitted (never `false`).
        var stream: Bool?
        /// Set only when streaming.
        var streamOptions: StreamOptions?
        /// Set only for native structured turns without tools.
        var responseFormat: ResponseFormat?

        private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case stop
            case topP = "top_p"
            case presencePenalty = "presence_penalty"
            case frequencyPenalty = "frequency_penalty"
            case seed
            case parallelToolCalls = "parallel_tool_calls"
            case tools
            case toolChoice = "tool_choice"
            case stream
            case streamOptions = "stream_options"
            case responseFormat = "response_format"
        }
    }

    /// One request message.
    struct RequestMessage: Encodable, Sendable, Equatable {
        var role: String
        var content: RequestMessageContent
        var name: String?
        var toolCallID: String?
        /// Set only when non-empty.
        var toolCalls: [RequestToolCall]?

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case name
            case toolCallID = "tool_call_id"
            case toolCalls = "tool_calls"
        }
    }

    /// Request message `content`: plain text, or text plus multimodal parts.
    ///
    /// Encodes as a JSON string when there are no parts, otherwise as a
    /// content-part array, matching the chat-completions wire shape.
    enum RequestMessageContent: Encodable, Sendable, Equatable {
        case text(String)
        case parts([RequestContentPart])

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(text):
                try container.encode(text)
            case let .parts(parts):
                try container.encode(parts)
            }
        }
    }

    /// One multimodal content part of a request message.
    enum RequestContentPart: Encodable, Sendable, Equatable {
        case text(String)
        case inputAudio(data: String, format: String)
        case imageURL(String)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .text(text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case let .inputAudio(data, format):
                try container.encode("input_audio", forKey: .type)
                var audio = container.nestedContainer(keyedBy: AudioKeys.self, forKey: .inputAudio)
                try audio.encode(data, forKey: .data)
                try audio.encode(format, forKey: .format)
            case let .imageURL(url):
                try container.encode("image_url", forKey: .type)
                var image = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
                try image.encode(url, forKey: .url)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case inputAudio = "input_audio"
            case imageURL = "image_url"
        }

        private enum AudioKeys: String, CodingKey {
            case data
            case format
        }

        private enum ImageKeys: String, CodingKey {
            case url
        }
    }

    /// One request tool call on an assistant message.
    struct RequestToolCall: Encodable, Sendable, Equatable {
        var id: String
        var type: String = "function"
        var function: RequestToolCallFunction
        var extraContent: ThoughtSignatureExtra?

        private enum CodingKeys: String, CodingKey {
            case id
            case type
            case function
            case extraContent = "extra_content"
        }
    }

    /// The `function` payload of a request tool call.
    struct RequestToolCallFunction: Encodable, Sendable, Equatable {
        var name: String
        var arguments: String
    }

    /// Thought-signature sidecar echoed on signed calls only.
    struct ThoughtSignatureExtra: Encodable, Sendable, Equatable {
        var google: ThoughtSignatureGoogle
    }

    /// Google `extra_content` sidecar.
    struct ThoughtSignatureGoogle: Encodable, Sendable, Equatable {
        var thoughtSignature: String

        private enum CodingKeys: String, CodingKey {
            case thoughtSignature = "thought_signature"
        }
    }

    /// One request tool definition.
    struct RequestTool: Encodable, Sendable, Equatable {
        var type: String = "function"
        var function: RequestToolFunction
    }

    /// The `function` payload of a request tool.
    struct RequestToolFunction: Encodable, Sendable, Equatable {
        var name: String
        var description: String
        var parameters: SendableValue
    }

    /// Request `tool_choice`: a mode string or a function reference.
    enum RequestToolChoice: Encodable, Sendable, Equatable {
        case auto
        case none
        case required
        case specific(toolName: String)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .auto:
                var container = encoder.singleValueContainer()
                try container.encode("auto")
            case .none:
                var container = encoder.singleValueContainer()
                try container.encode("none")
            case .required:
                var container = encoder.singleValueContainer()
                try container.encode("required")
            case let .specific(toolName):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("function", forKey: .type)
                var function = container.nestedContainer(keyedBy: FunctionKeys.self, forKey: .function)
                try function.encode(toolName, forKey: .name)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case function
        }

        private enum FunctionKeys: String, CodingKey {
            case name
        }
    }

    /// Request `stream_options`.
    struct StreamOptions: Encodable, Sendable, Equatable {
        var includeUsage: Bool

        private enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    /// Request `response_format`.
    enum ResponseFormat: Encodable, Sendable, Equatable {
        case jsonObject
        case jsonSchema(name: String, schema: SendableValue)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .jsonObject:
                try container.encode("json_object", forKey: .type)
            case let .jsonSchema(name, schema):
                try container.encode("json_schema", forKey: .type)
                var nested = container.nestedContainer(keyedBy: SchemaKeys.self, forKey: .jsonSchema)
                try nested.encode(name, forKey: .name)
                try nested.encode(schema, forKey: .schema)
                try nested.encode(true, forKey: .strict)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }

        private enum SchemaKeys: String, CodingKey {
            case name
            case schema
            case strict
        }
    }
}
