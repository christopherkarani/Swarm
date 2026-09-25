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
        case prompt(text: String, images: [PendingImage])
        case response(String)
        case toolOutput(name: String, content: String, toolCallID: String?)
    }

    struct Seed: Sendable, Equatable {
        var instructions: String?
        var seedEntries: [Entry]
        var pendingPrompt: String
        var pendingImages: [PendingImage]
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
            canRehydrate: mapped.canRehydrate && messages.last?.role == .user
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
            case let .prompt(text, _):
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
