#if canImport(MLX)
import Conduit
import Foundation

func makeMLXInferenceProvider(model: Model) -> any InferenceProvider {
    TextOnlyConversationInferenceProviderAdapter(base: MLXPromptProvider(model: model))
}

private struct MLXPromptProvider: Sendable, InferenceProvider {
    private let conduit: Conduit
    private let model: Model

    init(model: Model) {
        self.conduit = Conduit(Provider.mlx())
        self.model = model
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        let session = try makeSession(options: options)
        return try await session.run(prompt)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        do {
            let session = try makeSession(options: options)
            return session.stream(prompt)
        } catch {
            return StreamHelper.makeTrackedStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    private func makeSession(options: InferenceOptions) throws -> ConduitTypes.Session {
        try conduit.session(model: model) { sessionOptions in
            sessionOptions.run { run in
                run = Self.apply(options: options, to: run)
            }
        }
    }

    private static func apply(options: InferenceOptions, to config: GenerateConfig) throws -> GenerateConfig {
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
            updated = updated.parallelToolCalls(ParallelToolMode(parallelToolCalls))
        }

        if let structuredOutput = options.structuredOutput {
            updated = updated.responseFormat(try conduitResponseFormat(from: structuredOutput.format))
        }

        if let reasoning = options.reasoning {
            updated = updated.reasoning(conduitReasoning(from: reasoning))
        }

        if let providerSettings = options.providerSettings, !providerSettings.isEmpty {
            updated = try applyProviderRuntimeSettings(providerSettings, to: updated)
        }

        return updated
    }

    private static func conduitReasoning(from reasoning: ReasoningConfig) -> ConduitTypes.ReasoningConfig {
        ConduitTypes.ReasoningConfig(
            effort: reasoning.effort.flatMap { ConduitTypes.ReasoningEffort(rawValue: $0.rawValue) },
            maxTokens: reasoning.maxTokens,
            exclude: reasoning.exclude,
            enabled: reasoning.enabled
        )
    }

    private static func applyProviderRuntimeSettings(
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
                    reason: "Failed to decode structured output schema for MLX: \(error.localizedDescription)"
                )
            }
        }
    }
}
#endif
