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

/// Error thrown from a capture tool so Swarm can reclaim control of tool execution.
///
/// Foundation Models invokes tools inside `LanguageModelSession.respond(to:)`.
/// Swarm's agent runtime owns tool execution (guardrails, observers, retries).
/// Capture tools therefore record the model's structured arguments and throw,
/// surfacing a single tool-call round-trip that Swarm can execute itself.
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
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsCaptureTool: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    var includesSchemaInInstructions: Bool { true }

    func call(arguments: GeneratedContent) async throws -> String {
        let parsed = InferenceResponse.ParsedToolCall(
            id: UUID().uuidString,
            name: name,
            arguments: FoundationModelsSchemaConversion.argumentDictionary(from: arguments)
        )
        throw FoundationModelsToolCaptureError(toolCall: parsed)
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum FoundationModelsToolBridge {
    /// Builds native Foundation Models tools from Swarm schemas.
    ///
    /// - Parameter tools: Swarm provider-facing tool schemas.
    /// - Returns: Type-erased FoundationModels tools ready for `LanguageModelSession`.
    static func makeCaptureTools(from tools: [ToolSchema]) throws -> [any FoundationModels.Tool] {
        try tools.map { schema in
            let parameters = try FoundationModelsSchemaConversion.argumentSchema(for: schema)
            return FoundationModelsCaptureTool(
                name: schema.name,
                description: schema.description,
                parameters: parameters
            )
        }
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
}
#endif
