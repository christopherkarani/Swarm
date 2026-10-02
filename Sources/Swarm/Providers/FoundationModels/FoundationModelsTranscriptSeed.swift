import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Maps ``InferenceMessage`` history onto transcript-shaped entries so Apple
/// sees roles natively.
///
/// Both the capture turn (``FoundationModelsInferenceProvider/makeCaptureTurn(tools:messages:flattenTools:instructions:options:)``)
/// and the owned-loop session (`makeOwnedLoopSession`) seed from this one
/// module. Flattening remains the fallback when a message cannot be
/// represented (assistant tool-call metadata, extra system text). This is not
/// Apple's `LanguageModelSession.DynamicProfile`.
enum FoundationModelsTranscriptSeed: Sendable {
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

    /// One turn's rendered history: seed-first, flatten-fallback.
    ///
    /// This is the single owner of the history render choice. Representable
    /// history rehydrates as seed entries plus a pending prompt; anything
    /// else flattens into one prompt string. Capture (`makeCaptureTurn`) and
    /// the owned loop resolve here so the choice cannot drift between call
    /// sites. Both branches carry
    /// ``FoundationModelsPromptFlattening/appendTurnSuffixes(to:tools:options:)``,
    /// matching the previous per-site stitching.
    enum RenderedTurn: Sendable, Equatable {
        /// Rehydratable history: seed these entries, send this prompt.
        case rehydrate(seedEntries: [Entry], prompt: String, images: [PendingImage])
        /// Unrepresentable history: send this flattened prompt instead.
        case flatten(prompt: String, images: [PendingImage])

        /// Prompt text to send for the turn.
        var prompt: String {
            switch self {
            case let .rehydrate(_, prompt, _):
                prompt
            case let .flatten(prompt, _):
                prompt
            }
        }

        /// Pending-turn image sidecars.
        var images: [PendingImage] {
            switch self {
            case let .rehydrate(_, _, images):
                images
            case let .flatten(_, images):
                images
            }
        }
    }

    /// Resolves `messages` into the turn's rendered history.
    ///
    /// - Parameter historyResident: Pass true when the target session already
    ///   holds this history (owned-loop session reuse). The pending turn is
    ///   sent as-is instead of re-resolving seed-first/flatten-fallback.
    static func resolve(
        messages: [InferenceMessage],
        instructions: String?,
        tools: [ToolSchema],
        options: InferenceOptions,
        historyResident: Bool = false
    ) -> RenderedTurn {
        let seed = seed(messages: messages, instructions: instructions)
        if !historyResident, !seed.canRehydrate {
            return .flatten(
                prompt: FoundationModelsPromptFlattening.flatten(
                    messages: messages,
                    tools: tools,
                    options: options
                ),
                images: seed.pendingImages
            )
        }
        return .rehydrate(
            seedEntries: seed.seedEntries,
            prompt: FoundationModelsPromptFlattening.appendTurnSuffixes(
                to: seed.pendingPrompt,
                tools: tools,
                options: options
            ),
            images: seed.pendingImages
        )
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
extension FoundationModelsTranscriptSeed {
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
