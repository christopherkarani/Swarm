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
    /// Whether JSON parse failure is fatal on the untyped
    /// ``Agent/runStructured(_:request:session:observer:)`` path.
    ///
    /// The default `true` throws ``AgentError/generationFailed(reason:)`` when
    /// the assistant text is not valid JSON. When `false`, parse failure
    /// returns ``StructuredAgentResult`` whose ``StructuredOutputResult/value``
    /// is `.null` and ``StructuredOutputResult/rawJSON`` is the assistant text.
    /// Typed ``Agent/runStructured(_:_:request:session:observer:)`` still throws
    /// ``AgentError/structuredOutputDecodingFailed(reason:underlying:)`` if
    /// `Output` cannot be decoded.
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

/// Agent result plus a decoded structured payload.
///
/// Returned by ``Agent/runStructured(_:_:request:session:observer:)`` when the
/// caller supplies an `Output` type. ``StructuredAgentResult`` remains the
/// untyped companion from the non-generic
/// ``Agent/runStructured(_:request:session:observer:)``.
public struct DecodedStructuredAgentResult<Output: Sendable>: Sendable {
    /// The completed agent run.
    public let agentResult: AgentResult
    /// Parsed JSON as ``SendableValue``, plus the raw text decoded as `Output`.
    public let structuredOutput: StructuredOutputResult
    /// The decoded `Output` value.
    public let output: Output

    public init(
        agentResult: AgentResult,
        structuredOutput: StructuredOutputResult,
        output: Output
    ) {
        self.agentResult = agentResult
        self.structuredOutput = structuredOutput
        self.output = output
    }
}

extension DecodedStructuredAgentResult where Output: Decodable {
    static func decoding(_ result: StructuredAgentResult, as type: Output.Type) throws -> Self {
        do {
            let data = Data(result.structuredOutput.rawJSON.utf8)
            let output = try JSONDecoder().decode(type, from: data)
            return Self(
                agentResult: result.agentResult,
                structuredOutput: result.structuredOutput,
                output: output
            )
        } catch {
            throw AgentError.structuredOutputDecodingFailed(
                reason: "Failed to decode structured output as \(type)",
                underlying: error
            )
        }
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
            return try parseFailure(
                assistantText: text,
                request: request,
                source: source,
                reason: "Structured output is not valid UTF-8"
            )
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
            return try parseFailure(
                assistantText: text,
                request: request,
                source: source,
                reason: "Failed to parse structured output JSON: \(error.localizedDescription)"
            )
        }
    }

    private static func parseFailure(
        assistantText: String,
        request: StructuredOutputRequest,
        source: StructuredOutputResult.Source,
        reason: String
    ) throws -> StructuredOutputResult {
        guard request.required == false else {
            throw AgentError.generationFailed(reason: reason)
        }
        return StructuredOutputResult(
            format: request.format,
            rawJSON: assistantText,
            value: .null,
            source: source
        )
    }
}

/// Native structured-output prompt hook.
///
/// Agent dispatches from ``InferenceProviderCapabilities/structuredOutputs`` and
/// ``InferenceProvider/generateStructured(messages:request:options:)``. This
/// deprecated protocol remains as a source-compatible marker for existing
/// providers; it is not the Agent dispatch seam.
@available(*, deprecated, message: "Declare InferenceProviderCapabilities.structuredOutputs and override generateStructured on InferenceProvider")
public protocol StructuredOutputInferenceProvider: InferenceProvider {
    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult
}

@available(*, deprecated, renamed: "InferenceProvider")
public protocol StructuredOutputConversationInferenceProvider: ConversationInferenceProvider {}
