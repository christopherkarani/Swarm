//
//  LanguageModelSessionHelpers.swift
//  Swarm
//
//  Internal helpers for LanguageModelSession prompt building and tool call parsing.
//  Extracted to enable unit testing without requiring FoundationModels.
//

import Foundation

// MARK: - LanguageModelSessionToolCallingContext

/// Per-request metadata used to distinguish Swarm-owned tool-call envelopes from ordinary model text.
struct LanguageModelSessionToolCallingContext: Sendable, Equatable {
    static let envelopeKey = "swarm_tool_call"

    let nonce: String

    static func make() -> LanguageModelSessionToolCallingContext {
        LanguageModelSessionToolCallingContext(nonce: UUID().uuidString)
    }
}

// MARK: - LanguageModelSessionToolPromptBuilder

/// Builds tool-aware prompts for use with Foundation Models' prompt-based tool calling.
enum LanguageModelSessionToolPromptBuilder {
    /// Builds a prompt that includes tool definitions and format instructions.
    /// - Parameters:
    ///   - basePrompt: The original user prompt.
    ///   - tools: Available tool schemas to include in the prompt.
    ///   - context: Per-request envelope metadata used to authenticate tool-call responses.
    /// - Returns: The base prompt if no tools, or an enhanced prompt with tool definitions.
    static func buildToolPrompt(
        basePrompt: String,
        tools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext,
        structuredOutput: StructuredOutputRequest? = nil,
        maxToolDefTokens: Int = 200
    ) -> String {
        guard !tools.isEmpty else {
            if let structuredOutput {
                return StructuredOutputPromptBuilder.appendInstruction(to: basePrompt, request: structuredOutput)
            }
            return basePrompt
        }

        var toolDefinitions: [String] = []
        for tool in tools {
            let params: String = tool.parameters.map { (param: ToolParameter) -> String in
                let typeDesc = parameterTypeDescription(param.type)
                let required = param.isRequired ? " (required)" : ""
                return "  - \(param.name): \(typeDesc)\(required) - \(param.description)"
            }.joined(separator: "\n")

            let paramSection = params.isEmpty ? "  (no parameters)" : params

            let toolDef = """
                \(tool.name):
                  Description: \(tool.description)
                  Parameters:
                \(paramSection)
                """
            toolDefinitions.append(toolDef)
        }

        var toolDefsText = toolDefinitions.joined(separator: "\n\n")

        // Truncate tool definitions to fit within budget (Foundation Models 4096-token window).
        // Tool defs for WebSearchTool alone are ~800 tokens. Cap at 400 to leave room for
        // conversation history, system prompt, and tool results.
        let maxToolDefTokens = 400
        let estimatedToolTokens = toolDefsText.count / 4
        if estimatedToolTokens > maxToolDefTokens {
            let maxChars = maxToolDefTokens * 4
            if toolDefsText.count > maxChars {
                toolDefsText = String(toolDefsText.prefix(maxChars)) + "\n  ... (additional parameters omitted)"
            }
        }

        var prompt = """
            \(basePrompt)

            Available tools:
            \(toolDefsText)

            If you decide to use a tool, respond with only a single JSON object in this exact format and no surrounding text:
            \(toolEnvelopeExample(tools: tools, context: context))

            Never emit that JSON envelope unless you are requesting a tool call.
            Never copy placeholder names like "tool_name", "param1", or "value1".
            The "tool" field must be one of the real tool names listed above.
            If no tool is needed, respond normally without JSON.
            If tool results are already present in the prompt, use them directly to answer the user.
            Never claim you cannot browse, search, or access external information when a tool result is already present.
            Do not call the same tool again with weaker or emptier arguments after you already have a usable result.
            """

        if let structuredOutput {
            prompt = StructuredOutputPromptBuilder.appendInstruction(to: prompt, request: structuredOutput)
        }

        return prompt
    }

    /// Converts a ToolParameter type to a human-readable description.
    static func parameterTypeDescription(_ type: ToolParameter.ParameterType) -> String {
        switch type {
        case .string:
            return "string"
        case .int:
            return "integer"
        case .double:
            return "number"
        case .bool:
            return "boolean"
        case let .array(elementType):
            return "array of \(parameterTypeDescription(elementType))"
        case .object:
            return "object"
        case let .oneOf(options):
            return "one of: \(options.joined(separator: ", "))"
        case .any:
            return "any type"
        }
    }

    private static func toolEnvelopeExample(
        tools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext
    ) -> String {
        guard let tool = tools.first else {
            return #"{"swarm_tool_call":{"nonce":"\#(context.nonce)","tool":"tool_name","arguments":{"param1":"value1"}}}"#
        }

        let arguments = exampleArguments(for: tool)
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
              let argumentsJSON = String(data: data, encoding: .utf8)
        else {
            return #"{"swarm_tool_call":{"nonce":"\#(context.nonce)","tool":"\#(tool.name)","arguments":{}}}"#
        }

        return #"{"swarm_tool_call": {"nonce": "\#(context.nonce)", "tool": "\#(tool.name)", "arguments": \#(argumentsJSON)}}"#
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func exampleArguments(for tool: ToolSchema) -> [String: Any] {
        if tool.name == "websearch" {
            return [
                "detail": "compact",
                "maxResults": 3,
                "query": "latest official Foundation Models documentation",
            ]
        }

        var example: [String: Any] = [:]

        for parameter in tool.parameters {
            if !parameter.isRequired, !example.isEmpty {
                continue
            }

            switch parameter.type {
            case .string:
                example[parameter.name] = exampleStringValue(for: parameter.name)
            case .int:
                example[parameter.name] = 1
            case .double:
                example[parameter.name] = 1.0
            case .bool:
                example[parameter.name] = true
            case let .array(elementType):
                switch elementType {
                case .string:
                    example[parameter.name] = ["example"]
                case .int:
                    example[parameter.name] = [1]
                case .double:
                    example[parameter.name] = [1.0]
                case .bool:
                    example[parameter.name] = [true]
                default:
                    example[parameter.name] = []
                }
            case let .oneOf(options):
                if let first = options.first {
                    example[parameter.name] = first
                }
            case .object:
                example[parameter.name] = [:]
            case .any:
                example[parameter.name] = "example"
            }

            if parameter.isRequired, !example.isEmpty {
                break
            }
        }

        return example
    }

    private static func exampleStringValue(for parameterName: String) -> String {
        switch parameterName.lowercased() {
        case "query":
            return "example query"
        case "url":
            return "https://example.com"
        case "city":
            return "San Francisco"
        case "expression":
            return "2+2"
        default:
            return "example"
        }
    }
}

// MARK: - LanguageModelSessionToolParser

/// Parses tool calls from model response text for Foundation Models' prompt-based tool calling.
enum LanguageModelSessionToolParser {
    /// Parses tool calls from a model's text response.
    /// - Parameters:
    ///   - content: The model's response text.
    ///   - availableTools: The tools that were made available to the model.
    ///   - context: The request-scoped envelope context expected in a valid tool call.
    /// - Returns: Parsed tool calls if a valid tool call is found, nil otherwise.
    static func parseToolCalls(
        from content: String,
        availableTools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext
    ) -> [InferenceResponse.ParsedToolCall]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fast path for the intended exact-JSON response shape.
        if let toolCalls = parseToolCallsFromExactEnvelope(
            trimmed,
            availableTools: availableTools,
            context: context
        ) {
            return toolCalls
        }

        // Recover a single valid Swarm envelope from common wrappers such as prose or markdown fences.
        let candidates = extractJSONObjectCandidates(from: content)
        if !candidates.isEmpty {
            print("[FM ToolParser] extracted \(candidates.count) JSON candidates from response")
        }
        var parsedCandidates: [[InferenceResponse.ParsedToolCall]] = []

        for candidate in candidates {
            guard let toolCalls = parseToolCallsFromExactEnvelope(
                candidate,
                availableTools: availableTools,
                context: context
            ) else {
                let reason = debugParseFailure(candidate, availableTools: availableTools, context: context)
                print("[FM ToolParser] candidate rejected: \(reason)")
                continue
            }
            parsedCandidates.append(toolCalls)
            guard parsedCandidates.count < 2 else {
                return nil
            }
        }

        return parsedCandidates.first
    }

    /// Debug: traces why a candidate failed to parse as a valid tool call.
    private static func debugParseFailure(
        _ candidate: String,
        availableTools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext
    ) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first != "{" || trimmed.last != "}" {
            return "candidate doesn't start/end with braces: first=\(String(trimmed.prefix(1))), last=\(String(trimmed.suffix(1)))"
        }
        guard let data = trimmed.data(using: .utf8) else {
            return "failed to encode as UTF-8 data"
        }
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "failed to deserialize JSON"
        }
        guard let envelope = jsonObject[LanguageModelSessionToolCallingContext.envelopeKey] as? [String: Any] else {
            return "missing envelope key '\(LanguageModelSessionToolCallingContext.envelopeKey)'; keys=\(jsonObject.keys.joined(separator: ", "))"
        }
        if envelope["nonce"] == nil {
            return "missing nonce in envelope"
        }
        guard let nonce = envelope["nonce"] as? String else {
            return "invalid nonce in envelope"
        }
        if nonce != context.nonce {
            return "nonce mismatch: got='\(nonce.prefix(8))...', expected='\(context.nonce.prefix(8))...'"
        }
        let toolName = envelope["tool"] as? String ?? "(nil)"
        guard availableTools.contains(where: { $0.name == toolName }) else {
            return "tool '\(toolName)' not in available tools: \(availableTools.map(\.name).joined(separator: ", "))"
        }
        return "unknown failure"
    }

    /// Parses an exact JSON object string into Swarm tool calls when it matches the expected envelope.
    private static func parseToolCallsFromExactEnvelope(
        _ candidate: String,
        availableTools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext
    ) -> [InferenceResponse.ParsedToolCall]? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else {
            return nil
        }

        guard let data = trimmed.data(using: .utf8) else {
            return nil
        }

        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            guard let envelope = jsonObject[LanguageModelSessionToolCallingContext.envelopeKey] as? [String: Any] else {
                return nil
            }

            if let nonceValue = envelope["nonce"] {
                guard let nonce = nonceValue as? String, nonce == context.nonce else {
                    return nil
                }
            }

            let rawToolName = envelope["tool"] as? String
            guard let rawToolName = rawToolName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawToolName.isEmpty else {
                return nil
            }

            guard let tool = resolveTool(named: rawToolName, availableTools: availableTools) else {
                return nil
            }

            var arguments: [String: SendableValue] = [:]
            if let argsObject = envelope["arguments"] as? [String: Any] {
                for (key, value) in argsObject {
                    arguments[key] = SendableValue.fromJSONValue(value)
                }
            }
            arguments = sanitize(arguments: arguments, for: tool)

            let callId = envelope["id"] as? String

            return [InferenceResponse.ParsedToolCall(
                id: callId,
                name: tool.name,
                arguments: arguments
            )]
        } catch {
            return nil
        }
    }

    /// Extracts top-level JSON object substrings while respecting JSON string escaping.
    private static func extractJSONObjectCandidates(from content: String) -> [String] {
        var candidates: [String] = []
        var objectStart: String.Index?
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"":
                    inString = true
                case "{":
                    if depth == 0 {
                        objectStart = index
                    }
                    depth += 1
                case "}":
                    guard depth > 0 else {
                        break
                    }
                    depth -= 1
                    if depth == 0, let objectStart {
                        candidates.append(String(content[objectStart ... index]))
                    }
                default:
                    break
                }
            }

            index = content.index(after: index)
        }

        return candidates
    }

    private static func resolveTool(
        named rawToolName: String,
        availableTools: [ToolSchema]
    ) -> ToolSchema? {
        if let exact = availableTools.first(where: { $0.name == rawToolName }) {
            return exact
        }

        let prefixMatches = availableTools.filter {
            $0.name.hasPrefix(rawToolName) || rawToolName.hasPrefix($0.name)
        }
        if prefixMatches.count == 1 {
            return prefixMatches[0]
        }

        let normalizedRaw = normalizeToolName(rawToolName)
        let normalizedMatches = availableTools.filter { normalizeToolName($0.name) == normalizedRaw }
        if normalizedMatches.count == 1 {
            return normalizedMatches[0]
        }

        return nil
    }

    private static func normalizeToolName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func sanitize(
        arguments: [String: SendableValue],
        for tool: ToolSchema
    ) -> [String: SendableValue] {
        guard !tool.parameters.isEmpty else {
            return arguments
        }

        var sanitized: [String: SendableValue] = [:]
        sanitized.reserveCapacity(arguments.count)

        let parameterMap = Dictionary(uniqueKeysWithValues: tool.parameters.map { ($0.name, $0) })
        for (key, value) in arguments {
            guard let parameter = parameterMap[key] else {
                continue
            }
            if let normalized = normalize(value: value, for: parameter.type) {
                sanitized[key] = normalized
            }
        }

        return sanitized
    }

    private static func normalize(
        value: SendableValue,
        for type: ToolParameter.ParameterType
    ) -> SendableValue? {
        switch type {
        case .string:
            return switch value {
            case let .string(text): .string(text)
            case let .int(number): .string(String(number))
            case let .double(number): .string(String(number))
            case let .bool(flag): .string(flag ? "true" : "false")
            default: nil
            }
        case .int:
            return switch value {
            case let .int(number): .int(number)
            case let .double(number): .int(Int(number))
            case let .string(text):
                if let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    .int(number)
                } else {
                    nil
                }
            case let .bool(flag): .int(flag ? 1 : 0)
            default: nil
            }
        case .double:
            return switch value {
            case let .double(number): .double(number)
            case let .int(number): .double(Double(number))
            case let .string(text):
                if let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    .double(number)
                } else {
                    nil
                }
            default: nil
            }
        case .bool:
            switch value {
            case let .bool(flag):
                return .bool(flag)
            case let .string(text):
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "1"].contains(normalized) {
                    return .bool(true)
                }
                if ["false", "no", "0"].contains(normalized) {
                    return .bool(false)
                }
                return nil
            case let .int(number):
                return .bool(number != 0)
            default:
                return nil
            }
        case let .array(elementType):
            guard case let .array(values) = value else {
                return nil
            }
            let normalized = values.compactMap { normalize(value: $0, for: elementType) }
            return normalized.count == values.count ? .array(normalized) : nil
        case .object:
            if case .dictionary = value {
                return value
            }
            return nil
        case let .oneOf(options):
            guard let string = normalize(value: value, for: .string)?.stringValue else {
                return nil
            }
            return options.contains(string) ? .string(string) : nil
        case .any:
            return value
        }
    }
}

// MARK: - LanguageModelSessionToolCallingEmulation

/// Coordinates prompt-based tool calling for Foundation Models.
enum LanguageModelSessionToolCallingEmulation {
    /// Generates a tool-aware response using a text-generation closure.
    static func generateResponse(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions,
        generateText: @Sendable (String, InferenceOptions) async throws -> String
    ) async throws -> InferenceResponse {
        let context = LanguageModelSessionToolCallingContext.make()
        let promptToGenerate = LanguageModelSessionToolPromptBuilder.buildToolPrompt(
            basePrompt: prompt,
            tools: tools,
            context: context,
            structuredOutput: options.structuredOutput
        )

        let generatedText = try await generateText(promptToGenerate, options)
        return makeInferenceResponse(from: generatedText, availableTools: tools, context: context)
    }

    /// Maps generated text into Swarm's structured inference response shape.
    static func makeInferenceResponse(
        from generatedText: String,
        availableTools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext
    ) -> InferenceResponse {
        guard !availableTools.isEmpty else {
            return InferenceResponse(
                content: generatedText,
                toolCalls: [],
                finishReason: .completed
            )
        }

        if let parsedToolCalls = LanguageModelSessionToolParser.parseToolCalls(
            from: generatedText,
            availableTools: availableTools,
            context: context
        ), !parsedToolCalls.isEmpty {
            return InferenceResponse(
                content: nil,
                toolCalls: parsedToolCalls,
                finishReason: .toolCall
            )
        }

        return InferenceResponse(
            content: generatedText,
            toolCalls: [],
            finishReason: .completed
        )
    }
}
