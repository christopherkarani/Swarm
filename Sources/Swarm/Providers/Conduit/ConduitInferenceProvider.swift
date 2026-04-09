import ConduitAdvanced
private typealias ConduitToolChoice = ConduitAdvanced.ToolChoice
import Foundation

/// Bridges a Conduit TextGenerator into Swarm' InferenceProvider.
///
/// This adapter keeps tool execution in Swarm by returning tool calls
/// upstream, avoiding Conduit's internal ToolExecutor.
struct ConduitInferenceProvider<Provider: TextGenerator>: InferenceProvider,
    ToolCallStreamingInferenceProvider,
    CapabilityReportingInferenceProvider,
    ConversationInferenceProvider,
    StructuredOutputInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider
{
    init(
        provider: Provider,
        model: Provider.ModelID,
        baseConfig: GenerateConfig = .default,
        supportsStreamingToolCalls: Bool = true
    ) {
        self.provider = provider
        self.model = model
        self.baseConfig = baseConfig
        self.supportsStreamingToolCalls = supportsStreamingToolCalls
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        let config = try apply(options: options, to: baseConfig)
        return try await provider.generate(prompt, model: model, config: config)
    }

    var capabilities: InferenceProviderCapabilities {
        var capabilities: InferenceProviderCapabilities = [
            .conversationMessages,
            .nativeToolCalling,
            .structuredOutputs,
        ]
        if supportsStreamingToolCalls {
            capabilities.insert(.streamingToolCalls)
        }
        return capabilities
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let config: GenerateConfig
        do {
            config = try apply(options: options, to: baseConfig)
        } catch {
            return StreamHelper.makeTrackedStream { continuation in
                continuation.finish(throwing: error)
            }
        }
        return provider.stream(prompt, model: model, config: config)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        let config = try apply(options: options, to: baseConfig)
        let conduitMessages = try Self.conduitMessages(from: messages)
        let result = try await provider.generate(messages: conduitMessages, model: model, config: config)
        return result.text
    }

    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        var structuredOptions = options
        structuredOptions.structuredOutput = request
        let config = try apply(options: structuredOptions, to: baseConfig)
        let text = try await provider.generate(prompt, model: model, config: config)
        return try StructuredOutputParser.parse(text, request: request, source: .providerNative)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        var structuredOptions = options
        structuredOptions.structuredOutput = request
        let config = try apply(options: structuredOptions, to: baseConfig)
        let conduitMessages = try Self.conduitMessages(from: messages)
        let result = try await provider.generate(messages: conduitMessages, model: model, config: config)
        return try StructuredOutputParser.parse(result.text, request: request, source: .providerNative)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        var config = try apply(options: options, to: baseConfig)
        let toolDefinitions = try ConduitToolSchemaConverter.toolDefinitions(from: tools)
        config = config.tools(toolDefinitions)

        if !tools.isEmpty, let toolChoice = options.toolChoice {
            let conduitToolChoice: ConduitToolChoice = switch toolChoice {
                case .auto:
                    ConduitToolChoice.auto
                case .none:
                    ConduitToolChoice.none
                case .required:
                    ConduitToolChoice.required
                case .specific(let toolName):
                    ConduitToolChoice.named(toolName)
                }
            config = config.toolChoice(conduitToolChoice)
        }

        let result = try await provider.generate(
            messages: [Message.user(prompt)],
            model: model,
            config: config
        )

        let parsedToolCalls = try parsedToolCalls(from: result, tools: tools)
        let finishReason = mapFinishReason(result.finishReason, toolCalls: parsedToolCalls)
        let usage = result.usage.map { usage in
            TokenUsage(
                inputTokens: usage.promptTokens,
                outputTokens: usage.completionTokens
            )
        }

        return InferenceResponse(
            content: result.text.isEmpty ? nil : result.text,
            toolCalls: parsedToolCalls,
            finishReason: finishReason,
            usage: usage
        )
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        var config = try apply(options: options, to: baseConfig)
        let toolDefinitions = try ConduitToolSchemaConverter.toolDefinitions(from: tools)
        config = config.tools(toolDefinitions)

        if !tools.isEmpty, let toolChoice = options.toolChoice {
            let conduitToolChoice: ConduitToolChoice = switch toolChoice {
                case .auto:
                    ConduitToolChoice.auto
                case .none:
                    ConduitToolChoice.none
                case .required:
                    ConduitToolChoice.required
                case .specific(let toolName):
                    ConduitToolChoice.named(toolName)
                }
            config = config.toolChoice(conduitToolChoice)
        }

        let conduitMessages = try Self.conduitMessages(from: messages)
        let result = try await provider.generate(
            messages: conduitMessages,
            model: model,
            config: config
        )

        let parsedToolCalls = try parsedToolCalls(from: result, tools: tools)
        let finishReason = mapFinishReason(result.finishReason, toolCalls: parsedToolCalls)
        let usage = result.usage.map { usage in
            TokenUsage(
                inputTokens: usage.promptTokens,
                outputTokens: usage.completionTokens
            )
        }

        return InferenceResponse(
            content: result.text.isEmpty ? nil : result.text,
            toolCalls: parsedToolCalls,
            finishReason: finishReason,
            usage: usage
        )
    }

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        guard supportsStreamingToolCalls else {
            return StreamHelper.makeTrackedStream { continuation in
                let response = try await self.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
                if let content = response.content, !content.isEmpty {
                    continuation.yield(.outputChunk(content))
                }
                if !response.toolCalls.isEmpty {
                    continuation.yield(.toolCallsCompleted(response.toolCalls))
                }
                if let usage = response.usage {
                    continuation.yield(.usage(usage))
                }
                continuation.finish()
            }
        }
        return StreamHelper.makeTrackedStream { continuation in
            var config = try apply(options: options, to: baseConfig)
            let toolDefinitions = try ConduitToolSchemaConverter.toolDefinitions(from: tools)
            config = config.tools(toolDefinitions)

            if !tools.isEmpty, let toolChoice = options.toolChoice {
                let conduitToolChoice: ConduitToolChoice = switch toolChoice {
                    case .auto:
                        ConduitToolChoice.auto
                    case .none:
                        ConduitToolChoice.none
                    case .required:
                        ConduitToolChoice.required
                    case .specific(let toolName):
                        ConduitToolChoice.named(toolName)
                    }
                config = config.toolChoice(conduitToolChoice)
            }

            var lastFragmentByCallId: [String: String] = [:]

            let chunkStream = provider.streamWithMetadata(
                messages: [Message.user(prompt)],
                model: model,
                config: config
            )

            for try await chunk in chunkStream {
                if !chunk.text.isEmpty {
                    continuation.yield(.outputChunk(chunk.text))
                }

                if let partial = chunk.partialToolCall {
                    // Avoid emitting duplicate fragments if the provider repeats the same buffer.
                    if lastFragmentByCallId[partial.id] != partial.argumentsFragment {
                        lastFragmentByCallId[partial.id] = partial.argumentsFragment
                        continuation.yield(.toolCallPartial(
                            PartialToolCallUpdate(
                                providerCallId: partial.id,
                                toolName: partial.toolName,
                                index: partial.index,
                                argumentsFragment: partial.argumentsFragment
                            )
                        ))
                    }
                }

                if let usage = chunk.usage {
                    continuation.yield(.usage(
                        TokenUsage(
                            inputTokens: usage.promptTokens,
                            outputTokens: usage.completionTokens
                        )
                    ))
                }

                if let completed = chunk.completedToolCalls, !completed.isEmpty {
                    let parsedToolCalls = try ConduitToolCallConverter.toParsedToolCalls(completed)
                    continuation.yield(.toolCallsCompleted(parsedToolCalls))
                }
            }

            continuation.finish()
        }
    }

    func stream(
        messages: [InferenceMessage],
        options: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let config = try apply(options: options, to: baseConfig)
            let conduitMessages = try Self.conduitMessages(from: messages)
            let stream = provider.streamWithMetadata(messages: conduitMessages, model: model, config: config)

            for try await chunk in stream {
                if !chunk.text.isEmpty {
                    continuation.yield(chunk.text)
                }
            }

            continuation.finish()
        }
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        guard supportsStreamingToolCalls else {
            return StreamHelper.makeTrackedStream { continuation in
                let response = try await self.generateWithToolCalls(
                    messages: messages,
                    tools: tools,
                    options: options
                )
                if let content = response.content, !content.isEmpty {
                    continuation.yield(.outputChunk(content))
                }
                if !response.toolCalls.isEmpty {
                    continuation.yield(.toolCallsCompleted(response.toolCalls))
                }
                if let usage = response.usage {
                    continuation.yield(.usage(usage))
                }
                continuation.finish()
            }
        }
        return StreamHelper.makeTrackedStream { continuation in
            var config = try apply(options: options, to: baseConfig)
            let toolDefinitions = try ConduitToolSchemaConverter.toolDefinitions(from: tools)
            config = config.tools(toolDefinitions)

            if !tools.isEmpty, let toolChoice = options.toolChoice {
                let conduitToolChoice: ConduitToolChoice = switch toolChoice {
                    case .auto:
                        ConduitToolChoice.auto
                    case .none:
                        ConduitToolChoice.none
                    case .required:
                        ConduitToolChoice.required
                    case .specific(let toolName):
                        ConduitToolChoice.named(toolName)
                    }
                config = config.toolChoice(conduitToolChoice)
            }

            var lastFragmentByCallId: [String: String] = [:]
            let conduitMessages = try Self.conduitMessages(from: messages)
            let chunkStream = provider.streamWithMetadata(
                messages: conduitMessages,
                model: model,
                config: config
            )

            for try await chunk in chunkStream {
                if !chunk.text.isEmpty {
                    continuation.yield(.outputChunk(chunk.text))
                }

                if let partial = chunk.partialToolCall {
                    if lastFragmentByCallId[partial.id] != partial.argumentsFragment {
                        lastFragmentByCallId[partial.id] = partial.argumentsFragment
                        continuation.yield(.toolCallPartial(
                            PartialToolCallUpdate(
                                providerCallId: partial.id,
                                toolName: partial.toolName,
                                index: partial.index,
                                argumentsFragment: partial.argumentsFragment
                            )
                        ))
                    }
                }

                if let usage = chunk.usage {
                    continuation.yield(.usage(
                        TokenUsage(
                            inputTokens: usage.promptTokens,
                            outputTokens: usage.completionTokens
                        )
                    ))
                }

                if let completed = chunk.completedToolCalls, !completed.isEmpty {
                    let parsedToolCalls = try ConduitToolCallConverter.toParsedToolCalls(completed)
                    continuation.yield(.toolCallsCompleted(parsedToolCalls))
                }
            }

            continuation.finish()
        }
    }

    // MARK: - Private

    private let provider: Provider
    private let model: Provider.ModelID
    private let baseConfig: GenerateConfig
    private let supportsStreamingToolCalls: Bool

    private static func conduitMessages(from messages: [InferenceMessage]) throws -> [Message] {
        let toolNamesByCallID = Dictionary(
            uniqueKeysWithValues: messages
                .flatMap(\.toolCalls)
                .compactMap { call in
                    call.id.map { ($0, call.name) }
                }
        )

        return try messages.map { message in
            try conduitMessage(from: message, toolNamesByCallID: toolNamesByCallID)
        }
    }

    private static func conduitMessage(
        from message: InferenceMessage,
        toolNamesByCallID: [String: String]
    ) throws -> Message {
        switch message.role {
        case .system:
            return .system(message.content)
        case .user:
            return .user(message.content)
        case .assistant:
            let toolCalls = try message.toolCalls.map(conduitToolCall(from:))
            if !toolCalls.isEmpty {
                return .assistant(message.content, toolCalls: toolCalls)
            }
            return .assistant(message.content)
        case .tool:
            guard let toolCallID = message.toolCallID else {
                throw AgentError.generationFailed(reason: "Structured tool message is missing toolCallID")
            }

            let toolName = message.name ?? toolNamesByCallID[toolCallID]
            guard let toolName else {
                throw AgentError.generationFailed(reason: "Structured tool message is missing tool name for \(toolCallID)")
            }

            return .toolOutput(
                Transcript.ToolOutput(
                    id: toolCallID,
                    toolName: toolName,
                    segments: [.text(.init(content: message.content))]
                )
            )
        }
    }

    private static func conduitToolCall(from toolCall: InferenceMessage.ToolCall) throws -> Transcript.ToolCall {
        let jsonObject = try jsonObject(from: .dictionary(toolCall.arguments))
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return try Transcript.ToolCall(
            id: toolCall.id ?? UUID().uuidString,
            toolName: toolCall.name,
            argumentsJSON: json
        )
    }

    private static func jsonObject(from value: SendableValue) throws -> Any {
        switch value {
        case .null:
            return NSNull()
        case let .bool(bool):
            return bool
        case let .int(int):
            return int
        case let .double(double):
            return double
        case let .string(string):
            return string
        case let .array(elements):
            return try elements.map(jsonObject(from:))
        case let .dictionary(dictionary):
            return try dictionary.mapValues { try jsonObject(from: $0) }
        }
    }

    private func apply(options: InferenceOptions, to config: GenerateConfig) throws -> GenerateConfig {
        var updated = config

        updated = updated.temperature(Float(options.temperature))

        if let maxTokens = options.maxTokens {
            updated = updated.maxTokens(maxTokens)
        }

        if let seed = options.seed {
            updated = updated.seed(UInt64(bitPattern: Int64(seed)))
        }

        if let topP = options.topP {
            updated = updated.topP(Float(topP))
        }

        if let topK = options.topK {
            updated = updated.topK(topK)
        }

        if let frequencyPenalty = options.frequencyPenalty {
            updated = updated.frequencyPenalty(Float(frequencyPenalty))
        }

        if let presencePenalty = options.presencePenalty {
            updated = updated.presencePenalty(Float(presencePenalty))
        }

        if !options.stopSequences.isEmpty {
            updated = updated.stopSequences(options.stopSequences)
        }

        if let parallelToolCalls = options.parallelToolCalls {
            updated = updated.parallelToolCalls(parallelToolCalls)
        }

        if let structuredOutput = options.structuredOutput {
            updated = updated.responseFormat(try Self.conduitResponseFormat(from: structuredOutput.format))
        }

        if let providerSettings = options.providerSettings, !providerSettings.isEmpty {
            updated = try applyProviderRuntimeSettings(providerSettings, to: updated)
        }

        return updated
    }

    private func applyProviderRuntimeSettings(
        _ providerSettings: [String: SendableValue],
        to config: GenerateConfig
    ) throws -> GenerateConfig {
        let unsupportedRuntimeKeys = providerSettings.keys
            .filter { $0.hasPrefix("conduit.runtime.") }
            .sorted()

        if !unsupportedRuntimeKeys.isEmpty {
            let keyList = unsupportedRuntimeKeys.joined(separator: ", ")
            throw AgentError.inferenceProviderUnavailable(
                reason: "Conduit runtime policy settings are not supported yet: \(keyList)"
            )
        }

        return config
    }

    private static func conduitResponseFormat(
        from format: StructuredOutputFormat
    ) throws -> ResponseFormat {
        switch format {
        case .jsonObject:
            return .jsonObject
        case .jsonSchema(let name, let schemaJSON):
            guard let data = schemaJSON.data(using: .utf8) else {
                throw AgentError.generationFailed(reason: "Structured output schema is not valid UTF-8")
            }
            do {
                let schema = try JSONDecoder().decode(GenerationSchema.self, from: data)
                return .jsonSchema(name: name, schema: schema)
            } catch {
                throw AgentError.generationFailed(
                    reason: "Failed to decode structured output schema for Conduit: \(error.localizedDescription)"
                )
            }
        }
    }


    private func firstBool(
        for keys: [String],
        in providerSettings: [String: SendableValue]
    ) -> Bool? {
        for key in keys {
            if let value = providerSettings[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    private func firstInt(
        for keys: [String],
        in providerSettings: [String: SendableValue]
    ) -> Int? {
        for key in keys {
            if let value = providerSettings[key]?.intValue {
                return value
            }
        }
        return nil
    }

    private func firstDouble(
        for keys: [String],
        in providerSettings: [String: SendableValue]
    ) -> Double? {
        for key in keys {
            if let value = providerSettings[key]?.doubleValue {
                return value
            }
        }
        return nil
    }

    private func firstStringSet(
        for keys: [String],
        in providerSettings: [String: SendableValue]
    ) -> Set<String>? {
        for key in keys {
            guard let elements = providerSettings[key]?.arrayValue else { continue }
            return Set(elements.compactMap(\.stringValue))
        }
        return nil
    }

    private func mapFinishReason(
        _ reason: FinishReason,
        toolCalls: [InferenceResponse.ParsedToolCall]
    ) -> InferenceResponse.FinishReason {
        if reason.isToolCallRequest || !toolCalls.isEmpty {
            return .toolCall
        }

        switch reason {
        case .maxTokens:
            return .maxTokens
        case .contentFilter:
            return .contentFilter
        case .cancelled:
            return .cancelled
        default:
            return .completed
        }
    }

    private func parsedToolCalls(
        from result: GenerationResult,
        tools: [ToolSchema]
    ) throws -> [InferenceResponse.ParsedToolCall] {
        let direct = try ConduitToolCallConverter.toParsedToolCalls(result.toolCalls)
        if !direct.isEmpty {
            return direct
        }

        guard !result.text.isEmpty else {
            return []
        }

        return ConduitPromptToolFallbackParser.parseToolCalls(
            from: result.text,
            availableTools: tools
        )
    }
}

// MARK: - Tool Schema Conversion

enum ConduitToolSchemaConverter {
    static func toolDefinitions(from tools: [ToolSchema]) throws -> [Transcript.ToolDefinition] {
        try tools.map { tool in
            let schema = try generationSchema(for: tool)
            return Transcript.ToolDefinition(
                name: tool.name,
                description: tool.description,
                parameters: schema
            )
        }
    }

    static func generationSchema(for tool: ToolSchema) throws -> GenerationSchema {
        let rootName = SchemaName.rootName(for: tool.name)
        let properties = try tool.parameters.map { parameter in
            let schema = try dynamicSchema(
                for: parameter.type,
                name: SchemaName.propertyName(root: rootName, property: parameter.name)
            )
            return DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: schema,
                isOptional: !parameter.isRequired
            )
        }

        let root = DynamicGenerationSchema(
            name: rootName,
            description: "Tool parameters for \(tool.name)",
            properties: properties
        )

        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func dynamicSchema(
        for type: ToolParameter.ParameterType,
        name: String
    ) throws -> DynamicGenerationSchema {
        switch type {
        case .string:
            return DynamicGenerationSchema(type: String.self)
        case .int:
            return DynamicGenerationSchema(type: Int.self)
        case .double:
            return DynamicGenerationSchema(type: Double.self)
        case .bool:
            return DynamicGenerationSchema(type: Bool.self)
        case .array(let elementType):
            let elementSchema = try dynamicSchema(for: elementType, name: SchemaName.childName(base: name, suffix: "item"))
            return DynamicGenerationSchema(arrayOf: elementSchema)
        case .object(let properties):
            let objectName = SchemaName.objectName(for: name)
            let objectProperties = try properties.map { parameter in
                let schema = try dynamicSchema(
                    for: parameter.type,
                    name: SchemaName.childName(base: objectName, suffix: parameter.name)
                )
                return DynamicGenerationSchema.Property(
                    name: parameter.name,
                    description: parameter.description,
                    schema: schema,
                    isOptional: !parameter.isRequired
                )
            }
            return DynamicGenerationSchema(
                name: objectName,
                description: nil,
                properties: objectProperties
            )
        case .oneOf(let options):
            return DynamicGenerationSchema(
                name: SchemaName.enumName(for: name),
                description: nil,
                anyOf: options
            )
        case .any:
            return DynamicGenerationSchema(
                name: SchemaName.anyName(for: name),
                description: nil,
                anyOf: [
                    DynamicGenerationSchema(type: String.self),
                    DynamicGenerationSchema(type: Double.self),
                    DynamicGenerationSchema(type: Bool.self)
                ]
            )
        }
    }

    private enum SchemaName {
        static func rootName(for toolName: String) -> String {
            sanitize("SwarmToolParams_\(toolName)")
        }

        static func propertyName(root: String, property: String) -> String {
            sanitize("\(root)_\(property)")
        }

        static func childName(base: String, suffix: String) -> String {
            sanitize("\(base)_\(suffix)")
        }

        static func objectName(for name: String) -> String {
            sanitize("\(name)_Object")
        }

        static func enumName(for name: String) -> String {
            sanitize("\(name)_Enum")
        }

        static func anyName(for name: String) -> String {
            sanitize("\(name)_Any")
        }

        private static func sanitize(_ value: String) -> String {
            let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
            let sanitized = value.map { allowed.contains($0) ? $0 : "_" }
            let trimmed = String(sanitized).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "SwarmToolParams" : trimmed
        }
    }
}

// MARK: - Tool Call Conversion

enum ConduitToolCallConverter {
    static func toParsedToolCalls(
        _ toolCalls: [Transcript.ToolCall]
    ) throws -> [InferenceResponse.ParsedToolCall] {
        try toolCalls.map { try toParsedToolCall($0) }
    }

    static func toParsedToolCall(
        _ toolCall: Transcript.ToolCall
    ) throws -> InferenceResponse.ParsedToolCall {
        let arguments = try parseArguments(toolCall.arguments, toolName: toolCall.toolName)
        return InferenceResponse.ParsedToolCall(
            id: toolCall.id,
            name: toolCall.toolName,
            arguments: arguments
        )
    }

    private static func parseArguments(
        _ content: GeneratedContent,
        toolName: String
    ) throws -> [String: SendableValue] {
        let jsonString = content.jsonString
        guard let data = jsonString.data(using: .utf8) else {
            throw AgentError.invalidToolArguments(toolName: toolName, reason: "Invalid UTF-8 tool arguments")
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dict = jsonObject as? [String: Any] else {
            throw AgentError.invalidToolArguments(toolName: toolName, reason: "Tool arguments must be a JSON object")
        }

        var result: [String: SendableValue] = [:]
        for (key, value) in dict {
            result[key] = SendableValue.fromJSONValue(value)
        }
        return result
    }
}

extension ConduitInferenceProvider: PromptTokenCounter where Provider: ConduitAdvanced.TokenCounter {
    func countTokens(in text: String) async throws -> Int {
        try await provider.countTokens(in: text, for: model).count
    }
}

extension ConduitInferenceProvider: PromptTokenCountingInferenceProvider where Provider: ConduitAdvanced.TokenCounter {}

enum ConduitPromptToolFallbackParser {
    private static let envelopeKey = "conduit_tool_call"

    static func parseToolCalls(
        from content: String,
        availableTools: [ToolSchema]
    ) -> [InferenceResponse.ParsedToolCall] {
        for candidate in extractJSONObjectCandidates(from: content) {
            if let parsed = parseToolCall(from: candidate, availableTools: availableTools) {
                return [parsed]
            }
        }

        if let parsed = parseToolCall(from: content, availableTools: availableTools) {
            return [parsed]
        }

        return []
    }

    private static func parseToolCall(
        from candidate: String,
        availableTools: [ToolSchema]
    ) -> InferenceResponse.ParsedToolCall? {
        let trimmed = stripCodeFences(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        let repaired = repairJSONObjectCandidate(trimmed)
        guard repaired.first == "{", repaired.last == "}" else {
            return nil
        }

        guard let data = repaired.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
        else {
            return nil
        }

        let envelope: [String: Any]
        if let wrapped = json[envelopeKey] as? [String: Any] {
            envelope = wrapped
        } else {
            envelope = json
        }

        guard let resolvedToolName = resolveToolName(from: envelope, availableTools: availableTools) else {
            return nil
        }

        var arguments = (envelope["arguments"] as? [String: Any]) ?? [:]
        if arguments.isEmpty {
            arguments = envelope.filter { key, _ in
                key != "tool" && key != "tool_name" && key != "name" && key != "nonce"
            }
        }
        arguments.removeValue(forKey: "tool")
        arguments.removeValue(forKey: "tool_name")
        arguments.removeValue(forKey: "name")
        arguments.removeValue(forKey: "nonce")

        return InferenceResponse.ParsedToolCall(
            id: UUID().uuidString,
            name: resolvedToolName,
            arguments: arguments.reduce(into: [:]) { partial, item in
                partial[item.key] = SendableValue.fromJSONValue(item.value)
            }
        )
    }

    private static func resolveToolName(
        from envelope: [String: Any],
        availableTools: [ToolSchema]
    ) -> String? {
        let candidates = [
            envelope["tool_name"] as? String,
            envelope["tool"] as? String,
            envelope["name"] as? String,
            (envelope["arguments"] as? [String: Any])?["tool"] as? String,
            (envelope["arguments"] as? [String: Any])?["tool_name"] as? String,
        ]

        for candidate in candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            if availableTools.contains(where: { $0.name == candidate }) {
                return candidate
            }
        }
        return nil
    }

    private static func extractJSONObjectCandidates(from content: String) -> [String] {
        let stripped = stripCodeFences(content)
        guard let firstBrace = stripped.firstIndex(of: "{") else {
            return []
        }

        var candidates: [String] = []
        var depth = 0
        var startIndex: String.Index?
        var inString = false
        var isEscaped = false

        for index in stripped.indices {
            let character = stripped[index]

            if character == "\"" && !isEscaped {
                inString.toggle()
            }

            if inString {
                isEscaped = character == "\\" && !isEscaped
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let candidateStart = startIndex {
                    candidates.append(String(stripped[candidateStart...index]))
                    startIndex = nil
                }
            }

            isEscaped = character == "\\" && !isEscaped
        }

        if candidates.isEmpty {
            candidates.append(String(stripped[firstBrace...]))
        }

        return candidates
    }

    private static func stripCodeFences(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func repairJSONObjectCandidate(_ text: String) -> String {
        guard text.first == "{" else {
            return text
        }

        var depth = 0
        var inString = false
        var isEscaped = false

        for character in text {
            if character == "\"" && !isEscaped {
                inString.toggle()
            }

            if inString {
                isEscaped = character == "\\" && !isEscaped
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
            }

            isEscaped = character == "\\" && !isEscaped
        }

        guard depth > 0 else {
            return text
        }

        return text + String(repeating: "}", count: depth)
    }
}
