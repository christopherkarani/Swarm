import Foundation

/// Provider-agnostic structured output request owned by Swarm.
///
/// ``jsonObject`` asks for any JSON value via prompt instruction; it cannot be
/// lowered onto Foundation Models `GenerationSchema` (no property set to
/// guide). ``jsonSchema(name:schemaJSON:)`` uses native guided generation when
/// the schema is inside the documented GenerationSchema subset; otherwise the
/// same prompt+parse path runs and ``StructuredOutputResult/source`` stays
/// ``StructuredOutputResult/Source/promptFallback``.
public enum StructuredOutputFormat: Sendable, Equatable, Codable {
    case jsonObject
    case jsonSchema(name: String, schemaJSON: String)

    public var name: String? {
        switch self {
        case .jsonObject:
            return nil
        case .jsonSchema(let name, _):
            return name
        }
    }

    public var schemaJSON: String? {
        switch self {
        case .jsonObject:
            return nil
        case .jsonSchema(_, let schemaJSON):
            return schemaJSON
        }
    }
}

/// Swarm-owned request for a structured response.
public struct StructuredOutputRequest: Sendable, Equatable, Codable {
    public var format: StructuredOutputFormat
    public var required: Bool

    public init(format: StructuredOutputFormat, required: Bool = true) {
        self.format = format
        self.required = required
    }
}

/// Parsed structured output emitted by a provider or Swarm fallback path.
public struct StructuredOutputResult: Sendable, Equatable, Codable {
    /// How the JSON was produced.
    ///
    /// - ``providerNative``: the inference backend constrained generation
    ///   (Foundation Models `respond(to:schema:)` when the schema maps).
    /// - ``promptFallback``: Swarm appended JSON instructions and parsed the
    ///   reply. Used for ``StructuredOutputFormat/jsonObject``, unmappable
    ///   schemas, and providers without guided generation.
    public enum Source: String, Sendable, Equatable, Codable {
        case providerNative = "provider_native"
        case promptFallback = "prompt_fallback"
    }

    public var format: StructuredOutputFormat
    public var rawJSON: String
    public var value: SendableValue
    /// Which production path emitted ``rawJSON``. Survives on
    /// ``StructuredAgentResult/structuredOutput`` and as
    /// `structured_output.source` on ``AgentResult/metadata``.
    public var source: Source

    public init(
        format: StructuredOutputFormat,
        rawJSON: String,
        value: SendableValue,
        source: Source
    ) {
        self.format = format
        self.rawJSON = rawJSON
        self.value = value
        self.source = source
    }
}

/// Full agent result when a structured output contract is requested.
public struct StructuredAgentResult: Sendable, Equatable {
    public let agentResult: AgentResult
    public let structuredOutput: StructuredOutputResult

    public init(agentResult: AgentResult, structuredOutput: StructuredOutputResult) {
        self.agentResult = agentResult
        self.structuredOutput = structuredOutput
    }
}

enum StructuredOutputPromptBuilder {
    static func instruction(for request: StructuredOutputRequest) -> String {
        switch request.format {
        case .jsonObject:
            return """
            Respond with valid JSON only. Do not wrap it in markdown fences or explanatory prose.
            """
        case .jsonSchema(_, let schemaJSON):
            return """
            Respond with valid JSON only. It must match this JSON schema exactly:
            \(schemaJSON)
            """
        }
    }

    static func appendInstruction(
        to prompt: String,
        request: StructuredOutputRequest
    ) -> String {
        """
        \(prompt)

        \(instruction(for: request))
        """
    }

    static func appendInstruction(
        to messages: [InferenceMessage],
        request: StructuredOutputRequest
    ) -> [InferenceMessage] {
        var updated = messages
        updated.append(.user(instruction(for: request)))
        return updated
    }
}

enum StructuredOutputParser {
    static func parse(
        _ text: String,
        request: StructuredOutputRequest,
        source: StructuredOutputResult.Source
    ) throws -> StructuredOutputResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw AgentError.generationFailed(reason: "Structured output is not valid UTF-8")
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let value = SendableValue.fromJSONValue(object)
            return StructuredOutputResult(
                format: request.format,
                rawJSON: trimmed,
                value: value,
                source: source
            )
        } catch {
            throw AgentError.generationFailed(
                reason: "Failed to parse structured output JSON: \(error.localizedDescription)"
            )
        }
    }
}

@available(*, deprecated, renamed: "InferenceProvider")
public protocol StructuredOutputConversationInferenceProvider: ConversationInferenceProvider {}


