import Foundation

/// Serializes structured history into a single `Prompt` string.
///
/// Capture prefers ``FoundationModelsTranscriptSeed`` so Apple sees roles
/// natively. This flatten path is the fallback when a message cannot be
/// represented (assistant tool-call metadata or extra system text). On OS 27,
/// ``ToolChoice/required`` is `GenerationOptions.toolCallingMode` instead of
/// a prompt sentence.
enum FoundationModelsPromptFlattening: Sendable {
    static let requiredToolGuidance = "You must call one of the available tools before answering."

    static func flatten(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> String {
        // Attachments stay off the prompt string. OS 26 ignores them; do not
        // flatten PCM or image bytes into text.
        let prompt = ConversationHistoryRenderer.render(messages, style: .plain)
        return appendTurnSuffixes(to: prompt, tools: tools, options: options)
    }

    /// Tool-choice and structured-output sentences that flatten appends after history.
    ///
    /// Transcript rehydration still needs these: the pending user turn is a
    /// raw prompt, not a flattened history string.
    static func appendTurnSuffixes(
        to prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> String {
        var prompt = prompt
        if shouldPromptInjectToolChoice, !tools.isEmpty {
            switch options.toolChoice {
            case .required:
                prompt += "\n\n\(requiredToolGuidance)"
            case let .specific(toolName):
                prompt += "\n\nIf you need a tool, call \"\(toolName)\"."
            case .auto, ToolChoice.none?, nil:
                break
            }
        } else if !tools.isEmpty, case let .specific(toolName) = options.toolChoice {
            prompt += "\n\nIf you need a tool, call \"\(toolName)\"."
        }

        if let structuredOutput = options.structuredOutput {
            prompt = StructuredOutputPromptBuilder.appendInstruction(to: prompt, request: structuredOutput)
        }

        return prompt
    }

    /// OS 27 has `GenerationOptions.toolCallingMode`. OS 26 still needs a
    /// prompt sentence for ``ToolChoice/required``.
    static var shouldPromptInjectToolChoice: Bool {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            return false
        }
        return true
    }

}
