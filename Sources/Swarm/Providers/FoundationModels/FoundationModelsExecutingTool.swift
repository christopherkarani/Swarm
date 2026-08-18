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

/// Runtime shared by every executing Foundation Models tool in a native session turn.
///
/// Owns Swarm tool lookup, input/output guardrails, observer hooks, and
/// ``AgentResult`` recording. Isolation keeps parallel Apple tool calls from
/// racing the result builder.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
actor FoundationModelsNativeToolRuntime {
    private let registry: ToolRegistry
    private let agent: any AgentRuntime
    private let context: AgentContext?
    private let observer: (any AgentObserver)?
    private let tracing: TracingHelper?
    private let resultBuilder: AgentResult.Builder
    private let stopOnToolError: Bool
    private let executionGate: ProviderOwnedLoopGate

    init(
        registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        observer: (any AgentObserver)?,
        tracing: TracingHelper?,
        resultBuilder: AgentResult.Builder,
        stopOnToolError: Bool,
        executionGate: ProviderOwnedLoopGate
    ) {
        self.registry = registry
        self.agent = agent
        self.context = context
        self.observer = observer
        self.tracing = tracing
        self.resultBuilder = resultBuilder
        self.stopOnToolError = stopOnToolError
        self.executionGate = executionGate
    }

    /// Executes a Swarm tool and returns a string Foundation Models can feed back
    /// into the session. Recoverable failures become error strings; aborting
    /// failures throw ``FoundationModelsNativeToolError`` or `CancellationError`.
    func execute(name: String, arguments: [String: SendableValue]) async throws -> String {
        guard executionGate.isActive, !Task.isCancelled else {
            throw CancellationError()
        }
        let call = ToolCall(toolName: name, arguments: arguments)
        _ = resultBuilder.addToolCall(call)
        await observer?.onToolStart(context: context, agent: agent, call: call)

        let spanId: UUID? = if let tracing {
            await tracing.traceToolCall(name: name, arguments: arguments)
        } else {
            nil
        }
        let startTime = ContinuousClock.now

        do {
            let output = try await registry.execute(
                toolNamed: name,
                arguments: arguments,
                agent: agent,
                context: context,
                observer: observer
            )
            let duration = ContinuousClock.now - startTime
            let result = ToolResult.success(callId: call.id, output: output, duration: duration)
            _ = resultBuilder.addToolResult(result)
            if let tracing, let spanId {
                await tracing.traceToolResult(
                    spanId: spanId,
                    name: name,
                    result: output.description,
                    duration: duration
                )
            }
            await observer?.onToolEnd(context: context, agent: agent, result: result)
            return Agent.toolOutputText(for: output)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let duration = ContinuousClock.now - startTime
            let errorMessage = (error as? AgentError)?.localizedDescription
                ?? error.localizedDescription
            let result = ToolResult.failure(callId: call.id, error: errorMessage, duration: duration)
            _ = resultBuilder.addToolResult(result)
            if let tracing, let spanId {
                await tracing.traceToolError(spanId: spanId, name: name, error: error)
            }
            await observer?.onToolEnd(context: context, agent: agent, result: result)

            if stopOnToolError {
                throw FoundationModelsNativeToolError(toolName: name, message: errorMessage)
            }

            // Return the failure as tool output so LanguageModelSession can recover.
            return "Tool '\(name)' failed: \(errorMessage)"
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
        runtime: FoundationModelsNativeToolRuntime
    ) throws -> [any FoundationModels.Tool] {
        try tools.map { schema in
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
