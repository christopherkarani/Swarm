// FoundationModelsExecutingTool.swift
// Swarm Framework
//
// Real FoundationModels.Tool wrappers that execute Swarm tools (native session mode).

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Error thrown from a native-mode tool so Foundation Models can surface a
/// recoverable tool failure without crashing the process.
///
/// Cancellation and ``AgentConfiguration/stopOnToolError`` abort the session by
/// throwing. Other tool failures are returned as error strings from ``call(arguments:)``
/// so `LanguageModelSession.respond` can continue — throwing from `call` aborts
/// the session the same way capture-mode tools do.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsNativeToolError: Error, LocalizedError, Sendable {
    let toolName: String
    let message: String

    var errorDescription: String? {
        "Tool '\(toolName)' failed: \(message)"
    }
}

/// Runs the call's ``ToolCallExecutor`` and returns a string Apple can feed back.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
actor FoundationModelsNativeToolRuntime {
    private let executor: ToolCallExecutor

    init(executor: ToolCallExecutor) {
        self.executor = executor
    }

    func execute(name: String, arguments: [String: SendableValue]) async throws -> String {
        do {
            let output = try await executor.executeTool(named: name, arguments: arguments)
            return Agent.toolOutputText(for: output)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AgentError {
            if case .toolExecutionFailed = error {
                throw FoundationModelsNativeToolError(
                    toolName: name,
                    message: error.localizedDescription
                )
            }
            return "Tool '\(name)' failed: \(error.localizedDescription)"
        } catch {
            return "Tool '\(name)' failed: \(error.localizedDescription)"
        }
    }
}

/// A genuine `FoundationModels.Tool` whose `call(arguments:)` executes the
/// matching Swarm tool instead of capturing-and-throwing.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct FoundationModelsExecutingTool: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    var includesSchemaInInstructions: Bool { true }

    private let runtime: FoundationModelsNativeToolRuntime

    init(
        name: String,
        description: String,
        parameters: GenerationSchema,
        runtime: FoundationModelsNativeToolRuntime
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.runtime = runtime
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let parsed = FoundationModelsSchemaConversion.argumentDictionary(from: arguments)
        return try await runtime.execute(name: name, arguments: parsed)
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension FoundationModelsToolBridge {
    /// Builds executing Foundation Models tools from Swarm schemas.
    ///
    /// Unlike ``makeCaptureTools(from:store:)``, these tools run Swarm tools (with
    /// guardrails and observers) inside `LanguageModelSession`'s own loop.
    static func makeExecutingTools(
        from tools: [ToolSchema],
        executor: ToolCallExecutor
    ) throws -> [any FoundationModels.Tool] {
        let runtime = FoundationModelsNativeToolRuntime(executor: executor)
        return try tools.map { schema in
            let parameters = try FoundationModelsSchemaConversion.argumentSchema(for: schema)
            return FoundationModelsExecutingTool(
                name: schema.name,
                description: schema.description,
                parameters: parameters,
                runtime: runtime
            )
        }
    }
}
#endif
