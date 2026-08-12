import Foundation
@testable import Swarm

public actor MockAgentRuntime: AgentRuntime {
    public nonisolated let tools: [any AnyJSONTool]
    public nonisolated let instructions: String
    public nonisolated let configuration: AgentConfiguration
    public nonisolated let memory: (any Memory)?
    public nonisolated let inferenceProvider: (any InferenceProvider)?
    public nonisolated let tracer: (any Tracer)?
    public nonisolated let handoffs: [AnyHandoffConfiguration]
    public nonisolated let inputGuardrails: [any InputGuardrail]
    public nonisolated let outputGuardrails: [any OutputGuardrail]

    private let response: String?
    private let streamTokens: [String]
    private let responseFactory: (@Sendable () -> String)?
    private let delay: Duration
    private var cancelled = false

    public init(
        response: String = "",
        streamTokens: [String] = [],
        responseFactory: (@Sendable () -> String)? = nil,
        delay: Duration = .zero,
        tools: [any AnyJSONTool] = [],
        instructions: String = "Mock agent",
        configuration: AgentConfiguration = .default,
        memory: (any Memory)? = nil,
        inferenceProvider: (any InferenceProvider)? = nil,
        tracer: (any Tracer)? = nil,
        handoffs: [AnyHandoffConfiguration] = [],
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = []
    ) {
        self.response = response
        self.streamTokens = streamTokens
        self.responseFactory = responseFactory
        self.delay = delay
        self.tools = tools
        self.instructions = instructions
        self.configuration = configuration
        self.memory = memory
        self.inferenceProvider = inferenceProvider
        self.tracer = tracer
        self.handoffs = handoffs
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
    }

    public func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        if delay > .zero {
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                cancelled = true
                throw CancellationError()
            }
        }
        if Task.isCancelled {
            cancelled = true
            throw CancellationError()
        }
        if cancelled {
            throw AgentError.cancelled
        }

        await observer?.onAgentStart(context: nil, agent: self, input: input)

        let output = if let responseFactory {
            responseFactory()
        } else {
            response ?? ""
        }

        let result = AgentResult(output: output)
        await observer?.onAgentEnd(context: nil, agent: self, result: result)
        return result
    }

    public nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            if self.streamTokens.isEmpty {
                continuation.yield(.lifecycle(.completed(result: AgentResult(output: self.response ?? ""))))
                continuation.finish()
                return
            }

            var aggregate = ""
            for token in self.streamTokens {
                aggregate += token
                continuation.yield(.output(.token(token)))
            }

            continuation.yield(.lifecycle(.completed(result: AgentResult(output: aggregate))))
            continuation.finish()
        }
    }

    public func cancel() async {
        cancelled = true
    }

    public var isCancelled: Bool {
        get async { cancelled }
    }
}
