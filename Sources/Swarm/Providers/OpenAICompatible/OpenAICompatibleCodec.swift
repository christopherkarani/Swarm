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
        request.httpBody = try OpenAICompatibleWire.encode(body)
        return request
    }

    static func requestBody(
        configuration: OpenAICompatibleProviderConfiguration,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        stream: Bool,
        structuredOutput: StructuredOutputRequest?
    ) throws -> OpenAICompatibleWire.Request {
        OpenAICompatibleWire.Request(
            model: configuration.model,
            messages: encodeMessages(messages),
            temperature: options.temperature,
            maxTokens: options.maxTokens,
            stop: options.stopSequences.isEmpty ? nil : options.stopSequences,
            topP: options.topP,
            presencePenalty: options.presencePenalty,
            frequencyPenalty: options.frequencyPenalty,
            seed: options.seed,
            parallelToolCalls: options.parallelToolCalls,
            tools: tools.isEmpty ? nil : tools.map(encodeTool),
            toolChoice: tools.isEmpty ? nil : options.toolChoice.map(encodeToolChoice),
            stream: stream ? true : nil,
            streamOptions: stream ? OpenAICompatibleWire.StreamOptions(includeUsage: true) : nil,
            responseFormat: try responseFormatWire(
                configuration: configuration,
                tools: tools,
                structuredOutput: structuredOutput
            )
        )
    }

    private static func responseFormatWire(
        configuration: OpenAICompatibleProviderConfiguration,
        tools: [ToolSchema],
        structuredOutput: StructuredOutputRequest?
    ) throws -> OpenAICompatibleWire.ResponseFormat? {
        // Many OpenAI-compatible hosts reject `tools` + `response_format` on
        // the same call. Native structured output is only advertised when this
        // request is not also a tool-calling turn.
        guard let structuredOutput,
              configuration.structuredOutputMode == .nativeJSONSchema,
              tools.isEmpty
        else {
            return nil
        }
        return try encodeResponseFormat(structuredOutput)
    }

    static func encodeMessages(_ messages: [InferenceMessage]) -> [OpenAICompatibleWire.RequestMessage] {
        var pendingCallIDs: [String] = []
        var pendingCallNames: [String] = []
        var nextUnused = 0

        return messages.map { message in
            if message.role == .assistant, !message.toolCalls.isEmpty {
                pendingCallIDs = message.toolCalls.enumerated().map { index, call in
                    synthesizedToolCallID(call.id, index: index)
                }
                pendingCallNames = message.toolCalls.map(\.name)
                nextUnused = 0
            }

            let toolCallID: String?
            if message.role == .tool {
                toolCallID = resolvedToolCallID(
                    for: message,
                    pendingIDs: pendingCallIDs,
                    pendingNames: pendingCallNames,
                    nextUnused: &nextUnused
                )
            } else {
                toolCallID = message.toolCallID
            }

            return encodeMessage(message, toolCallID: toolCallID)
        }
    }

    static func encodeMessage(
        _ message: InferenceMessage,
        toolCallID: String? = nil
    ) -> OpenAICompatibleWire.RequestMessage {
        var name: String?
        if let messageName = message.name, message.role != .tool {
            name = messageName
        }
        var resolvedID: String?
        if message.role == .tool, let toolCallID, !toolCallID.isEmpty {
            resolvedID = toolCallID
        }
        return OpenAICompatibleWire.RequestMessage(
            role: message.role.rawValue,
            content: message.content,
            name: name,
            toolCallID: resolvedID,
            toolCalls: message.toolCalls.isEmpty ? nil : message.toolCalls.enumerated().map { index, call in
                encodeToolCall(call, index: index)
            }
        )
    }

    static func encodeTool(_ schema: ToolSchema) -> OpenAICompatibleWire.RequestTool {
        OpenAICompatibleWire.RequestTool(
            function: OpenAICompatibleWire.RequestToolFunction(
                name: schema.name,
                description: schema.description,
                parameters: parametersSchema(for: schema)
            )
        )
    }

    static func encodeToolChoice(_ choice: ToolChoice) -> OpenAICompatibleWire.RequestToolChoice {
        switch choice {
        case .auto:
            return .auto
        case .none:
            return .none
        case .required:
            return .required
        case let .specific(toolName):
            return .specific(toolName: toolName)
        }
    }

    static func encodeResponseFormat(
        _ request: StructuredOutputRequest
    ) throws -> OpenAICompatibleWire.ResponseFormat {
        switch request.format {
        case .jsonObject:
            return .jsonObject
        case let .jsonSchema(name, schemaJSON):
            guard let data = schemaJSON.data(using: .utf8),
                  let schema = try? JSONDecoder().decode(SendableValue.self, from: data),
                  case .dictionary = schema
            else {
                throw AgentError.invalidInput(
                    reason: "Structured output JSON schema is not a JSON object"
                )
            }
            return .jsonSchema(name: sanitizeSchemaName(name), schema: schema)
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
            arguments: decodeArguments(delta.arguments),
            thoughtSignature: delta.thoughtSignature
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

    static func parametersSchema(for schema: ToolSchema) -> SendableValue {
        parametersSchemaValue(name: schema.name, parameters: schema.parameters)
    }

    private static func parametersSchemaValue(name: String, parameters: [ToolParameter]) -> SendableValue {
        var properties: [String: SendableValue] = [:]
        var required: [String] = []

        for parameter in parameters {
            var node = jsonSchemaValue(for: parameter.type).dictionaryValue ?? [:]
            node["description"] = .string(parameter.description)
            if let defaultValue = parameter.defaultValue {
                node["default"] = defaultValue
            }
            properties[parameter.name] = .dictionary(node)
            if parameter.isRequired, parameter.defaultValue == nil {
                required.append(parameter.name)
            }
        }

        required.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

        var root: [String: SendableValue] = [
            "type": .string("object"),
            "properties": .dictionary(properties),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty {
            root["required"] = .array(required.map(SendableValue.string))
        }
        if properties.isEmpty {
            root["description"] = .string("Tool parameters for \(name)")
        }
        return .dictionary(root)
    }

    private static func jsonSchemaValue(for type: ToolParameter.ParameterType) -> SendableValue {
        switch type {
        case .string:
            return .dictionary(["type": .string("string")])
        case .int:
            return .dictionary(["type": .string("integer")])
        case .double:
            return .dictionary(["type": .string("number")])
        case .bool:
            return .dictionary(["type": .string("boolean")])
        case let .array(elementType):
            return .dictionary([
                "type": .string("array"),
                "items": jsonSchemaValue(for: elementType),
            ])
        case let .object(properties):
            return parametersSchemaValue(name: "object", parameters: properties)
        case let .oneOf(options):
            return .dictionary([
                "type": .string("string"),
                "enum": .array(options.map(SendableValue.string)),
            ])
        case .any:
            return .dictionary([:])
        }
    }

    static func synthesizedToolCallID(_ id: String?, index: Int) -> String {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "call_\(index)" : trimmed
    }

    private static func resolvedToolCallID(
        for message: InferenceMessage,
        pendingIDs: [String],
        pendingNames: [String],
        nextUnused: inout Int
    ) -> String? {
        if let explicit = message.toolCallID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return explicit
        }

        if let name = message.name,
           let match = pendingNames.enumerated().first(where: { index, callName in
               index >= nextUnused && callName == name
           })
        {
            nextUnused = match.offset + 1
            return pendingIDs[match.offset]
        }

        if nextUnused < pendingIDs.count {
            let id = pendingIDs[nextUnused]
            nextUnused += 1
            return id
        }

        return nil
    }

    private static func encodeToolCall(
        _ call: InferenceMessage.ToolCall,
        index: Int
    ) -> OpenAICompatibleWire.RequestToolCall {
        // The arguments leaf stays on its historical serialization so echoed
        // tool calls keep byte-identical argument strings; dynamic
        // model-generated content is outside the typed wire boundary.
        let argumentsObject = SendableValue.dictionary(call.arguments).toJSONObject()
        let argumentsData = (try? JSONSerialization.data(withJSONObject: argumentsObject, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        let arguments = String(data: argumentsData, encoding: .utf8) ?? "{}"
        var extra: OpenAICompatibleWire.ThoughtSignatureExtra?
        // Gemini thinking models reject follow-ups without the echoed signature.
        if let signature = call.thoughtSignature, !signature.isEmpty {
            extra = OpenAICompatibleWire.ThoughtSignatureExtra(
                google: OpenAICompatibleWire.ThoughtSignatureGoogle(thoughtSignature: signature)
            )
        }
        return OpenAICompatibleWire.RequestToolCall(
            id: synthesizedToolCallID(call.id, index: index),
            function: OpenAICompatibleWire.RequestToolCallFunction(
                name: call.name,
                arguments: arguments
            ),
            extraContent: extra
        )
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
                if let signature = delta.thoughtSignature, !signature.isEmpty {
                    accumulated.thoughtSignature = signature
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
            // Defer `.toolCallsCompleted` until `finish()` so a later usage
            // chunk is still consumed. ``Agent`` stops the stream on completed
            // calls.
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
                arguments: OpenAICompatibleCodec.decodeArguments(call.arguments),
                thoughtSignature: call.thoughtSignature.isEmpty ? nil : call.thoughtSignature
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
    var thoughtSignature: String = ""
}
