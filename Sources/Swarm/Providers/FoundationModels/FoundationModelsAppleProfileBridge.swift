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
        case prompt(text: String, images: [PendingImage])
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
        var pendingImages: [PendingImage]
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
        let pendingImages: [PendingImage]
        if case let .prompt(text, images) = entries.last, messages.last?.role == .user {
            pending = text
            pendingImages = images
            entries.removeLast()
        } else {
            let fallback = messages.last(where: { $0.role == .user }) ?? messages.last
            pending = fallback?.content ?? ""
            pendingImages = fallback.map { FoundationModelsImageAttachments.pendingImages(in: $0) } ?? []
        }
        return Seed(
            instructions: instructions,
            seedEntries: entries,
            pendingPrompt: pending,
            pendingImages: pendingImages,
            canRehydrateTranscript: mapped.canRehydrate && messages.last?.role == .user
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
                let images = FoundationModelsImageAttachments.pendingImages(in: message)
                guard !message.content.isEmpty || !images.isEmpty else { continue }
                entries.append(.prompt(text: message.content, images: images))
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
        case let .prompt(text, images):
            return .prompt(
                Transcript.Prompt(
                    id: UUID().uuidString,
                    segments: promptSegments(text: text, images: images),
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

    /// Text plus one attachment segment per image on OS 27. Older systems
    /// keep the text-only segment; image sidecars need OS 27.
    private static func promptSegments(text: String, images: [PendingImage]) -> [Transcript.Segment] {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *), !images.isEmpty {
            return FoundationModelsImageAttachments.transcriptSegments(text: text, images: images)
        }
        return [textSegment(text)]
    }
}
#endif
