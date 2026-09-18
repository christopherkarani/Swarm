import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Maps capture-mode ``InferenceMessage`` history onto transcript-shaped
/// entries so Apple can see roles natively.
///
/// Flattening remains the fallback when a message cannot be represented
/// (assistant tool-call metadata, extra system text). This is not Apple's
/// `LanguageModelSession.DynamicProfile`.
enum FoundationModelsCaptureTranscript: Sendable {
    enum Entry: Sendable, Equatable {
        case instructions(String)
        case prompt(String)
        case response(String)
        case toolOutput(name: String, content: String, toolCallID: String?)
    }

    struct Seed: Sendable, Equatable {
        var instructions: String?
        var seedEntries: [Entry]
        var pendingPrompt: String
        var canRehydrate: Bool
    }

    /// Returns a seed when every message maps; `canRehydrate` is false when
    /// the session must still flatten.
    static func seed(
        messages: [InferenceMessage],
        instructions: String?
    ) -> Seed {
        let mapped = mapEntries(messages: messages, instructions: instructions)
        var entries = mapped.entries
        let pending: String
        if case let .prompt(text) = entries.last, messages.last?.role == .user {
            pending = text
            entries.removeLast()
        } else {
            pending = messages.last(where: { $0.role == .user })?.content
                ?? messages.last?.content
                ?? ""
        }
        return Seed(
            instructions: instructions,
            seedEntries: entries,
            pendingPrompt: pending,
            canRehydrate: mapped.canRehydrate
        )
    }

    static func mapEntries(
        messages: [InferenceMessage],
        instructions: String?
    ) -> (entries: [Entry], canRehydrate: Bool) {
        var entries: [Entry] = []
        if let instructions, !instructions.isEmpty {
            entries.append(.instructions(instructions))
        }

        var canRehydrate = true
        for message in messages {
            switch message.role {
            case .system:
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if text == instructions {
                    continue
                }
                canRehydrate = false
            case .user:
                guard !message.content.isEmpty else { continue }
                entries.append(.prompt(message.content))
            case .assistant:
                if !message.toolCalls.isEmpty {
                    canRehydrate = false
                    continue
                }
                guard !message.content.isEmpty else { continue }
                entries.append(.response(message.content))
            case .tool:
                // Apple Transcript pairs ToolOutput with a preceding ToolCalls
                // group. This mapper never emits ToolCalls, so unpaired tool
                // results cannot rehydrate.
                canRehydrate = false
                entries.append(
                    .toolOutput(
                        name: message.name ?? "",
                        content: message.content,
                        toolCallID: message.toolCallID
                    )
                )
            }
        }
        return (entries, canRehydrate)
    }

    /// Inverse of ``mapEntries(messages:instructions:)`` for golden tests.
    /// Instructions entries are omitted — they are session configuration.
    static func messages(from entries: [Entry]) -> [InferenceMessage] {
        entries.compactMap { entry in
            switch entry {
            case .instructions:
                return nil
            case let .prompt(text):
                return .user(text)
            case let .response(text):
                return .assistant(text)
            case let .toolOutput(name, content, toolCallID):
                return .tool(name: name, content: content, toolCallID: toolCallID)
            }
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension FoundationModelsCaptureTranscript {
    static func makeTranscript(from entries: [Entry]) -> Transcript? {
        guard !entries.isEmpty else { return nil }
        return Transcript(entries: entries.map(appleEntry(from:)))
    }

    private static func appleEntry(from entry: Entry) -> Transcript.Entry {
        switch entry {
        case let .instructions(text):
            return .instructions(
                Transcript.Instructions(
                    id: UUID().uuidString,
                    segments: [textSegment(text)],
                    toolDefinitions: []
                )
            )
        case let .prompt(text):
            return .prompt(
                Transcript.Prompt(
                    id: UUID().uuidString,
                    segments: [textSegment(text)],
                    options: GenerationOptions()
                )
            )
        case let .response(text):
            return .response(
                Transcript.Response(
                    id: UUID().uuidString,
                    assetIDs: [],
                    segments: [textSegment(text)]
                )
            )
        case let .toolOutput(name, content, toolCallID):
            return .toolOutput(
                Transcript.ToolOutput(
                    id: toolCallID ?? UUID().uuidString,
                    toolName: name,
                    segments: [textSegment(content)]
                )
            )
        }
    }

    private static func textSegment(_ content: String) -> Transcript.Segment {
        .text(Transcript.TextSegment(id: UUID().uuidString, content: content))
    }
}
#endif
