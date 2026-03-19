import Foundation

/// Provider-agnostic structured output request owned by Swarm.
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
    public enum Source: String, Sendable, Equatable, Codable {
        case providerNative = "provider_native"
        case promptFallback = "prompt_fallback"
    }

    public var format: StructuredOutputFormat
    public var rawJSON: String
    public var value: SendableValue
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

public protocol StructuredOutputInferenceProvider: InferenceProvider {
    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult
}

public protocol StructuredOutputConversationInferenceProvider: ConversationInferenceProvider {
    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult
}

public extension InferenceProvider {
    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let structuredPrompt = StructuredOutputPromptBuilder.appendInstruction(to: prompt, request: request)
        let text = try await generate(prompt: structuredPrompt, options: options)
        return try StructuredOutputParser.parse(text, request: request, source: .promptFallback)
    }
}

public extension ConversationInferenceProvider {
    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        let structuredMessages = StructuredOutputPromptBuilder.appendInstruction(to: messages, request: request)
        let text = try await generate(messages: structuredMessages, options: options)
        return try StructuredOutputParser.parse(text, request: request, source: .promptFallback)
    }
}
