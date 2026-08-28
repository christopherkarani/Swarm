#if SWARM_OTEL
// OpenTelemetryAgentRuntime.swift
// SwarmOpenTelemetry

import Foundation
@preconcurrency import OpenTelemetryApi
import Swarm

/// An agent-runtime wrapper that creates one OpenTelemetry trace scope per user turn.
struct OpenTelemetryAgentRuntime<Base: AgentRuntime>: @unchecked Sendable, AgentRuntime {
  public init(
        _ base: Base,
        tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: "swarm.agent",
            instrumentationVersion: nil
        ),
        llmTracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: "swarm.llm",
            instrumentationVersion: nil
        ),
        spanName: String? = nil,
        captureContent: Bool = false
    ) {
        self.base = base
        self.otelConfiguration = OpenTelemetryAgentRuntimeConfiguration(
            tracer: tracer,
            llmTracer: llmTracer,
            spanName: spanName,
            captureContent: captureContent
        )
    }

    public var name: String { base.name }
    public var tools: [any AnyJSONTool] { base.tools }
    public var instructions: String { base.instructions }
    public var configuration: AgentConfiguration { base.configuration }
    public var memory: (any Memory)? { base.memory }
    public var inferenceProvider: (any InferenceProvider)? { base.inferenceProvider }
    public var tracer: (any SwarmRuntimeTracer)? { base.tracer }
    public var inputGuardrails: [any InputGuardrail] { base.inputGuardrails }
    public var outputGuardrails: [any OutputGuardrail] { base.outputGuardrails }
    public var handoffs: [AnyHandoffConfiguration] { base.handoffs }

    public func run(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResult {
        try await withAgentSpan(operation: "run", input: input) { span in
            let result = try await base.run(input, session: session, observer: observer)
            apply(result: result, to: span)
            return result
        }
    }

    public func runWithResponse(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResponse {
        try await withAgentSpan(operation: "runWithResponse", input: input) { span in
            let response = try await base.runWithResponse(input, session: session, observer: observer)
            apply(response: response, to: span)
            return response
        }
    }

    public func stream(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await withAgentSpan(operation: "stream", input: input) { span in
                        for try await event in base.stream(input, session: session, observer: observer) {
                            if case let .lifecycle(.completed(result)) = event {
                                apply(result: result, to: span)
                            }
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func cancel() async {
        await base.cancel()
    }

    private let base: Base
    private let otelConfiguration: OpenTelemetryAgentRuntimeConfiguration
}

extension OpenTelemetryAgentRuntime where Base == Agent {
    func runStructured(
        _ input: String,
        request: StructuredOutputRequest,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> StructuredAgentResult {
        try await withAgentSpan(operation: "runStructured", input: input) { span in
            let result = try await base.runStructured(input, request: request, session: session, observer: observer)
            apply(result: result.agentResult, to: span)
            span.setAttribute(key: "gen_ai.output.type", value: "json")
            span.setAttribute(key: "gen_ai.response.output_length", value: result.structuredOutput.rawJSON.count)
            return result
        }
    }
}

private final class OpenTelemetryAgentRuntimeConfiguration: @unchecked Sendable {
    init(
        tracer: any OpenTelemetryApi.Tracer,
        llmTracer: any OpenTelemetryApi.Tracer,
        spanName: String?,
        captureContent: Bool
    ) {
        self.tracer = tracer
        self.llmTracer = llmTracer
        self.spanName = spanName
        self.captureContent = captureContent
    }

    let tracer: any OpenTelemetryApi.Tracer
    let llmTracer: any OpenTelemetryApi.Tracer
    let spanName: String?
    let captureContent: Bool
}

private extension OpenTelemetryAgentRuntime {
    func withAgentSpan<T: Sendable>(
        operation: String,
        input: String,
        _ body: @escaping @Sendable (any SpanBase) async throws -> T
    ) async throws -> T {
        let builder = otelConfiguration.tracer.spanBuilder(spanName: spanName(operation: operation))
        builder.setSpanKind(spanKind: .internal)
        builder.setAttribute(key: "swarm.operation.name", value: operation)
        builder.setAttribute(key: "swarm.agent.name", value: name)
        builder.setAttribute(key: "swarm.request.input_length", value: input.count)

        return try await builder.withActiveSpan { span in
            try await OpenTelemetryTracePropagation.withCurrentSpan(span) {
                do {
                    let result = try await withInstrumentedProviderEnvironment {
                        try await body(span)
                    }
                    span.status = .ok
                    return result
                } catch {
                    OpenTelemetryAttributes.recordError(error, on: span)
                    throw error
                }
            }
        }
    }

    func withInstrumentedProviderEnvironment<T: Sendable>(
        _ body: () async throws -> T
    ) async throws -> T {
        var environment = AgentEnvironmentValues.current
        let existingTransform = environment.inferenceProviderTransform
        let configuration = otelConfiguration

        environment.inferenceProviderTransform = { provider in
            let transformed = existingTransform?(provider) ?? provider
            if transformed is any OpenTelemetryInstrumentedInferenceProvider {
                return transformed
            }
            return OpenTelemetryAnyInferenceProvider(
                transformed,
                tracer: configuration.llmTracer,
                captureContent: configuration.captureContent
            )
        }

        return try await AgentEnvironmentValues.$current.withValue(environment) {
            try await body()
        }
    }

    func spanName(operation: String) -> String {
        otelConfiguration.spanName ?? "swarm.agent.\(operation) \(name)"
    }

    func apply(result: AgentResult, to span: any SpanBase) {
        span.setAttribute(key: "swarm.response.output_length", value: result.output.count)
        span.setAttribute(key: "swarm.iterations.count", value: result.iterationCount)
        span.setAttribute(key: "swarm.tool.calls.count", value: result.toolCalls.count)
        span.setAttribute(key: "swarm.tool.results.count", value: result.toolResults.count)
        OpenTelemetryAttributes.applyUsage(result.tokenUsage, to: span)
    }

    func apply(response: AgentResponse, to span: any SpanBase) {
        span.setAttribute(key: "swarm.response.id", value: response.responseId)
        span.setAttribute(key: "swarm.response.output_length", value: response.output.count)
        span.setAttribute(key: "swarm.iterations.count", value: response.iterationCount)
        span.setAttribute(key: "swarm.tool.calls.count", value: response.toolCalls.count)
        OpenTelemetryAttributes.applyUsage(response.usage, to: span)
    }
}

public extension AgentRuntime {
    /// Wraps this agent so each user turn emits one parent OpenTelemetry span and
    /// all resolved LLM providers emit child GenAI spans.
    func instrumentedWithOpenTelemetry(
        tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: "swarm.agent",
            instrumentationVersion: nil
        ),
        llmTracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: "swarm.llm",
            instrumentationVersion: nil
        ),
        spanName: String? = nil,
        captureContent: Bool = false
  ) -> some AgentRuntime {
        OpenTelemetryAgentRuntime(
            self,
            tracer: tracer,
            llmTracer: llmTracer,
            spanName: spanName,
            captureContent: captureContent
        )
    }
}
#endif
