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
        maxToolDefTokens _: Int = 200
    ) -> String {
        guard !tools.isEmpty else {
            if let structuredOutput {
                return StructuredOutputPromptBuilder.appendInstruction(to: basePrompt, request: structuredOutput)
            }
            return basePrompt
        }

        return """
            \(basePrompt)

            \(toolCallingInstructions(
                tools: tools,
                context: context,
                structuredOutput: structuredOutput
            ))
            """
    }

    static func toolCallingInstructions(
        tools: [ToolSchema],
        context: LanguageModelSessionToolCallingContext,
        structuredOutput: StructuredOutputRequest? = nil
    ) -> String {
        toolCallingInstructions(
            toolDefsText: formattedToolDefinitions(tools),
            context: context,
            structuredOutput: structuredOutput
        )
    }

    private static func formattedToolDefinitions(_ tools: [ToolSchema]) -> String {
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

        let maxToolDefTokens = 400
        let estimatedToolTokens = toolDefsText.count / 4
        if estimatedToolTokens > maxToolDefTokens {
            let maxChars = maxToolDefTokens * 4
            if toolDefsText.count > maxChars {
                toolDefsText = String(toolDefsText.prefix(maxChars)) + "\n  ... (additional parameters omitted)"
            }
        }

        return toolDefsText
    }

    private static func toolCallingInstructions(
        toolDefsText: String,
        context: LanguageModelSessionToolCallingContext,
        structuredOutput: StructuredOutputRequest?
    ) -> String {
        var prompt = """
            Available tools:
            \(toolDefsText)

            If you decide to use a tool, respond with only a single JSON object in this exact format and no surrounding text:
            {"\(LanguageModelSessionToolCallingContext.envelopeKey)": {"nonce": "\(context.nonce)", "tool": "tool_name", "arguments": {"param1": "value1"}}}

            Never emit that JSON envelope unless you are requesting a tool call.
            If no tool is needed, respond normally without JSON.
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
        var parsedCandidates: [[InferenceResponse.ParsedToolCall]] = []

        for candidate in candidates {
            guard let toolCalls = parseToolCallsFromExactEnvelope(
                candidate,
                availableTools: availableTools,
                context: context
            ) else {
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
        guard let nonce = envelope["nonce"] as? String else {
            return "missing nonce in envelope"
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

            guard let nonce = envelope["nonce"] as? String, nonce == context.nonce else {
                return nil
            }

            let toolName = envelope["tool"] as? String
            guard let toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }

            guard availableTools.contains(where: { $0.name == toolName }) else {
                return nil
            }

            var arguments: [String: SendableValue] = [:]
            if let argsObject = envelope["arguments"] as? [String: Any] {
                for (key, value) in argsObject {
                    arguments[key] = SendableValue.fromJSONValue(value)
                }
            }

            let callId = envelope["id"] as? String

            return [InferenceResponse.ParsedToolCall(
                id: callId,
                name: toolName,
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

    /// Generates a tool-aware response without flattening role-tagged history.
    static func generateResponse(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        generateText: @Sendable ([InferenceMessage], InferenceOptions) async throws -> String
    ) async throws -> InferenceResponse {
        let context = LanguageModelSessionToolCallingContext.make()
        var outgoing = messages
        if tools.isEmpty {
            if let structuredOutput = options.structuredOutput {
                outgoing = StructuredOutputPromptBuilder.appendInstruction(
                    to: outgoing,
                    request: structuredOutput
                )
            }
        } else {
            outgoing.append(.system(
                LanguageModelSessionToolPromptBuilder.toolCallingInstructions(
                    tools: tools,
                    context: context,
                    structuredOutput: options.structuredOutput
                )
            ))
        }

        let generatedText = try await generateText(outgoing, options)
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
