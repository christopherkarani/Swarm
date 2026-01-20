//
//  LanguageModelSession.swift
//  SwiftAgents
//
//  Created by Chris Karani on 16/01/2026.
//

// Gate FoundationModels import for cross-platform builds (Linux, Windows, etc.)
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
extension LanguageModelSession: InferenceProvider {
    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        // Create a request with the prompt
        let response = try await self.respond(to: prompt)
        var content = response.content

        // Handle manual stop sequences since Foundation Models might not support them natively via this API
        for stopSequence in options.stopSequences {
            if let range = content.range(of: stopSequence) {
                content = String(content[..<range.lowerBound])
            }
        }

        return content
    }

    public func stream(prompt: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For streaming, we'll generate the full response and yield it
                    for try await stream in self.streamResponse(to: prompt) {
                        continuation.yield(stream.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateWithToolCalls(
        prompt: String,
        tools _: [ToolDefinition],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        // TODO: Implement native tool calling for FoundationModels
        // Foundation Models on-device may support function calling in future releases.
        // For now, fall back to text generation without tool calls.
        let response = try await self.respond(to: prompt)

        return InferenceResponse(
            content: response.content,
            toolCalls: [],
            finishReason: .completed
        )
    }
}
#endif