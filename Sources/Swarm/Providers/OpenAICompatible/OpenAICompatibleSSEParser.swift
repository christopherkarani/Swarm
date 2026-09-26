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
              let chunk = try? OpenAICompatibleChatChunk(decoding: data)
        else {
            return [.malformed(payload)]
        }
        return [.chunk(chunk)]
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
