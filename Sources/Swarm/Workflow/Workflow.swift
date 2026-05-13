import Foundation

/// Fluent multi-agent workflow composition API.
///
/// Use `Workflow` to compose multi-agent execution pipelines with sequential,
/// parallel, routed, and repeating steps. Workflows provide a fluent, composable
/// interface for orchestrating complex multi-agent interactions.
///
/// ## Sequential Composition
///
/// Chain agents to run one after another, where each agent's output becomes
/// the next agent's input:
///
/// ```swift
/// let result = try await Workflow()
///     .step(researchAgent)
///     .step(writeAgent)
///     .run("Research topic and write summary")
/// ```
///
/// ## Parallel Composition
///
/// Run multiple agents concurrently and merge their results:
///
/// ```swift
/// let result = try await Workflow()
///     .parallel([bullAgent, bearAgent], merge: .structured)
///     .run("Analyze market sentiment")
/// ```
///
/// ## Dynamic Routing
///
/// Route to different agents based on input content:
///
/// ```swift
/// let result = try await Workflow()
///     .route { input in
///         input.contains("weather") ? weatherAgent : generalAgent
///     }
///     .run("What's the weather?")
/// ```
///
/// ## Repeating Workflows
///
/// Repeat execution until a condition is met:
///
/// ```swift
/// let result = try await Workflow()
///     .step(iterativeRefiner)
///     .repeatUntil(maxIterations: 10) { result in
///         result.output.contains("FINAL") || result.iterationCount >= 5
///     }
///     .run("Improve this text")
/// ```
///
/// ## Observing Execution
///
/// Monitor workflow progress with an observer:
///
/// ```swift
/// let result = try await Workflow()
///     .step(agent)
///     .observedBy(loggingObserver)
///     .run("Task input")
/// ```
///
/// ## Topics
///
/// ### Creating Workflows
/// - ``init()``
/// - ``step(_:)``
///
/// ### Parallel Execution
/// - ``parallel(_:merge:)``
/// - ``MergeStrategy``
///
/// ### Control Flow
/// - ``route(_:)``
/// - ``repeatUntil(maxIterations:_:)``
/// - ``timeout(_:)``
///
/// ### Execution
/// - ``run(_:)``
/// - ``stream(_:)``
/// - ``observed(by:)``
///
/// ### Durable Execution
/// - ``durable``
public struct Workflow: Sendable {
    struct OpaqueBehaviorSignature: Sendable, Equatable {
        let value: String

        init(kind: String, explicit: String?, fileID: StaticString, line: UInt) {
            let trimmed = explicit?.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = if let trimmed, !trimmed.isEmpty {
                "explicit:\(workflowSignatureComponent(trimmed))"
            } else {
                "source:\(workflowSignatureComponent("\(fileID):\(line)"))"
            }
            value = "\(kind):\(identity)"
        }
    }

    enum Step: Sendable {
        case single(any AgentRuntime)
        case parallel([any AgentRuntime], merge: MergeStrategy, mergeBehaviorSignature: OpaqueBehaviorSignature?)
        case route(OpaqueBehaviorSignature, @Sendable (String) -> (any AgentRuntime)?)
        case fallback(primary: any AgentRuntime, backup: any AgentRuntime, retries: Int)
    }

    /// Strategy for merging results from parallel agent execution.
    ///
    /// When multiple agents run in parallel using ``Workflow/parallel(_:merge:)``,
    /// their individual results must be combined into a single output that
    /// downstream steps can process. Choose a strategy based on how you need
    /// to consume the merged results.
    ///
    /// ## Topics
    ///
    /// ### Merge Strategies
    /// - ``structured``
    /// - ``indexed``
    /// - ``first``
    /// - ``custom(_:)``
    public enum MergeStrategy: Sendable {
        /// Merges results into a JSON object: `{"0": "output0", "1": "output1", ...}`.
        ///
        /// Use this strategy when downstream agents or tools need machine-parseable
        /// parallel output. The JSON format allows structured access to each agent's
        /// result by index.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let result = try await Workflow()
        ///     .parallel([agentA, agentB], merge: .structured)
        ///     .run("Task")
        /// // result.output: {"0": "Agent A result", "1": "Agent B result"}
        /// ```
        case structured

        /// Merges results as a numbered list: `[0]: output0\n[1]: output1\n...`.
        ///
        /// Use this strategy for human-readable output that doesn't require
        /// JSON parsing. Both humans and LLMs can easily read this format.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let result = try await Workflow()
        ///     .parallel([agentA, agentB], merge: .indexed)
        ///     .run("Task")
        /// // result.output:
        /// // [0]: Agent A result
        /// // [1]: Agent B result
        /// ```
        case indexed

        /// Returns the output of the first agent to complete.
        ///
        /// Use this strategy when you only need one result and want the fastest
        /// response. Note: All agents still run to completion, but only the
        /// first completed result is used.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let result = try await Workflow()
        ///     .parallel([fastAgent, slowAgent], merge: .first)
        ///     .run("Task")
        /// // result.output contains output from whichever agent finished first
        /// ```
        case first

        /// Applies a custom merge function to combine all parallel results.
        ///
        /// Use this strategy when you need specialized merging logic, such as
        /// averaging numeric results, concatenating with custom separators, or
        /// selecting based on result quality.
        ///
        /// - Parameter transform: A closure that receives an array of ``AgentResult``
        ///   values and returns a merged string.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let result = try await Workflow()
        ///     .parallel([agentA, agentB], merge: .custom { results in
        ///         results.map { "- \($0.output)" }.joined(separator: "\n")
        ///     })
        ///     .run("Task")
        /// ```
        case custom(@Sendable ([AgentResult]) -> String)
    }

    /// Creates a new empty workflow.
    ///
    /// Initialize a workflow and chain steps to build your execution pipeline.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let workflow = Workflow()
    ///     .step(agentA)
    ///     .step(agentB)
    ///
    /// let result = try await workflow.run("Input")
    /// ```
    public init() {}

    /// Adds a sequential step to the workflow.
    ///
    /// The agent will execute when this step is reached, receiving the output
    /// from the previous step (or the initial input if this is the first step).
    /// The agent's output becomes the input for the next step.
    ///
    /// - Parameter agent: The agent to execute at this step.
    /// - Returns: A new workflow with the added step.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await Workflow()
    ///     .step(researchAgent)      // Researches the topic
    ///     .step(outlineAgent)       // Creates outline from research
    ///     .step(writerAgent)        // Writes from outline
    ///     .run("Write about Swift concurrency")
    /// ```
    public func step(_ agent: some AgentRuntime) -> Workflow {
        var copy = self
        copy.steps.append(.single(agent))
        return copy
    }

    /// Adds a parallel execution step to the workflow.
    ///
    /// All agents in the array execute concurrently. Their results are merged
    /// according to the specified ``MergeStrategy``. The merged output becomes
    /// the input for the next step.
    ///
    /// - Parameters:
    ///   - agents: An array of agents to execute in parallel.
    ///   - merge: The strategy for combining results. Defaults to `.structured`.
    ///   - customMergeSignature: Optional stable durable identity to change when `.custom` merge behavior changes.
    /// - Returns: A new workflow with the added parallel step.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Analyze from multiple perspectives
    /// let result = try await Workflow()
    ///     .parallel(
    ///         [technicalAgent, businessAgent, userAgent],
    ///         merge: .indexed
    ///     )
    ///     .step(synthesizerAgent)
    ///     .run("Evaluate new feature proposal")
    /// ```
    public func parallel(
        _ agents: [any AgentRuntime],
        merge: MergeStrategy = .structured,
        customMergeSignature: String? = nil,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Workflow {
        var copy = self
        let mergeBehaviorSignature: OpaqueBehaviorSignature?
        if case .custom = merge {
            mergeBehaviorSignature = OpaqueBehaviorSignature(
                kind: "customMerge",
                explicit: customMergeSignature,
                fileID: fileID,
                line: line
            )
        } else {
            mergeBehaviorSignature = nil
        }
        copy.steps.append(.parallel(
            agents,
            merge: merge,
            mergeBehaviorSignature: mergeBehaviorSignature
        ))
        return copy
    }

    /// Adds a dynamic routing step to the workflow.
    ///
    /// The routing closure is called with the current input to determine which
    /// agent should execute next. Return `nil` to throw a routing error.
    ///
    /// - Parameter condition: A closure that receives the current input string
    ///   and returns the agent to execute, or `nil` if routing fails.
    /// - Parameter signature: Optional stable durable identity to change when route behavior changes.
    /// - Returns: A new workflow with the added routing step.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await Workflow()
    ///     .route { input in
    ///         if input.contains("code") {
    ///             return codeAgent
    ///         } else if input.contains("design") {
    ///             return designAgent
    ///         } else {
    ///             return generalAgent
    ///         }
    ///     }
    ///     .run("Review this code snippet")
    /// ```
    public func route(
        _ condition: @escaping @Sendable (String) -> (any AgentRuntime)?,
        signature: String? = nil,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Workflow {
        var copy = self
        copy.steps.append(.route(
            OpaqueBehaviorSignature(kind: "route", explicit: signature, fileID: fileID, line: line),
            condition
        ))
        return copy
    }

    /// Adds a dynamic routing step with an explicit durable identity for the routing behavior.
    public func route(
        signature: String,
        fileID: StaticString = #fileID,
        line: UInt = #line,
        _ condition: @escaping @Sendable (String) -> (any AgentRuntime)?
    ) -> Workflow {
        route(condition, signature: signature, fileID: fileID, line: line)
    }

    /// Configures the workflow to repeat until a condition is met.
    ///
    /// The workflow will execute repeatedly, passing the previous result's output
    /// as the next iteration's input, until the condition returns `true` or the
    /// maximum iteration count is reached.
    ///
    /// - Parameters:
    ///   - maxIterations: The maximum number of iterations before stopping.
    ///     Defaults to 100.
    ///   - condition: A closure that receives the ``AgentResult`` from each
    ///     iteration and returns `true` when the workflow should stop.
    ///   - signature: Optional stable durable identity to change when repeat predicate behavior changes.
    /// - Returns: A new workflow configured with the repeat condition.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Iteratively refine until quality threshold is met
    /// let result = try await Workflow()
    ///     .step(refinerAgent)
    ///     .repeatUntil(maxIterations: 10) { result in
    ///         // Stop if output contains "FINAL" or we've iterated 5+ times
    ///         result.output.contains("FINAL") || result.iterationCount >= 5
    ///     }
    ///     .run("Write a compelling headline")
    /// ```
    public func repeatUntil(
        maxIterations: Int = 100,
        _ condition: @escaping @Sendable (AgentResult) -> Bool,
        signature: String? = nil,
        fileID: StaticString = #fileID,
        line: UInt = #line
    ) -> Workflow {
        var copy = self
        copy.repeatCondition = condition
        copy.repeatConditionSignature = OpaqueBehaviorSignature(
            kind: "repeat",
            explicit: signature,
            fileID: fileID,
            line: line
        )
        copy.maxRepeatIterations = maxIterations
        return copy
    }

    /// Configures repetition with an explicit durable identity for the repeat predicate.
    public func repeatUntil(
        maxIterations: Int = 100,
        signature: String,
        fileID: StaticString = #fileID,
        line: UInt = #line,
        _ condition: @escaping @Sendable (AgentResult) -> Bool
    ) -> Workflow {
        repeatUntil(maxIterations: maxIterations, condition, signature: signature, fileID: fileID, line: line)
    }

    /// Sets a timeout for workflow execution.
    ///
    /// If the workflow doesn't complete within the specified duration, it will
    /// throw an ``AgentError/timeout(duration:)`` error.
    ///
    /// - Parameter duration: The maximum time allowed for execution.
    /// - Returns: A new workflow with the timeout configured.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await Workflow()
    ///     .step(potentiallySlowAgent)
    ///     .timeout(.seconds(30))
    ///     .run("Complex analysis task")
    /// ```
    public func timeout(_ duration: Duration) -> Workflow {
        var copy = self
        copy.timeoutDuration = duration
        return copy
    }

    /// Adds an observer to monitor workflow execution.
    ///
    /// The observer receives events during workflow execution, allowing you to
    /// log progress, track metrics, or implement custom monitoring.
    ///
    /// - Parameter observer: An ``AgentObserver`` conforming type that will
    ///   receive execution events.
    /// - Returns: A new workflow with the observer attached.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let loggingObserver = CustomLoggingObserver()
    ///
    /// let result = try await Workflow()
    ///     .step(agentA)
    ///     .step(agentB)
    ///     .observed(by: loggingObserver)
    ///     .run("Task input")
    /// ```
    public func observed(by observer: some AgentObserver) -> Workflow {
        var copy = self
        copy.observer = observer
        return copy
    }

    /// Executes the workflow with the given input.
    ///
    /// Runs all steps in sequence, applying routing, parallel execution, and
    /// repetition as configured. Throws an error if any step fails or if the
    /// timeout is exceeded.
    ///
    /// - Parameter input: The initial input string for the workflow.
    /// - Returns: The final ``AgentResult`` after all steps complete.
    /// - Throws: An error if execution fails, times out, or routing fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let workflow = Workflow()
    ///     .step(researchAgent)
    ///     .step(writerAgent)
    ///
    /// let result = try await workflow.run("Write about Swift macros")
    /// print(result.output)
    /// ```
    public func run(_ input: String) async throws -> AgentResult {
        try await executeWithTimeout {
            try await executeDirect(input: input)
        }
    }

    /// Executes the workflow and streams execution events.
    ///
    /// Similar to ``run(_:)`` but returns an async stream of ``AgentEvent``
    /// values that allows real-time observation of the execution progress.
    ///
    /// - Parameter input: The initial input string for the workflow.
    /// - Returns: An `AsyncThrowingStream` of ``AgentEvent`` values.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = Workflow()
    ///     .step(agentA)
    ///     .step(agentB)
    ///     .stream("Task input")
    ///
    /// for try await event in stream {
    ///     switch event {
    ///     case .lifecycle(.started(input: let input)):
    ///         print("Workflow started: \(input)")
    ///     case .lifecycle(.completed(let result)):
    ///         print("Completed: \(result.output)")
    ///     case .lifecycle(.failed(let error)):
    ///         print("Failed: \(error)")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            do {
                let result = try await run(input)
                continuation.yield(.lifecycle(.completed(result: result)))
                continuation.finish()
            } catch let error as AgentError {
                continuation.yield(.lifecycle(.failed(error: error)))
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    struct AdvancedConfiguration: Sendable {
        var checkpoint: CheckpointConfiguration?
        var checkpointing: WorkflowCheckpointing?
    }

    struct CheckpointConfiguration: Sendable {
        let id: String
        let policy: Durable.CheckpointPolicy
    }

    var steps: [Step] = []
    var repeatCondition: (@Sendable (AgentResult) -> Bool)?
    var repeatConditionSignature: OpaqueBehaviorSignature?
    var maxRepeatIterations = 100
    var timeoutDuration: Duration?
    var observer: (any AgentObserver)?
    var advancedConfiguration = AdvancedConfiguration()

    func executeWithTimeout(
        _ operation: @escaping @Sendable () async throws -> AgentResult
    ) async throws -> AgentResult {
        if let timeoutDuration {
            let coordinator = WorkflowTimedOperationCoordinator<AgentResult>()
            return try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        coordinator.install(continuation: continuation)

                        let operationTask = Task {
                            do {
                                coordinator.finish(returning: try await operation())
                            } catch {
                                coordinator.finish(throwing: error)
                            }
                        }
                        coordinator.setOperationTask(operationTask)

                        let timeoutTask = Task {
                            do {
                                try await Task.sleep(for: timeoutDuration)
                                operationTask.cancel()
                                coordinator.finish(throwing: AgentError.timeout(duration: timeoutDuration))
                            } catch is CancellationError {
                                return
                            } catch {
                                coordinator.finish(throwing: error)
                            }
                        }
                        coordinator.setTimeoutTask(timeoutTask)
                    }
                },
                onCancel: {
                    coordinator.cancelPending(with: CancellationError())
                }
            )
        }
        return try await operation()
    }

    func executeDirect(input: String) async throws -> AgentResult {
        if let repeatCondition {
            var lastResult: AgentResult?

            for _ in 0 ..< maxRepeatIterations {
                let currentInput = lastResult?.output ?? input
                lastResult = try await runSinglePass(input: currentInput)
                if repeatCondition(lastResult!) {
                    return lastResult!
                }
            }

            return lastResult ?? AgentResult(output: "")
        }

        return try await runSinglePass(input: input)
    }

    func runSinglePass(input: String) async throws -> AgentResult {
        var currentInput = input
        var lastResult = AgentResult(output: "")

        for step in steps {
            lastResult = try await execute(step: step, withInput: currentInput)
            currentInput = lastResult.output
        }

        return lastResult
    }

    func execute(step: Step, withInput input: String) async throws -> AgentResult {
        switch step {
        case .single(let agent):
            return try await agent.run(input, session: nil, observer: observer)

        case .parallel(let agents, let merge, _):
            let inputSnapshot = input
            let completedResults = try await withThrowingTaskGroup(
                of: (Int, AgentResult).self,
                returning: [(Int, AgentResult)].self
            ) { group in
                for (index, agent) in agents.enumerated() {
                    let observer = observer
                    group.addTask {
                        (index, try await agent.run(inputSnapshot, session: nil, observer: observer))
                    }
                }

                var collected: [(Int, AgentResult)] = []
                for try await result in group {
                    collected.append(result)
                }
                return collected
            }

            let results = switch merge {
            case .first:
                completedResults.map(\.1)
            default:
                completedResults.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let mergedOutput = mergeResults(results, strategy: merge)
            return AgentResult(output: mergedOutput)

        case .route(_, let route):
            guard let selected = route(input) else {
                throw WorkflowError.routingFailed(reason: "Workflow route did not match any agent for input")
            }
            return try await selected.run(input, session: nil, observer: observer)

        case .fallback(let primary, let backup, let retries):
            var lastError: (any Error)?
            let attempts = max(1, retries + 1)

            for _ in 0 ..< attempts {
                do {
                    return try await primary.run(input, session: nil, observer: observer)
                } catch {
                    lastError = error
                }
            }

            let fallbackResult = try await backup.run(input, session: nil, observer: observer)
            var metadata = fallbackResult.metadata
            metadata["workflow.fallback.used"] = .bool(true)
            if let lastError {
                metadata["workflow.fallback.error"] = .string(String(describing: lastError))
            }
            return AgentResult(
                output: fallbackResult.output,
                toolCalls: fallbackResult.toolCalls,
                toolResults: fallbackResult.toolResults,
                iterationCount: fallbackResult.iterationCount,
                duration: fallbackResult.duration,
                tokenUsage: fallbackResult.tokenUsage,
                metadata: metadata
            )
        }
    }

    func mergeResults(_ results: [AgentResult], strategy: MergeStrategy) -> String {
        switch strategy {
        case .structured:
            // Produce a JSON object keyed by index for machine-parseable output.
            let dict = results.enumerated().reduce(into: [String: String]()) { acc, pair in
                acc["\(pair.offset)"] = pair.element.output
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
               let json = String(data: data, encoding: .utf8)
            {
                return json
            }
            // Fallback: indexed format if JSON serialization fails (non-UTF-8 content).
            fallthrough
        case .indexed:
            return results.enumerated().map { idx, result in
                "[\(idx)]: \(result.output)"
            }.joined(separator: "\n")
        case .first:
            return results.first?.output ?? ""
        case .custom(let transform):
            return transform(results)
        }
    }

    var workflowSignature: String {
        let parts: [String] = steps.enumerated().map { index, step in
            switch step {
            case .single(let agent):
                return "\(index):single:\(workflowAgentSignature(agent))"
            case .parallel(let agents, let merge, let mergeBehaviorSignature):
                let agentsSignature = agents.map(workflowAgentSignature).joined(separator: ",")
                let mergeSignature: String
                switch merge {
                case .structured:
                    mergeSignature = "structured"
                case .indexed:
                    mergeSignature = "indexed"
                case .first:
                    mergeSignature = "first"
                case .custom:
                    mergeSignature = mergeBehaviorSignature?.value ?? "custom:opaque"
                }
                return "\(index):parallel:\(agentsSignature):\(mergeSignature)"
            case .route(let signature, _):
                return "\(index):route:\(signature.value)"
            case .fallback(let primary, let backup, let retries):
                return "\(index):fallback:\(workflowAgentSignature(primary)):\(workflowAgentSignature(backup)):\(retries)"
            }
        }

        let repeatSignature = if repeatCondition != nil {
            "repeat:true:\(maxRepeatIterations):\(repeatConditionSignature?.value ?? "repeat:opaque")"
        } else {
            "repeat:false:\(maxRepeatIterations)"
        }
        return (["workflowSignature:v2"] + parts + [repeatSignature]).joined(separator: "|")
    }
}

private func workflowAgentSignature(_ agent: any AgentRuntime) -> String {
    [
        "type=\(workflowSignatureComponent(String(reflecting: type(of: agent))))",
        "name=\(workflowSignatureComponent(agent.name))",
        "instructions=\(workflowSignatureComponent(agent.instructions))",
        "configuration=\(workflowConfigurationSignature(agent.configuration))",
        "tools=\(agent.tools.map(workflowToolSignature).joined(separator: ","))",
        "memory=\(workflowOptionalTypeSignature(agent.memory))",
        "provider=\(workflowInferenceProviderSignature(agent.inferenceProvider))",
        "tracer=\(workflowOptionalTypeSignature(agent.tracer))",
        "inputGuardrails=\(agent.inputGuardrails.map(workflowGuardrailSignature).joined(separator: ","))",
        "outputGuardrails=\(agent.outputGuardrails.map(workflowGuardrailSignature).joined(separator: ","))",
        "handoffs=\(agent.handoffs.map(workflowHandoffSignature).joined(separator: ","))",
    ].joined(separator: ";")
}

private func workflowConfigurationSignature(_ configuration: AgentConfiguration) -> String {
    let timeout = configuration.timeout.components
    let parts = [
        "name=\(workflowSignatureComponent(configuration.name))",
        "maxIterations=\(configuration.maxIterations)",
        "timeout=\(timeout.seconds):\(timeout.attoseconds)",
        "temperature=\(configuration.temperature)",
        "maxTokens=\(configuration.maxTokens.map(String.init) ?? "nil")",
        "stopSequences=\(workflowSignatureComponent(String(reflecting: configuration.stopSequences)))",
        "modelSettings=\(workflowSignatureComponent(String(reflecting: configuration.modelSettings)))",
        "contextProfile=\(workflowSignatureComponent(String(reflecting: configuration.contextProfile)))",
        "contextMode=\(workflowSignatureComponent(String(reflecting: configuration.contextMode)))",
        "inferencePolicy=\(workflowSignatureComponent(String(reflecting: configuration.inferencePolicy)))",
        "enableStreaming=\(configuration.enableStreaming)",
        "includeToolCallDetails=\(configuration.includeToolCallDetails)",
        "stopOnToolError=\(configuration.stopOnToolError)",
        "includeReasoning=\(configuration.includeReasoning)",
        "sessionHistoryLimit=\(configuration.sessionHistoryLimit.map(String.init) ?? "nil")",
        "parallelToolCalls=\(configuration.parallelToolCalls)",
        "previousResponseId=\(workflowSignatureComponent(configuration.previousResponseId ?? "nil"))",
        "autoPreviousResponseId=\(configuration.autoPreviousResponseId)",
        "defaultTracingEnabled=\(configuration.defaultTracingEnabled)",
        "graphRunOptionsOverride=\(workflowSignatureComponent(String(reflecting: configuration.graphRunOptionsOverride)))",
    ]
    return parts.joined(separator: ";")
}

private func workflowToolSignature(_ tool: any AnyJSONTool) -> String {
    [
        "type=\(workflowSignatureComponent(String(reflecting: type(of: tool))))",
        "name=\(workflowSignatureComponent(tool.name))",
        "description=\(workflowSignatureComponent(tool.description))",
        "parameters=\(workflowSignatureComponent(String(reflecting: tool.parameters)))",
        "semantics=\(workflowSignatureComponent(String(reflecting: tool.executionSemantics)))",
        "enabled=\(tool.isEnabled)",
        "inputGuardrails=\(tool.inputGuardrails.map(workflowToolInputGuardrailSignature).joined(separator: ","))",
        "outputGuardrails=\(tool.outputGuardrails.map(workflowToolOutputGuardrailSignature).joined(separator: ","))",
    ].joined(separator: ";")
}

private func workflowHandoffSignature(_ handoff: AnyHandoffConfiguration) -> String {
    [
        "target=\(workflowAgentSignature(handoff.targetAgent))",
        "toolName=\(workflowSignatureComponent(handoff.toolNameOverride ?? "nil"))",
        "toolDescription=\(workflowSignatureComponent(handoff.toolDescription ?? "nil"))",
        "onTransfer=\(handoff.onTransfer == nil ? "nil" : "present")",
        "transform=\(handoff.transform == nil ? "nil" : "present")",
        "when=\(handoff.when == nil ? "nil" : "present")",
        "nestHistory=\(handoff.nestHandoffHistory)",
    ].joined(separator: ";")
}

private func workflowGuardrailSignature(_ guardrail: any Guardrail) -> String {
    [
        "type=\(workflowSignatureComponent(String(reflecting: type(of: guardrail))))",
        "name=\(workflowSignatureComponent(guardrail.name))",
    ].joined(separator: ";")
}

private func workflowToolInputGuardrailSignature(_ guardrail: any ToolInputGuardrail) -> String {
    [
        "type=\(workflowSignatureComponent(String(reflecting: type(of: guardrail))))",
        "name=\(workflowSignatureComponent(guardrail.name))",
    ].joined(separator: ";")
}

private func workflowToolOutputGuardrailSignature(_ guardrail: any ToolOutputGuardrail) -> String {
    [
        "type=\(workflowSignatureComponent(String(reflecting: type(of: guardrail))))",
        "name=\(workflowSignatureComponent(guardrail.name))",
    ].joined(separator: ";")
}

private func workflowInferenceProviderSignature(_ provider: (any InferenceProvider)?) -> String {
    guard let provider else {
        return "nil"
    }
    let capabilities = InferenceProviderCapabilities.resolved(for: provider)
    return [
        "type=\(workflowSignatureComponent(String(reflecting: type(of: provider))))",
        "capabilities=\(capabilities.rawValue)",
    ].joined(separator: ";")
}

private func workflowOptionalTypeSignature(_ value: Any?) -> String {
    guard let value else {
        return "nil"
    }
    return workflowSignatureComponent(String(reflecting: type(of: value)))
}

private func workflowSignatureComponent(_ value: String) -> String {
    "\(value.utf8.count)#\(value)"
}

private final class WorkflowTimedOperationCoordinator<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false

    func install(continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        operationTask = task
        lock.unlock()
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        timeoutTask = task
        lock.unlock()
    }

    func finish(returning value: T) {
        complete { continuation in
            continuation.resume(returning: value)
        }
    }

    func finish(throwing error: Error) {
        complete { continuation in
            continuation.resume(throwing: error)
        }
    }

    func cancelPending(with error: Error) {
        let pendingState = takePendingState()
        pendingState.operationTask?.cancel()
        pendingState.timeoutTask?.cancel()
        pendingState.continuation?.resume(throwing: error)
    }

    private func complete(_ resume: (CheckedContinuation<T, Error>) -> Void) {
        let pendingState = takePendingState()
        pendingState.operationTask?.cancel()
        pendingState.timeoutTask?.cancel()
        guard let continuation = pendingState.continuation else { return }
        resume(continuation)
    }

    private func takePendingState() -> (
        continuation: CheckedContinuation<T, Error>?,
        operationTask: Task<Void, Never>?,
        timeoutTask: Task<Void, Never>?
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard completed == false else {
            return (nil, nil, nil)
        }

        completed = true
        let pendingContinuation = continuation
        let pendingOperationTask = operationTask
        let pendingTimeoutTask = timeoutTask
        continuation = nil
        operationTask = nil
        timeoutTask = nil
        return (pendingContinuation, pendingOperationTask, pendingTimeoutTask)
    }
}
