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
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [.malformed(payload)]
        }
        return [.chunk(OpenAICompatibleChatChunk(json: object))]
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
    }

    init(json: [String: Any]) {
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
            return ToolCallDelta(
                index: call["index"] as? Int ?? offset,
                id: call["id"] as? String,
                name: function["name"] as? String,
                arguments: function["arguments"] as? String ?? ""
            )
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }
}
