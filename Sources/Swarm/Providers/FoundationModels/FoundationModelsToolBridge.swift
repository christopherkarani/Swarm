// FoundationModelsToolBridge.swift
// Swarm Framework
//
// Bridges Swarm tool schemas to Apple FoundationModels.Tool for native tool calling.
//
// Apple's FoundationModels framework defines its own `Tool` protocol. Swarm also
// exposes a public `Tool` protocol for agent tools. These types intentionally share
// a short name but live in different modules. This bridge always refers to
// `FoundationModels.Tool` explicitly to avoid the compile-time clash engineers hit
// when importing both Swarm and FoundationModels in the same file.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Per-turn store of tool calls captured from Foundation Models.
///
/// Capture tools record into this actor and return
/// ``FoundationModelsCaptureTool/sentinelOutput`` so Apple can invoke every
/// tool in a parallel `Transcript.ToolCalls` group. Swarm then takes the
/// **first** tool-call group from the turn transcript (request order) and
/// discards later inner-loop calls that were based on sentinel results.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
actor FoundationModelsToolCaptureStore {
    private var calls: [InferenceResponse.ParsedToolCall] = []

    func record(_ call: InferenceResponse.ParsedToolCall) {
        calls.append(call)
    }

    func snapshot() -> [InferenceResponse.ParsedToolCall] {
        calls
    }
}

/// Error thrown from a capture tool so Swarm can reclaim control of tool execution.
///
/// The default capture path records calls and returns a sentinel instead of
/// throwing, so a single `LanguageModelSession.respond` can surface N parallel
/// tool calls. This error remains for SDK `ToolCallError` wrapping and as a
/// fallback when a capture tool still throws (tests, later-wave abort).
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsToolCaptureError: Error, Sendable {
    let toolCall: InferenceResponse.ParsedToolCall
}

/// A dynamic FoundationModels tool backed by a Swarm `ToolSchema`.
///
/// Uses guided generation (`GenerationSchema`) for argument typing instead of
/// prompt-injected JSON envelopes. Arguments are always `GeneratedContent` so
/// any Swarm schema can be represented without per-tool `@Generable` types.
///
/// `call(arguments:)` records the invocation into a per-turn store and returns
/// ``sentinelOutput`` rather than throwing, so Apple can finish the rest of
/// the current `ToolCalls` group.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsCaptureTool: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    /// Documented sentinel returned in place of a real tool result.
    ///
    /// Swarm intercepts the call and executes the tool in the agent loop.
    /// The model must not treat this string as successful tool output.
    static let sentinelOutput = """
    SWARM_CAPTURED: Swarm intercepted this tool call and will execute it after this turn. \
    This is not a real tool result. Do not call more tools based on this string.
    """

    let name: String
    let description: String
    let parameters: GenerationSchema
    let store: FoundationModelsToolCaptureStore
    var includesSchemaInInstructions: Bool { true }

    func call(arguments: GeneratedContent) async throws -> String {
        let parsed = InferenceResponse.ParsedToolCall(
            id: UUID().uuidString,
            name: name,
            arguments: FoundationModelsSchemaConversion.argumentDictionary(from: arguments)
        )
        await store.record(parsed)
        return Self.sentinelOutput
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum FoundationModelsToolBridge {
    /// Builds native Foundation Models tools from Swarm schemas.
    ///
    /// - Parameters:
    ///   - tools: Swarm provider-facing tool schemas.
    ///   - store: Per-turn capture store shared by every returned tool.
    /// - Returns: Type-erased FoundationModels tools ready for `LanguageModelSession`.
    static func makeCaptureTools(
        from tools: [ToolSchema],
        store: FoundationModelsToolCaptureStore
    ) throws -> [any FoundationModels.Tool] {
        try tools.map { schema in
            let parameters = try FoundationModelsSchemaConversion.argumentSchema(for: schema)
            return FoundationModelsCaptureTool(
                name: schema.name,
                description: schema.description,
                parameters: parameters,
                store: store
            )
        }
    }

    /// Builds an inference response from captured calls and this turn's transcript.
    ///
    /// Policy:
    /// - Prefer the first non-empty `Transcript.toolCalls` group that appears
    ///   **before** any post-tool response (Apple's request order).
    /// - Empty placeholder groups are skipped only until that first real group
    ///   or a post-tool `.response` (sentinel-mediated text).
    /// - Carry assistant text that appeared **before** the first tool-call marker.
    /// - Discard post-tool `response` text.
    /// - Fall back to the store only when the transcript recorded **no**
    ///   `toolCalls` entries (session aborted before Apple wrote a group).
    ///   Once a `toolCalls` marker exists, later-wave store contents are ignored.
    /// - If a capture tool still threw and nothing else was recovered, use the
    ///   throw-path converter.
    static func inferenceResponse(
        store: FoundationModelsToolCaptureStore,
        turnEntries: [Transcript.Entry],
        error: Error? = nil
    ) async -> InferenceResponse? {
        let stored = await store.snapshot()
        let fromTranscript = firstWave(from: turnEntries)
        let calls: [InferenceResponse.ParsedToolCall]
        let accompanying: String?

        if let fromTranscript, !fromTranscript.calls.isEmpty {
            calls = fromTranscript.calls
            accompanying = fromTranscript.accompanyingContent
        } else if fromTranscript == nil, !stored.isEmpty {
            calls = stored
            accompanying = nil
        } else if let error, let thrown = inferenceResponse(from: error) {
            return thrown
        } else {
            return nil
        }

        let trimmed = accompanying?.trimmingCharacters(in: .whitespacesAndNewlines)
        return InferenceResponse(
            content: (trimmed?.isEmpty == false) ? trimmed : nil,
            toolCalls: calls,
            finishReason: .toolCall
        )
    }

    /// Extracts a Swarm tool-call response from a Foundation Models error, if present.
    static func inferenceResponse(from error: Error) -> InferenceResponse? {
        if let capture = error as? FoundationModelsToolCaptureError {
            return InferenceResponse(
                content: nil,
                toolCalls: [capture.toolCall],
                finishReason: .toolCall
            )
        }

        if let toolCallError = error as? LanguageModelSession.ToolCallError,
           let capture = toolCallError.underlyingError as? FoundationModelsToolCaptureError
        {
            return InferenceResponse(
                content: nil,
                toolCalls: [capture.toolCall],
                finishReason: .toolCall
            )
        }

        // Walk a single level of wrapping for resilience across SDK revisions.
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return inferenceResponse(from: underlying)
        }

        return nil
    }

    // MARK: - Transcript first wave

    struct FirstWave: Sendable {
        var accompanyingContent: String?
        var calls: [InferenceResponse.ParsedToolCall]
    }

    static func firstWave(from entries: [Transcript.Entry]) -> FirstWave? {
        var accompanying: [String] = []
        var sawToolCalls = false
        entryLoop: for entry in entries {
            switch entry {
            case let .response(response):
                if sawToolCalls {
                    // Sentinel-mediated continuation. Do not treat later tool
                    // groups as the first wave.
                    break entryLoop
                }
                let text = FoundationModelsNativeTranscriptMapper.concatenatedText(response.segments)
                if !text.isEmpty {
                    accompanying.append(text)
                }
            case let .toolCalls(calls):
                sawToolCalls = true
                let parsed = calls.map { call in
                    InferenceResponse.ParsedToolCall(
                        id: call.id,
                        name: call.toolName,
                        arguments: FoundationModelsSchemaConversion.argumentDictionary(from: call.arguments)
                    )
                }
                if !parsed.isEmpty {
                    let joined = accompanying.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return FirstWave(
                        accompanyingContent: joined.isEmpty ? nil : joined,
                        calls: parsed
                    )
                }
            default:
                continue
            }
        }
        guard sawToolCalls else {
            return nil
        }
        let joined = accompanying.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FirstWave(
            accompanyingContent: joined.isEmpty ? nil : joined,
            calls: []
        )
    }
}
#endif
