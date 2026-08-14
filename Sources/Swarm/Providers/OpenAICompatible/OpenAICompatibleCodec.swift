// OpenAICompatibleCodec.swift
// Swarm Framework
//
// InferenceMessage / ToolSchema ↔ OpenAI chat-completions JSON.

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum OpenAICompatibleCodec: Sendable {
    static func chatCompletionsURL(for configuration: OpenAICompatibleProviderConfiguration) throws -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        guard var components else {
            throw AgentError.invalidInput(reason: "OpenAI-compatible baseURL is not a valid URL")
        }

        let path = components.path
        if !path.hasSuffix("/chat/completions") && !path.hasSuffix("/chat/completions/") {
            if path.hasSuffix("/") {
                components.path = path + "chat/completions"
            } else if path.isEmpty {
                components.path = "/chat/completions"
            } else {
                components.path = path + "/chat/completions"
            }
        }

        var items = components.queryItems ?? []
        for (name, value) in configuration.queryItems.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let url = components.url else {
            throw AgentError.invalidInput(reason: "OpenAI-compatible endpoint could not be constructed")
        }
        return url
    }

    static func makeRequest(
        configuration: OpenAICompatibleProviderConfiguration,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        stream: Bool,
        structuredOutput: StructuredOutputRequest?
    ) throws -> URLRequest {
        let url = try chatCompletionsURL(for: configuration)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")

        for (name, value) in configuration.httpHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let hasAuthHeader = configuration.httpHeaders.keys.contains { key in
            key.caseInsensitiveCompare("Authorization") == .orderedSame
                || key.caseInsensitiveCompare("api-key") == .orderedSame
        }
        if !hasAuthHeader, let apiKey = configuration.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        TraceContextHeaders.applyCurrent(to: &request)

        let body = try requestBody(
            configuration: configuration,
            messages: messages,
            tools: tools,
            options: options,
            stream: stream,
            structuredOutput: structuredOutput
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static func requestBody(
        configuration: OpenAICompatibleProviderConfiguration,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        stream: Bool,
        structuredOutput: StructuredOutputRequest?
    ) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages.map(encodeMessage),
            "temperature": options.temperature,
        ]

        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if !options.stopSequences.isEmpty {
            body["stop"] = options.stopSequences
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }
        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = presencePenalty
        }
        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = frequencyPenalty
        }
        if let seed = options.seed {
            body["seed"] = seed
        }
        if let parallel = options.parallelToolCalls {
            body["parallel_tool_calls"] = parallel
        }
        if !tools.isEmpty {
            body["tools"] = tools.map(encodeTool)
            if let toolChoice = options.toolChoice {
                body["tool_choice"] = encodeToolChoice(toolChoice)
            }
        }
        if stream {
            body["stream"] = true
            body["stream_options"] = ["include_usage": true]
        }
        if let structuredOutput,
           configuration.structuredOutputMode == .nativeJSONSchema
        {
            body["response_format"] = try encodeResponseFormat(structuredOutput)
        }

        return body
    }

    static func encodeMessage(_ message: InferenceMessage) -> [String: Any] {
        var object: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content,
        ]
        if let name = message.name, message.role != .tool {
            object["name"] = name
        }
        if message.role == .tool {
            object["tool_call_id"] = message.toolCallID ?? message.name ?? "tool_call"
        }
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = message.toolCalls.enumerated().map { index, call in
                encodeToolCall(call, index: index)
            }
        }
        return object
    }

    static func encodeTool(_ schema: ToolSchema) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": schema.name,
                "description": schema.description,
                "parameters": parametersSchema(for: schema),
            ] as [String: Any],
        ]
    }

    static func encodeToolChoice(_ choice: ToolChoice) -> Any {
        switch choice {
        case .auto:
            return "auto"
        case .none:
            return "none"
        case .required:
            return "required"
        case let .specific(toolName):
            return [
                "type": "function",
                "function": ["name": toolName],
            ] as [String: Any]
        }
    }

    static func encodeResponseFormat(_ request: StructuredOutputRequest) throws -> [String: Any] {
        switch request.format {
        case .jsonObject:
            return ["type": "json_object"]
        case let .jsonSchema(name, schemaJSON):
            guard let data = schemaJSON.data(using: .utf8),
                  let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw AgentError.invalidInput(
                    reason: "Structured output JSON schema is not a JSON object"
                )
            }
            return [
                "type": "json_schema",
                "json_schema": [
                    "name": sanitizeSchemaName(name),
                    "schema": schema,
                    "strict": true,
                ] as [String: Any],
            ]
        }
    }

    static func inferenceResponse(from chunk: OpenAICompatibleChatChunk) throws -> InferenceResponse {
        let choice = chunk.choices.first
        let message = choice?.message ?? choice?.delta
        let toolCalls = (message?.toolCalls ?? []).map(parsedToolCall)
        let finishReason = finishReason(from: choice?.finishReason, hasToolCalls: !toolCalls.isEmpty)

        if finishReason == .contentFilter {
            throw AgentError.contentFiltered(
                reason: message?.content ?? "OpenAI-compatible content filter"
            )
        }

        let content = message?.content.flatMap { $0.isEmpty ? nil : $0 }
        return InferenceResponse(
            content: content,
            toolCalls: toolCalls,
            finishReason: finishReason,
            usage: chunk.usage
        )
    }

    static func parsedToolCall(_ delta: OpenAICompatibleChatChunk.ToolCallDelta) -> InferenceResponse.ParsedToolCall {
        InferenceResponse.ParsedToolCall(
            id: delta.id,
            name: delta.name ?? "",
            arguments: decodeArguments(delta.arguments)
        )
    }

    static func decodeArguments(_ json: String) -> [String: SendableValue] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return [:]
        }
        if case let .dictionary(dictionary) = SendableValue.fromJSONValue(object) {
            return dictionary
        }
        return [:]
    }

    static func finishReason(from raw: String?, hasToolCalls: Bool) -> InferenceResponse.FinishReason {
        switch raw {
        case "tool_calls", "function_call":
            return .toolCall
        case "length":
            return .maxTokens
        case "content_filter":
            return .contentFilter
        case "cancelled", "cancelled_by_user":
            return .cancelled
        default:
            return hasToolCalls ? .toolCall : .completed
        }
    }

    static func parametersSchema(for schema: ToolSchema) -> [String: Any] {
        parametersSchema(name: schema.name, parameters: schema.parameters)
    }

    private static func parametersSchema(name: String, parameters: [ToolParameter]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for parameter in parameters {
            var schema = jsonSchema(for: parameter.type)
            schema["description"] = parameter.description
            if let defaultValue = parameter.defaultValue {
                schema["default"] = defaultValue.toJSONObject()
            }
            properties[parameter.name] = schema
            if parameter.isRequired, parameter.defaultValue == nil {
                required.append(parameter.name)
            }
        }

        required.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

        var root: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            root["required"] = required
        }
        if properties.isEmpty {
            root["description"] = "Tool parameters for \(name)"
        }
        return root
    }

    private static func jsonSchema(for type: ToolParameter.ParameterType) -> [String: Any] {
        switch type {
        case .string:
            return ["type": "string"]
        case .int:
            return ["type": "integer"]
        case .double:
            return ["type": "number"]
        case .bool:
            return ["type": "boolean"]
        case let .array(elementType):
            return [
                "type": "array",
                "items": jsonSchema(for: elementType),
            ]
        case let .object(properties):
            return parametersSchema(name: "object", parameters: properties)
        case let .oneOf(options):
            return [
                "type": "string",
                "enum": options,
            ]
        case .any:
            return [:]
        }
    }

    private static func encodeToolCall(_ call: InferenceMessage.ToolCall, index: Int) -> [String: Any] {
        let argumentsObject = SendableValue.dictionary(call.arguments).toJSONObject()
        let argumentsData = (try? JSONSerialization.data(withJSONObject: argumentsObject, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        let arguments = String(data: argumentsData, encoding: .utf8) ?? "{}"
        return [
            "id": call.id ?? "call_\(index)",
            "type": "function",
            "function": [
                "name": call.name,
                "arguments": arguments,
            ] as [String: Any],
        ]
    }

    private static func sanitizeSchemaName(_ name: String) -> String {
        let filtered = name.map { character -> Character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
                ? character
                : "_"
        }
        let sanitized = String(filtered)
        return sanitized.isEmpty ? "response" : sanitized
    }
}

/// Accumulates streamed tool-call deltas into ``InferenceStreamUpdate`` values.
struct OpenAICompatibleStreamAccumulator: Sendable {
    private var toolCalls: [Int: AccumulatedToolCall] = [:]
    private var emittedCompleted = false

    mutating func consume(_ chunk: OpenAICompatibleChatChunk) -> [InferenceStreamUpdate] {
        var updates: [InferenceStreamUpdate] = []

        for choice in chunk.choices {
            if let content = choice.delta?.content, !content.isEmpty {
                updates.append(.outputChunk(content))
            }
            for delta in choice.delta?.toolCalls ?? [] {
                var accumulated = toolCalls[delta.index] ?? AccumulatedToolCall(index: delta.index)
                if let id = delta.id, !id.isEmpty {
                    accumulated.id = id
                }
                if let name = delta.name, !name.isEmpty {
                    accumulated.name = name
                }
                accumulated.arguments += delta.arguments
                toolCalls[delta.index] = accumulated
                updates.append(
                    .toolCallPartial(
                        PartialToolCallUpdate(
                            providerCallId: accumulated.id,
                            toolName: accumulated.name,
                            index: accumulated.index,
                            argumentsFragment: accumulated.arguments
                        )
                    )
                )
            }
            if let finish = choice.finishReason,
               finish == "tool_calls" || finish == "function_call"
            {
                updates.append(contentsOf: completeToolCalls())
            }
        }

        if let usage = chunk.usage {
            updates.append(.usage(usage))
        }

        return updates
    }

    mutating func finish() -> [InferenceStreamUpdate] {
        completeToolCalls()
    }

    private mutating func completeToolCalls() -> [InferenceStreamUpdate] {
        guard !emittedCompleted, !toolCalls.isEmpty else {
            return []
        }
        emittedCompleted = true
        let parsed = toolCalls.keys.sorted().compactMap { index -> InferenceResponse.ParsedToolCall? in
            guard let call = toolCalls[index] else { return nil }
            return InferenceResponse.ParsedToolCall(
                id: call.id.isEmpty ? nil : call.id,
                name: call.name,
                arguments: OpenAICompatibleCodec.decodeArguments(call.arguments)
            )
        }
        return parsed.isEmpty ? [] : [.toolCallsCompleted(parsed)]
    }
}

private struct AccumulatedToolCall: Sendable {
    var index: Int
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}
