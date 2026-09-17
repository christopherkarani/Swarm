import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Maps a resolved Swarm ``Profile`` onto owned-loop session inputs.
///
/// This is **not** Apple's `LanguageModelSession.DynamicProfile`. Swarm
/// ``DynamicProfile`` / ``Profile`` / ``ProfileHistoryPolicy`` stay Swarm
/// types. Owned-loop uses the resolved instructions, tool filter, and
/// history policy. Capture still goes through ``DynamicProfileResolution``.
enum FoundationModelsAppleProfileBridge: Sendable {
    /// Linux-safe transcript-shaped entry. Apple `Transcript` is built only
    /// when every message is text-only.
    enum Entry: Sendable, Equatable {
        case instructions(String)
        case prompt(String)
        case response(String)
        case toolOutput(name: String, content: String, toolCallID: String?)
    }

    /// Full resolve of a Swarm profile for an owned-loop turn.
    struct Plan: Sendable, Equatable {
        var instructions: String?
        var tools: [ToolSchema]
        var options: InferenceOptions
        var messages: [InferenceMessage]
        var entries: [Entry]
        var canRehydrateTranscript: Bool
    }

    /// History to seed onto a new `LanguageModelSession`, minus the pending user prompt.
    struct Seed: Sendable, Equatable {
        var instructions: String?
        var seedEntries: [Entry]
        var pendingPrompt: String
        var canRehydrateTranscript: Bool
    }

    static func plan(
        profile: Profile?,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        baseInstructions: String?
    ) -> Plan {
        let applied = DynamicProfileResolution.apply(
            profile,
            messages: messages,
            tools: tools,
            options: options,
            baseInstructions: baseInstructions
        )
        let withSystem = DynamicProfileResolution.messagesByInjectingInstructions(
            applied.instructions,
            into: applied.messages
        )
        let mapped = mapEntries(messages: withSystem, instructions: applied.instructions)
        return Plan(
            instructions: applied.instructions,
            tools: applied.tools,
            options: applied.options,
            messages: withSystem,
            entries: mapped.entries,
            canRehydrateTranscript: mapped.canRehydrate
        )
    }

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
            canRehydrateTranscript: mapped.canRehydrate
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
                // Extra system text has no Instructions/Prompt split we trust.
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
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension FoundationModelsAppleProfileBridge {
    /// Builds an Apple `Transcript` from text-only bridged entries.
    ///
    /// Returns `nil` when `entries` is empty so the caller can fall back to
    /// `LanguageModelSession(model:tools:instructions:)`.
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
                    segments: [textSegment(text)]
                )
            )
        case let .response(text):
            return .response(
                Transcript.Response(
                    id: UUID().uuidString,
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
