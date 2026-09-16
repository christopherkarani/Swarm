import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Builds Apple `GenerationOptions` from Swarm ``InferenceOptions``.
///
/// Uses `samplingMode` (the `sampling` alias is deprecated). On OS 27,
/// `toolCallingMode` maps ``ToolChoice/required`` and ``ToolChoice/none``.
enum FoundationModelsGenerationOptions: Sendable {
    static func make(from options: InferenceOptions) -> GenerationOptions {
        var generationOptions = GenerationOptions()
        generationOptions.temperature = options.temperature
        if let maxTokens = options.maxTokens {
            generationOptions.maximumResponseTokens = maxTokens
        }
        if options.temperature == 0 {
            generationOptions.samplingMode = .greedy
        } else if let topP = options.topP, topP > 0, topP <= 1 {
            generationOptions.samplingMode = .random(probabilityThreshold: topP)
        }
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            generationOptions.toolCallingMode = toolCallingMode(for: options.toolChoice)
        }
        return generationOptions
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func toolCallingMode(for choice: ToolChoice?) -> GenerationOptions.ToolCallingMode? {
        switch choice {
        case .required:
            return .required
        case ToolChoice.none?:
            return .disallowed
        case .auto, .specific, nil:
            return .allowed
        }
    }
}
#endif
