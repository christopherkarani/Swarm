// OpenAICompatibleSSEParser.swift
// Swarm Framework
//
// Server-Sent Events parser for OpenAI-compatible chat completion streams.

import Foundation

/// One decoded SSE payload from an OpenAI-compatible stream.
enum OpenAICompatibleSSEEvent: Sendable, Equatable {
    case chunk(OpenAICompatibleChatChunk)
    case done
    case malformed(String)
}

/// Incremental SSE parser for `data:` lines, `[DONE]`, and multi-line events.
///
/// Malformed JSON lines are reported as ``OpenAICompatibleSSEEvent/malformed(_:)``
/// so the provider can skip them without aborting the stream.
struct OpenAICompatibleSSEParser: Sendable {
    private var pendingDataLines: [String] = []

    init() {}

    /// Consumes one raw SSE line (without the trailing LF).
    ///
    /// An empty line dispatches the accumulated `data:` payload. Comment lines
    /// (`:`) and unknown fields are ignored.
    mutating func consume(line: String) -> [OpenAICompatibleSSEEvent] {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if trimmed.isEmpty {
            return flushEvent()
        }
        if trimmed.hasPrefix(":") {
            return []
        }
        if trimmed.hasPrefix("data:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            pendingDataLines.append(payload)
            return []
        }
        return []
    }

    /// Flushes a trailing event that was not terminated by a blank line.
    mutating func finish() -> [OpenAICompatibleSSEEvent] {
        flushEvent()
    }

    private mutating func flushEvent() -> [OpenAICompatibleSSEEvent] {
        guard !pendingDataLines.isEmpty else {
            return []
        }
        let payload = pendingDataLines.joined(separator: "\n")
        pendingDataLines.removeAll(keepingCapacity: true)

        if payload == "[DONE]" {
            return [.done]
        }
        if payload.isEmpty {
            return []
        }
        guard let data = payload.data(using: .utf8) else {
            return [.malformed(payload)]
        }
        do {
            return [.chunk(try OpenAICompatibleChatChunk(jsonData: data))]
        } catch let error as OpenAICompatibleChunkDecodingError {
            switch error {
            case .shapeMismatch:
                return [.malformed("\(error); data: \(payload)")]
            case .invalidJSON:
                return [.malformed(payload)]
            }
        } catch {
            return [.malformed(payload)]
        }
    }
}

/// Fail-closed decoding failure for an OpenAI-compatible chunk payload.
///
/// Thrown by ``OpenAICompatibleChatChunk/init(jsonData:)`` when a present
/// field has the wrong shape. Absent fields still take their documented
/// defaults; only present-but-malformed fields fail.
enum OpenAICompatibleChunkDecodingError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Payload is not JSON, or not a JSON object.
    case invalidJSON(detail: String)
    /// Payload is JSON but `field` (dotted path, e.g. `choices[0].delta.tool_calls`) has the wrong shape.
    case shapeMismatch(field: String, detail: String)

    var description: String {
        switch self {
        case let .invalidJSON(detail):
            "invalid chunk JSON: \(detail)"
        case let .shapeMismatch(field, detail):
            "invalid shape for field '\(field)': \(detail)"
        }
    }
}

/// Decoded chat-completion chunk or full response object.
struct OpenAICompatibleChatChunk: Sendable, Equatable {
    var id: String?
    var choices: [Choice]
    var usage: TokenUsage?
    var errorMessage: String?

    struct Choice: Sendable, Equatable {
        var index: Int
        var finishReason: String?
        var message: Message?
        var delta: Message?
    }

    struct Message: Sendable, Equatable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCallDelta]
    }

    struct ToolCallDelta: Sendable, Equatable {
        var index: Int
        var id: String?
        var name: String?
        var arguments: String
        var thoughtSignature: String?
    }

    /// Decodes a chunk from already-parsed JSON.
    ///
    /// Typed fail-closed decoding is the primary path; payloads that fail
    /// typed decoding fall back to the legacy lenient parse here. The
    /// streaming path surfaces them as field-context `.malformed` events
    /// instead, and direct callers should use throwing ``init(jsonData:)``.
    init(json: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let typed = try? OpenAICompatibleChatChunk(jsonData: data)
        {
            self = typed
            return
        }
        self.init(lenientJSON: json)
    }

    /// Fail-closed typed decoding from wire bytes.
    ///
    /// - Throws: ``OpenAICompatibleChunkDecodingError`` naming the
    ///   mistyped field. Absent fields take documented defaults.
    init(jsonData data: Data) throws {
        let wire: WireChunkPayload
        do {
            wire = try JSONDecoder().decode(WireChunkPayload.self, from: data)
        } catch let error as DecodingError {
            throw Self.wrapDecodingError(error)
        }
        self.init(wire: wire)
    }

    private init(wire: WireChunkPayload) {
        id = wire.id
        usage = wire.usage
        errorMessage = wire.errorMessage
        choices = wire.choices.enumerated().map { offset, choice in
            Choice(
                index: choice.index ?? offset,
                finishReason: choice.finishReason,
                message: Self.mapMessage(choice.message),
                delta: Self.mapMessage(choice.delta)
            )
        }
    }

    private static func mapMessage(_ wire: WireMessagePayload?) -> Message? {
        guard let wire else {
            return nil
        }
        return Message(
            role: wire.role,
            content: wire.content,
            toolCalls: (wire.toolCalls ?? []).enumerated().map { offset, call in
                ToolCallDelta(
                    index: call.index ?? offset,
                    id: call.id,
                    name: call.function?.name,
                    arguments: call.function?.arguments ?? "",
                    thoughtSignature: call.extraContent?.google?.thoughtSignature
                )
            }
        )
    }

    private static func wrapDecodingError(_ error: DecodingError) -> OpenAICompatibleChunkDecodingError {
        let context: DecodingError.Context
        switch error {
        case let .typeMismatch(_, c),
             let .valueNotFound(_, c),
             let .keyNotFound(_, c),
             let .dataCorrupted(c):
            context = c
        @unknown default:
            return .invalidJSON(detail: "unrecognized decoding failure")
        }
        if context.codingPath.isEmpty {
            return .invalidJSON(detail: context.debugDescription)
        }
        return .shapeMismatch(
            field: dottedFieldPath(context.codingPath),
            detail: context.debugDescription
        )
    }

    private static func dottedFieldPath(_ path: [any CodingKey]) -> String {
        var result = ""
        for key in path {
            if let index = key.intValue {
                result += "[\(index)]"
            } else if result.isEmpty {
                result = key.stringValue
            } else {
                result += ".\(key.stringValue)"
            }
        }
        return result
    }

    private init(lenientJSON json: [String: Any]) {
        id = json["id"] as? String
        usage = Self.parseUsage(json["usage"])
        if let error = json["error"] as? [String: Any] {
            errorMessage = error["message"] as? String ?? "OpenAI-compatible stream error"
        } else {
            errorMessage = nil
        }
        let rawChoices = json["choices"] as? [[String: Any]] ?? []
        choices = rawChoices.enumerated().map { offset, choice in
            Choice(
                index: choice["index"] as? Int ?? offset,
                finishReason: choice["finish_reason"] as? String,
                message: Self.parseMessage(choice["message"]),
                delta: Self.parseMessage(choice["delta"])
            )
        }
    }

    static func parseUsage(_ value: Any?) -> TokenUsage? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        let prompt = intValue(object["prompt_tokens"])
        let completion = intValue(object["completion_tokens"])
        guard prompt != nil || completion != nil else {
            return nil
        }
        return TokenUsage(inputTokens: prompt ?? 0, outputTokens: completion ?? 0)
    }

    private static func parseMessage(_ value: Any?) -> Message? {
        guard let object = value as? [String: Any] else {
            return nil
        }
        let content: String?
        if object["content"] is NSNull {
            content = nil
        } else {
            content = object["content"] as? String
        }
        return Message(
            role: object["role"] as? String,
            content: content,
            toolCalls: parseToolCalls(object["tool_calls"])
        )
    }

    private static func parseToolCalls(_ value: Any?) -> [ToolCallDelta] {
        guard let array = value as? [[String: Any]] else {
            return []
        }
        return array.enumerated().map { offset, call in
            let function = call["function"] as? [String: Any] ?? [:]
            let extra = call["extra_content"] as? [String: Any] ?? [:]
            let google = extra["google"] as? [String: Any] ?? [:]
            return ToolCallDelta(
                index: call["index"] as? Int ?? offset,
                id: call["id"] as? String,
                name: function["name"] as? String,
                arguments: function["arguments"] as? String ?? "",
                thoughtSignature: google["thought_signature"] as? String
            )
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
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
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    /// Decodes one SSE or unary payload with a single throwing Codable decode.
    init(decoding data: Data) throws {
        let wire = try JSONDecoder().decode(OpenAICompatibleWire.Chunk.self, from: data)
        self.init(wire: wire)
    }

    /// Maps wire values onto chunk values, applying the documented lenient
    /// defaults: a missing choice or tool-call index falls back to its
    /// offset, and missing tool-call arguments default to `""`.
    init(wire: OpenAICompatibleWire.Chunk) {
        id = wire.id
        usage = Self.tokenUsage(from: wire.usage)
        if wire.error != nil {
            errorMessage = wire.error?.message ?? "OpenAI-compatible stream error"
        } else {
            errorMessage = nil
        }
        choices = wire.choices.enumerated().map { offset, choice in
            Choice(
                index: choice.index ?? offset,
                finishReason: choice.finishReason,
                message: Self.message(from: choice.message),
                delta: Self.message(from: choice.delta)
            )
        }
    }

    private static func tokenUsage(from usage: OpenAICompatibleWire.Usage?) -> TokenUsage? {
        guard let usage, usage.promptTokens != nil || usage.completionTokens != nil else {
            return nil
        }
        return TokenUsage(
            inputTokens: usage.promptTokens ?? 0,
            outputTokens: usage.completionTokens ?? 0
        )
    }

    private static func message(from wire: OpenAICompatibleWire.Message?) -> Message? {
        guard let wire else {
            return nil
        }
        return Message(
            role: wire.role,
            content: wire.content,
            toolCalls: wire.toolCalls.enumerated().map { offset, call in
                ToolCallDelta(
                    index: call.index ?? offset,
                    id: call.id,
                    name: call.function?.name,
                    arguments: call.function?.arguments ?? "",
                    thoughtSignature: call.extraContent?.google?.thoughtSignature
                )
            }
        )
    }
}

// MARK: - Fail-closed wire payloads

/// Typed chunk payload. Shapes fail closed, except for documented lossy
/// fields: `content` (compat gateways legitimately send array content
/// parts), `index` (falls back to the positional offset, as before),
/// vendor `extra_content`, auxiliary `usage`, and the `error` envelope
/// (already a failure signal).
private struct WireChunkPayload: Decodable, Sendable {
    var id: String?
    var choices: [WireChoicePayload]
    var usage: TokenUsage?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case choices
        case usage
        case error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        choices = try container.decodeIfPresent([WireChoicePayload].self, forKey: .choices) ?? []
        if let wireUsage = lossyDecode(WireUsagePayload.self, from: container, forKey: .usage),
           wireUsage.promptTokens != nil || wireUsage.completionTokens != nil
        {
            usage = TokenUsage(
                inputTokens: wireUsage.promptTokens ?? 0,
                outputTokens: wireUsage.completionTokens ?? 0
            )
        } else {
            usage = nil
        }
        if let wireError = lossyDecode(WireErrorPayload.self, from: container, forKey: .error) {
            errorMessage = wireError.message ?? "OpenAI-compatible stream error"
        } else {
            errorMessage = nil
        }
    }
}

private struct WireChoicePayload: Decodable, Sendable {
    var index: Int?
    var finishReason: String?
    var message: WireMessagePayload?
    var delta: WireMessagePayload?

    enum CodingKeys: String, CodingKey {
        case index
        case finishReason = "finish_reason"
        case message
        case delta
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = lossyDecode(Int.self, from: container, forKey: .index)
        finishReason = try container.decodeIfPresent(String.self, forKey: .finishReason)
        message = try container.decodeIfPresent(WireMessagePayload.self, forKey: .message)
        delta = try container.decodeIfPresent(WireMessagePayload.self, forKey: .delta)
    }
}

private struct WireMessagePayload: Decodable, Sendable {
    var role: String?
    var content: String?
    var toolCalls: [WireToolCallPayload]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        content = lossyDecode(String.self, from: container, forKey: .content)
        toolCalls = try container.decodeIfPresent([WireToolCallPayload].self, forKey: .toolCalls)
    }
}

private struct WireToolCallPayload: Decodable, Sendable {
    var index: Int?
    var id: String?
    var function: WireFunctionPayload?
    var extraContent: WireExtraContentPayload?

    enum CodingKeys: String, CodingKey {
        case index
        case id
        case function
        case extraContent = "extra_content"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = lossyDecode(Int.self, from: container, forKey: .index)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        function = try container.decodeIfPresent(WireFunctionPayload.self, forKey: .function)
        extraContent = lossyDecode(WireExtraContentPayload.self, from: container, forKey: .extraContent)
    }
}

private struct WireFunctionPayload: Decodable, Sendable {
    var name: String?
    var arguments: String?
}

private struct WireExtraContentPayload: Decodable, Sendable {
    var google: WireGoogleExtraPayload?
}

private struct WireGoogleExtraPayload: Decodable, Sendable {
    var thoughtSignature: String?

    enum CodingKeys: String, CodingKey {
        case thoughtSignature = "thought_signature"
    }
}

private struct WireUsagePayload: Decodable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = lossyTokenCount(from: container, forKey: .promptTokens)
        completionTokens = lossyTokenCount(from: container, forKey: .completionTokens)
    }
}

private struct WireErrorPayload: Decodable, Sendable {
    var message: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = lossyDecode(String.self, from: container, forKey: .message)
    }

    enum CodingKeys: String, CodingKey {
        case message
    }
}

/// Lossy optional decode: absent, null, or mistyped all yield nil.
private func lossyDecode<T: Decodable, K: CodingKey>(
    _: T.Type,
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> T? {
    let boxed = try? container.decodeIfPresent(T.self, forKey: key)
    return boxed ?? nil
}

/// Lossy token count mirroring the legacy coerce-then-truncate behavior
/// (integer, floating-point, or boolean wire values).
private func lossyTokenCount<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> Int? {
    if let int = lossyDecode(Int.self, from: container, forKey: key) {
        return int
    }
    if let double = lossyDecode(Double.self, from: container, forKey: key) {
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
    if let bool = lossyDecode(Bool.self, from: container, forKey: key) {
        return bool ? 1 : 0
    }
    return nil
}
