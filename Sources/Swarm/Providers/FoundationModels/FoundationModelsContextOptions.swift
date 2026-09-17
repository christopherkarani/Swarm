import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// How much reasoning Apple Foundation Models should apply on OS 27.
///
/// Set this on ``FoundationModelsProviderConfiguration/reasoningLevel``.
/// `nil` there leaves Apple's default. The value is ignored on OS 26.
/// Swarm does not expose Apple's `.custom(String)` case.
public enum FoundationModelsReasoningLevel: Sendable, Equatable, CaseIterable {
    /// Maps onto Apple `ContextOptions.ReasoningLevel.light`.
    case light
    /// Maps onto Apple `ContextOptions.ReasoningLevel.moderate`.
    case moderate
    /// Maps onto Apple `ContextOptions.ReasoningLevel.deep`.
    case deep
}

#if canImport(FoundationModels)
/// Builds OS 27 `ContextOptions` from Swarm configuration.
///
/// Text generate/stream leave `includeSchemaInPrompt` at Apple's default
/// (`nil`). Structured generate sets it on `ContextOptions` rather than the
/// OS 26 `includeSchemaInPrompt:` argument.
enum FoundationModelsContextOptions: Sendable {
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func appleReasoningLevel(
        from level: FoundationModelsReasoningLevel
    ) -> ContextOptions.ReasoningLevel {
        switch level {
        case .light: .light
        case .moderate: .moderate
        case .deep: .deep
        }
    }

    /// Builds `ContextOptions` without forcing a reasoning level when `nil`.
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func make(
        reasoningLevel: FoundationModelsReasoningLevel?,
        includeSchemaInPrompt: Bool? = nil
    ) -> ContextOptions {
        ContextOptions(
            includeSchemaInPrompt: includeSchemaInPrompt,
            reasoningLevel: reasoningLevel.map(appleReasoningLevel(from:))
        )
    }

    /// Text generate/stream: reasoning only; schema inclusion stays Apple's default.
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func text(reasoningLevel: FoundationModelsReasoningLevel?) -> ContextOptions {
        make(reasoningLevel: reasoningLevel)
    }

    /// Structured generate: schema included via `contextOptions:`, not the
    /// `includeSchemaInPrompt:` argument.
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func structured(reasoningLevel: FoundationModelsReasoningLevel?) -> ContextOptions {
        make(reasoningLevel: reasoningLevel, includeSchemaInPrompt: true)
    }

    static func respond(
        _ session: LanguageModelSession,
        to prompt: String,
        options: GenerationOptions,
        reasoningLevel: FoundationModelsReasoningLevel?
    ) async throws -> LanguageModelSession.Response<String> {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            return try await session.respond(
                to: prompt,
                options: options,
                contextOptions: text(reasoningLevel: reasoningLevel)
            )
        } else {
            return try await session.respond(to: prompt, options: options)
        }
    }

    static func streamResponse(
        _ session: LanguageModelSession,
        to prompt: String,
        options: GenerationOptions,
        reasoningLevel: FoundationModelsReasoningLevel?
    ) -> LanguageModelSession.ResponseStream<String> {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            return session.streamResponse(
                to: prompt,
                options: options,
                contextOptions: text(reasoningLevel: reasoningLevel)
            )
        } else {
            return session.streamResponse(to: prompt, options: options)
        }
    }

    static func respond(
        _ session: LanguageModelSession,
        to prompt: String,
        schema: GenerationSchema,
        options: GenerationOptions,
        reasoningLevel: FoundationModelsReasoningLevel?
    ) async throws -> LanguageModelSession.Response<GeneratedContent> {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            return try await session.respond(
                to: prompt,
                schema: schema,
                options: options,
                contextOptions: structured(reasoningLevel: reasoningLevel)
            )
        } else {
            return try await session.respond(
                to: prompt,
                schema: schema,
                includeSchemaInPrompt: true,
                options: options
            )
        }
    }
}
#endif
