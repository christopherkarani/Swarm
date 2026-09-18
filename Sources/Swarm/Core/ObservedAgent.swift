import Foundation

/// Internal wrapper that attaches an observer to an existing agent runtime.
struct ObservedAgent<Wrapped: AgentRuntime>: AgentRuntime {
    let wrapped: Wrapped
    let observer: any AgentObserver

    nonisolated var name: String { wrapped.name }
    nonisolated var tools: [any AnyJSONTool] { wrapped.tools }
    nonisolated var instructions: String { wrapped.instructions }
    nonisolated var configuration: AgentConfiguration { wrapped.configuration }
    nonisolated var memory: (any Memory)? { wrapped.memory }
    nonisolated var inferenceProvider: (any InferenceProvider)? { wrapped.inferenceProvider }
    nonisolated var tracer: (any Tracer)? { wrapped.tracer }
    nonisolated var handoffs: [AnyHandoffConfiguration] { wrapped.handoffs }
    nonisolated var inputGuardrails: [any InputGuardrail] { wrapped.inputGuardrails }
    nonisolated var outputGuardrails: [any OutputGuardrail] { wrapped.outputGuardrails }

    func cancel() async {
        await wrapped.cancel()
    }

    func run(_ input: String, session: (any Session)?, observer additionalObserver: (any AgentObserver)?) async throws -> AgentResult {
        try await wrapped.run(input, session: session, observer: combined(with: additionalObserver))
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer additionalObserver: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        wrapped.stream(input, session: session, observer: combined(with: additionalObserver))
    }

    func runWithResponse(
        _ input: String,
        session: (any Session)?,
        observer additionalObserver: (any AgentObserver)?
    ) async throws -> AgentResponse {
        try await wrapped.runWithResponse(input, session: session, observer: combined(with: additionalObserver))
    }

    func handleHandoff(
        _ request: HandoffRequest,
        context: AgentContext,
        session: (any Session)?,
        observer additionalObserver: (any AgentObserver)?
    ) async throws -> AgentResult {
        try await wrapped.handleHandoff(
            request,
            context: context,
            session: session,
            observer: combined(with: additionalObserver)
        )
    }

    private nonisolated func combined(with additionalObserver: (any AgentObserver)?) -> any AgentObserver {
        guard let additionalObserver else {
            return observer
        }
        return CompositeObserver(observers: [observer, additionalObserver])
    }
}

public extension AgentRuntime {
    /// Wraps this agent with an observer that receives lifecycle callbacks.
    func observed(by observer: some AgentObserver) -> some AgentRuntime {
        ObservedAgent(wrapped: self, observer: observer)
    }
}
