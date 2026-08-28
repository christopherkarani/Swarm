// AgentTurnTranscript.swift
// Swarm Framework

import Foundation

/// Value-level owner for an agent turn's inference and persistence projections.
/// Effects remain in the surrounding Agent tool-loop shell.
struct AgentTurnTranscript: Sendable, Equatable {
    enum Message: Sendable, Equatable {
        case system(String)
        case user(String)
        case assistant(String, toolCalls: [InferenceResponse.ParsedToolCall] = [])
        case toolResult(toolName: String, result: String, toolCallID: String? = nil)

        var formatted: String {
            switch self {
            case let .system(content):
                return "[System]: \(content)"
            case let .user(content):
                return "[User]: \(content)"
            case let .assistant(content, toolCalls):
                if toolCalls.isEmpty { return "[Assistant]: \(content)" }
                let summary = toolCalls.map { "Calling tool: \($0.name)" }.joined(separator: ", ")
                if content.isEmpty { return "[Assistant]: \(summary)" }
                return "[Assistant]: \(content)\n[Assistant Tool Calls]: \(summary)"
            case let .toolResult(toolName, result, _):
                return "[Tool Result - \(toolName)]: \(result)"
            }
        }

        var inferenceMessage: InferenceMessage {
            switch self {
            case let .system(content): return .system(content)
            case let .user(content): return .user(content)
            case let .assistant(content, toolCalls):
                return .assistant(content, toolCalls: toolCalls.map(InferenceMessage.ToolCall.init))
            case let .toolResult(toolName, result, toolCallID):
                return .tool(name: toolName, content: result, toolCallID: toolCallID)
            }
        }

        init(_ message: InferenceMessage) {
            switch message.role {
            case .system: self = .system(message.content)
            case .user: self = .user(message.content)
            case .assistant:
                self = .assistant(
                    message.content,
                    toolCalls: message.toolCalls.map {
                        InferenceResponse.ParsedToolCall(id: $0.id, name: $0.name, arguments: $0.arguments)
                    }
                )
            case .tool:
                self = .toolResult(
                    toolName: message.name ?? "previous",
                    result: message.content,
                    toolCallID: message.toolCallID
                )
            }
        }
    }

    struct FinalizedResponse: Sendable, Equatable {
        let content: String
        let structuredOutput: StructuredOutputResult?

        init(content: String, structuredOutput: StructuredOutputResult? = nil) {
            self.content = content
            self.structuredOutput = structuredOutput
        }
    }

    private(set) var conversationMessages: [Message]
    private(set) var memoryMessages: [MemoryMessage]

    var inferenceMessages: [InferenceMessage] {
        conversationMessages.map(\.inferenceMessage)
    }

    init(conversationMessages: [Message] = [], memoryMessages: [MemoryMessage] = []) {
        self.conversationMessages = conversationMessages
        self.memoryMessages = memoryMessages
    }

    mutating func appendAssistant(
        content: String,
        toolCalls: [InferenceResponse.ParsedToolCall] = [],
        structuredOutput: StructuredOutputResult? = nil
    ) {
        conversationMessages.append(.assistant(content, toolCalls: toolCalls))
        memoryMessages.append(
            SwarmTranscriptCodec.encodeMessage(
                role: .assistant,
                content: content,
                toolCalls: toolCalls,
                structuredOutput: structuredOutput
            )
        )
    }

    mutating func appendToolResult(toolName: String, result: String, toolCallID: String? = nil) {
        conversationMessages.append(.toolResult(toolName: toolName, result: result, toolCallID: toolCallID))
        memoryMessages.append(
            SwarmTranscriptCodec.encodeMessage(
                role: .tool,
                content: result,
                toolName: toolName,
                toolCallID: toolCallID
            )
        )
    }

    mutating func appendOwnedLoopTranscript(
        _ messages: [InferenceMessage],
        finalizedResponse: FinalizedResponse
    ) {
        guard !messages.isEmpty else {
            appendAssistant(
                content: finalizedResponse.content,
                structuredOutput: finalizedResponse.structuredOutput
            )
            return
        }

        var ownedConversation = messages.map(Message.init)
        var ownedMemory = messages.map(SwarmTranscriptCodec.encode)
        if let structuredOutput = finalizedResponse.structuredOutput,
           let last = ownedConversation.indices.last
        {
            let toolCalls: [InferenceResponse.ParsedToolCall]
            if case let .assistant(_, calls) = ownedConversation[last] {
                toolCalls = calls
                ownedConversation[last] = .assistant(finalizedResponse.content, toolCalls: calls)
            } else {
                toolCalls = []
            }

            if ownedMemory[last].role == .assistant {
                let previous = ownedMemory[last]
                ownedMemory[last] = SwarmTranscriptCodec.encodeMessage(
                    role: .assistant,
                    content: finalizedResponse.content,
                    timestamp: previous.timestamp,
                    messageID: previous.id,
                    metadata: previous.metadata,
                    toolCalls: toolCalls,
                    structuredOutput: structuredOutput
                )
            }
        }

        conversationMessages.append(contentsOf: ownedConversation)
        memoryMessages.append(contentsOf: ownedMemory)
    }
}
