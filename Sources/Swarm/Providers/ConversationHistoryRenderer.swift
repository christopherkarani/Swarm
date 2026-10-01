// ConversationHistoryRenderer.swift
// Swarm Framework
//
// Single renderer for structured turn history → prompt text.

import Foundation

/// Renders structured turn history into prompt text.
///
/// The two flatten sites delegate here: ``InferenceMessage/flattenPrompt(_:)``
/// uses ``Style/bracketed`` for text-only backends and token counting, and
/// Foundation Models fallback flattening uses ``Style/plain``. One driver
/// loop; attachments stay off the text in both styles.
package enum ConversationHistoryRenderer: Sendable {
    /// Label dialect of the rendered history.
    package enum Style: Sendable {
        /// `[System]: …` blocks joined with blank lines. Every message
        /// contributes a block, even when its content is empty.
        case bracketed
        /// `System: …` lines joined with single newlines. Empty system and
        /// user turns are skipped.
        case plain
    }

    /// Renders `messages` as prompt text in `style`.
    package static func render(_ messages: [InferenceMessage], style: Style) -> String {
        let separator = switch style {
        case .bracketed: "\n\n"
        case .plain: "\n"
        }
        return lines(for: messages, style: style).joined(separator: separator)
    }

    /// Rendered lines for `messages` in `style`.
    package static func lines(for messages: [InferenceMessage], style: Style) -> [String] {
        messages.flatMap { lines(for: $0, style: style) }
    }

    /// Rendered lines for one message in `style`. Attachments never
    /// contribute text.
    package static func lines(for message: InferenceMessage, style: Style) -> [String] {
        switch (message.role, style) {
        case (.system, .bracketed):
            ["[System]: \(message.content)"]
        case (.system, .plain):
            message.content.isEmpty ? [] : ["System: \(message.content)"]
        case (.user, .bracketed):
            ["[User]: \(message.content)"]
        case (.user, .plain):
            message.content.isEmpty ? [] : ["User: \(message.content)"]
        case (.assistant, .bracketed):
            [bracketedAssistantLine(for: message)]
        case (.assistant, .plain):
            plainAssistantLines(for: message)
        case (.tool, .bracketed):
            ["[Tool Result - \(message.name ?? "tool")]: \(message.content)"]
        case (.tool, .plain):
            [plainToolLine(for: message)]
        }
    }

    private static func bracketedAssistantLine(for message: InferenceMessage) -> String {
        if message.toolCalls.isEmpty {
            return "[Assistant]: \(message.content)"
        }

        let summary = message.toolCalls
            .map { "Calling tool: \($0.name)" }
            .joined(separator: ", ")

        if message.content.isEmpty {
            return "[Assistant]: \(summary)"
        }

        return "[Assistant]: \(message.content)\n[Assistant Tool Calls]: \(summary)"
    }

    private static func plainAssistantLines(for message: InferenceMessage) -> [String] {
        var rendered: [String] = []
        if !message.toolCalls.isEmpty {
            rendered.append("Assistant requested tool calls:")
            for call in message.toolCalls {
                rendered.append("- \(call.name)(\(encodeArguments(call.arguments)))")
            }
        }
        if !message.content.isEmpty {
            rendered.append("Assistant: \(message.content)")
        }
        return rendered
    }

    private static func plainToolLine(for message: InferenceMessage) -> String {
        let prefix = message.name.map { "Tool result (\($0))" } ?? "Tool result"
        if let callID = message.toolCallID, !callID.isEmpty {
            return "\(prefix) [id=\(callID)]: \(message.content)"
        }
        return "\(prefix): \(message.content)"
    }

    private static func encodeArguments(_ arguments: [String: SendableValue]) -> String {
        var object: [String: Any] = [:]
        for (key, value) in arguments {
            object[key] = value.toJSONObject()
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}
