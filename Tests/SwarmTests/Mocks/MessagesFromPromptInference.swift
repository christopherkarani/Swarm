import Foundation
@testable import Swarm

/// Test-only: satisfy ``InferenceProvider`` messages generate by flattening to the type's prompt method.
protocol MessagesFromPromptInference: InferenceProvider {}

extension MessagesFromPromptInference {
    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(
            prompt: InferenceMessage.flattenPrompt(messages),
            options: options
        )
    }
}
