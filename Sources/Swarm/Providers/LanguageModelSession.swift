//
//  LanguageModelSession.swift
//  Swarm
//
//  InferenceProvider conformance for Apple's LanguageModelSession.
//
//  Prefer ``FoundationModelsInferenceProvider`` for new code — it owns session
//  lifecycle and native tool bridging. This extension remains for apps that
//  construct a session themselves and pass it as an inference provider.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension LanguageModelSession: InferenceProvider {
    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        var generationOptions = GenerationOptions()
        generationOptions.temperature = options.temperature
        if let maxTokens = options.maxTokens {
            generationOptions.maximumResponseTokens = maxTokens
        }

        let response = try await respond(to: prompt, options: generationOptions)
        var content = response.content

        // Manual stop sequences — Foundation Models GenerationOptions does not
        // surface stopSequences on the current SDK.
        var earliestStop: String.Index?
        for stopSequence in options.stopSequences {
            if let range = content.range(of: stopSequence) {
                if earliestStop == nil || range.lowerBound < earliestStop! {
                    earliestStop = range.lowerBound
                }
            }
        }
        if let stop = earliestStop {
            content = String(content[..<stop])
        }

        return content
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        var generationOptions = GenerationOptions()
        generationOptions.temperature = options.temperature
        if let maxTokens = options.maxTokens {
            generationOptions.maximumResponseTokens = maxTokens
        }
        let resolvedOptions = generationOptions

        return StreamHelper.makeTrackedStream { continuation in
            do {
                var previous = ""
                for try await snapshot in self.streamResponse(to: prompt, options: resolvedOptions) {
                    let current = snapshot.content
                    let delta: String
                    if current.hasPrefix(previous) {
                        delta = String(current.dropFirst(previous.count))
                    } else {
                        delta = current
                    }
                    previous = current
                    if !delta.isEmpty {
                        continuation.yield(delta)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                throw AgentError.cancelled
            }
        }
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        // A caller-owned LanguageModelSession may already have been created without
        // tools. Native FoundationModels tools must be attached at session init, so
        // tool-calling requests are delegated to the first-class provider which
        // creates a properly configured session.
        let provider = FoundationModelsInferenceProvider(
            configuration: FoundationModelsProviderConfiguration(
                instructions: nil,
                prewarmOnInit: false
            )
        )
        return try await provider.generateWithToolCalls(
            prompt: prompt,
            tools: tools,
            options: options
        )
    }
}
#endif
