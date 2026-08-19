// FoundationModelsNativeTool.swift
// Swarm Framework
//
// Wraps a FoundationModels.Tool as a Swarm AnyJSONTool for @ToolBuilder.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Adapts a user-authored `FoundationModels.Tool` into a Swarm tool.
///
/// Use this (or pass the Apple tool directly to `@ToolBuilder`) to register
/// native Foundation Models tools alongside `@Tool` macros and ``FunctionTool``.
///
/// - Experiment: Intended for ``InferenceProvider/foundationModelsOwningToolLoop()``.
///   In capture mode the wrapper still executes via Swarm's loop, converting
///   arguments through `GeneratedContent`.
///
/// ```swift
/// struct LookupTool: FoundationModels.Tool {
///     var name: String { "lookup" }
///     var description: String { "Look up a topic" }
///     // ...
/// }
///
/// let agent = try Agent(
///     "Be helpful.",
///     inferenceProvider: .foundationModelsOwningToolLoop()
/// ) {
///     WeatherTool()
///     LookupTool()
/// }
/// ```
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public struct FoundationModelsNativeTool: AnyJSONTool {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]

    private let executor: @Sendable ([String: SendableValue]) async throws -> SendableValue

    /// Wraps a `FoundationModels.Tool` so it can live in a Swarm tool registry.
    public init<T: FoundationModels.Tool>(_ tool: T) {
        name = tool.name
        description = tool.description
        parameters = [
            ToolParameter(
                name: "arguments",
                description: "Arguments for \(tool.name)",
                type: .object(properties: []),
                isRequired: false
            ),
        ]
        executor = { arguments in
            let content = FoundationModelsSchemaConversion.generatedContent(from: arguments)
            let typed = try T.Arguments(content)
            let output = try await tool.call(arguments: typed)
            if let string = output as? String {
                return .string(string)
            }
            return .string(String(describing: output))
        }
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await executor(arguments)
    }
}
#endif
