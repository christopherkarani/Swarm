//
//  LanguageModelSession.swift
//  Swarm
//
//  Created by Chris Karani on 16/01/2026.
//

import Foundation

// Gate FoundationModels import for cross-platform builds (Linux, Windows, etc.)
#if canImport(FoundationModels)
    import FoundationModels

    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    extension LanguageModelSession: InferenceProvider {
        public func generate(prompt: String, options: InferenceOptions) async throws -> String {
            // Create a request with the prompt
            let response = try await respond(to: prompt)
            var content = response.content

            // Handle manual stop sequences since Foundation Models might not support them natively via this API.
            // Find the earliest occurring stop sequence and truncate at that point.
            var earliestStop: String.Index? = nil
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

        public func stream(prompt: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
            StreamHelper.makeTrackedStream { continuation in
                do {
                    // For streaming, we'll generate the full response and yield it.
                    for try await stream in self.streamResponse(to: prompt) {
                        continuation.yield(stream.content)
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
            try await LanguageModelSessionToolCallingEmulation.generateResponse(
                prompt: prompt,
                tools: tools,
                options: options
            ) { toolPrompt, options in
                try await self.generate(prompt: toolPrompt, options: options)
            }
        }
    }
#endif
