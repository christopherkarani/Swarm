// GuardrailRunner.swift
// Swarm Framework
//
// Thread-safe guardrail execution orchestrator.
// Provides sequential and parallel execution modes with tripwire handling.

import Foundation

// MARK: - GuardrailRunnerConfiguration

/// Configuration for guardrail runner behavior.
///
/// `GuardrailRunnerConfiguration` controls how the runner executes guardrails:
/// - Sequential vs parallel execution
/// - Stop-on-first-tripwire vs run-all behavior
/// - Per-guardrail timeout enforcement
///
/// Use the static factory properties for common configurations:
/// ```swift
/// // Default: sequential, stop on first tripwire
/// let runner = GuardrailRunner(configuration: .default)
///
/// // Parallel execution, stop on first tripwire
/// let fastRunner = GuardrailRunner(configuration: .parallel)
///
/// // Custom: parallel, run all guardrails
/// let customRunner = GuardrailRunner(
///     configuration: GuardrailRunnerConfiguration(
///         runInParallel: true,
///         stopOnFirstTripwire: false
///     )
/// )
/// ```
public struct GuardrailRunnerConfiguration: Sendable, Equatable {
    // MARK: - Static Configurations

    /// Default configuration: sequential execution, stop on first tripwire.
    public static let `default` = GuardrailRunnerConfiguration()

    /// Parallel configuration: concurrent execution, stop on first tripwire.
    public static let parallel = GuardrailRunnerConfiguration(runInParallel: true)

    /// Whether to run guardrails in parallel using TaskGroup.
    /// - `false`: Run guardrails sequentially in order (default)
    /// - `true`: Run guardrails concurrently
    public let runInParallel: Bool

    /// Whether to stop immediately when a tripwire is triggered.
    /// - `true`: Stop and throw error on first tripwire (default)
    /// - `false`: Continue all guardrails, throw at end if any tripwired
    public let stopOnFirstTripwire: Bool

    /// Maximum duration allowed for each guardrail validation.
    ///
    /// A `nil` value disables timeout enforcement. The default keeps guardrails
    /// from stalling agent execution indefinitely.
    public let timeout: Duration?

    // MARK: - Initialization

    /// Creates a guardrail runner configuration.
    ///
    /// - Parameters:
    ///   - runInParallel: Whether to run guardrails concurrently. Default: false
    ///     - `false`: Guardrails run sequentially, maintaining order and dependencies
    ///     - `true`: Guardrails run concurrently for better performance (order not guaranteed)
    ///   - stopOnFirstTripwire: Whether to stop on first tripwire. Default: true
    ///     - `true`: Stop immediately when any guardrail triggers (faster, less information)
    ///     - `false`: Run all guardrails even after tripwires (slower, more diagnostic info)
    ///   - timeout: Per-guardrail timeout. Default: 30 seconds. Pass `nil` to disable.
    ///
    /// ## Performance Notes
    ///
    /// - Parallel execution is faster but results may arrive out of order
    /// - Stop-on-first is recommended for production (fail-fast)
    /// - Run-all is useful for testing and diagnostics
    public init(
        runInParallel: Bool = false,
        stopOnFirstTripwire: Bool = true,
        timeout: Duration? = .seconds(30)
    ) {
        self.runInParallel = runInParallel
        self.stopOnFirstTripwire = stopOnFirstTripwire
        self.timeout = timeout
    }
}

// MARK: - GuardrailExecutionResult

/// Result of a single guardrail execution.
///
/// `GuardrailExecutionResult` tracks which guardrail executed and its result.
/// This is used to collect results when running multiple guardrails.
///
/// Example:
/// ```swift
/// let results = try await runner.runInputGuardrails(
///     guardrails,
///     input: "user input",
///     context: nil
/// )
///
/// for executionResult in results {
///     print("\(executionResult.guardrailName): \(executionResult.result.tripwireTriggered)")
/// }
/// ```
public struct GuardrailExecutionResult: Sendable, Equatable {
    /// The name of the guardrail that executed.
    public let guardrailName: String

    /// The result from the guardrail.
    public let result: GuardrailResult

    // MARK: - Convenience Properties

    /// Whether this execution triggered a tripwire.
    public var didTriggerTripwire: Bool {
        switch result {
        case .passed:
            false
        case .tripwire:
            true
        }
    }

    /// Whether this execution passed without triggering.
    public var passed: Bool {
        switch result {
        case .passed:
            true
        case .tripwire:
            false
        }
    }

    // MARK: - Initialization

    /// Creates a guardrail execution result.
    ///
    /// - Parameters:
    ///   - guardrailName: The name of the guardrail.
    ///   - result: The guardrail result.
    public init(guardrailName: String, result: GuardrailResult) {
        self.guardrailName = guardrailName
        self.result = result
    }
}

private struct GuardrailTimeoutError: Error, LocalizedError, Sendable {
    let guardrailName: String
    let timeout: Duration

    var errorDescription: String? {
        "Guardrail '\(guardrailName)' timed out after \(timeout)."
    }
}

// MARK: - GuardrailUnit

/// One normalized guardrail execution unit, independent of guardrail kind.
///
/// Kind-specific differences (how validation is invoked, which tripwire error
/// is constructed, what the observer receives) collapse into this unit so a
/// single sequential executor and a single parallel executor serve every
/// guardrail kind.
private struct GuardrailUnit: Sendable {
    /// The guardrail kind paired with the subject its tripwire errors reference.
    /// Modeling kind and subject as one value makes a mismatched pairing
    /// unrepresentable (e.g. an `.input` unit carrying a tool name).
    let subject: Subject

    /// Name of the guardrail itself, used in results and errors.
    let name: String

    /// Context forwarded to observer events.
    let observerContext: AgentContext?

    /// Runs this guardrail's validation once.
    let validate: @Sendable () async throws -> GuardrailResult

    /// Kind of guardrail being executed. Drives observer event payloads.
    var kind: GuardrailType {
        switch subject {
        case .input: .input
        case .output: .output
        case .toolInput: .toolInput
        case .toolOutput: .toolOutput
        }
    }

    /// Subject referenced by tripwire errors, tied to the guardrail kind:
    /// nothing for `.input`, the agent name for `.output`, and the tool name
    /// for `.toolInput`/`.toolOutput`.
    enum Subject: Sendable {
        case input
        case output(agentName: String)
        case toolInput(toolName: String)
        case toolOutput(toolName: String)
    }
}

// MARK: - GuardrailRunner

/// Actor for thread-safe guardrail execution.
///
/// `GuardrailRunner` orchestrates the execution of multiple guardrails,
/// providing configurable execution modes and error handling.
///
/// **Execution Modes:**
/// - **Sequential**: Run guardrails one-by-one in order
/// - **Parallel**: Run guardrails concurrently using TaskGroup
///
/// **Tripwire Handling:**
/// - **Stop on first**: Immediately throw when a tripwire is triggered
/// - **Run all**: Execute all guardrails, then throw if any tripwired
///
/// **Note:** Parallel mode executes guardrails concurrently and sorts completed
/// results back into input order before returning. Under stop-on-first-tripwire
/// semantics, the error thrown corresponds to whichever guardrail finished
/// first, which may differ from input order.
///
/// **Example:**
/// ```swift
/// let runner = GuardrailRunner()
///
/// let inputGuardrails = [
///     SensitiveDataGuardrail(),
///     ContentLengthGuardrail()
/// ]
///
/// do {
///     let results = try await runner.runInputGuardrails(
///         inputGuardrails,
///         input: "user input",
///         context: nil
///     )
///     // All guardrails passed
/// } catch let error as GuardrailError {
///     // Handle tripwire or execution error
/// }
/// ```
public actor GuardrailRunner {
    /// The configuration controlling execution behavior.
    public let configuration: GuardrailRunnerConfiguration

    /// Optional observer for emitting guardrail events.
    public let observer: (any AgentObserver)?

    // MARK: - Initialization

    /// Creates a guardrail runner with the specified configuration.
    ///
    /// - Parameters:
    ///   - configuration: The execution configuration. Default: .default
    ///   - observer: Optional observer for emitting guardrail events. Default: nil
    public init(configuration: GuardrailRunnerConfiguration = .default, observer: (any AgentObserver)? = nil) {
        self.configuration = configuration
        self.observer = observer
    }

    // MARK: - Private Helpers

    /// Emits a guardrail triggered event via observer if available.
    private func emitGuardrailEvent(
        guardrailName: String,
        guardrailType: GuardrailType,
        result: GuardrailResult,
        context: AgentContext?
    ) async {
        switch result {
        case .passed:
            return
        case .tripwire:
            await observer?.onGuardrailTriggered(
                context: context,
                guardrailName: guardrailName,
                guardrailType: guardrailType,
                result: result
            )
        }
    }

    /// Single tripwire error-construction table across all guardrail kinds.
    private static func tripwireError(
        subject: GuardrailUnit.Subject,
        guardrailName: String,
        result: GuardrailResult
    ) -> GuardrailError? {
        switch result {
        case .passed:
            nil
        case let .tripwire(message, outputInfo, _):
            switch subject {
            case .input:
                .inputTripwireTriggered(
                    guardrailName: guardrailName,
                    message: message,
                    outputInfo: outputInfo
                )
            case let .output(agentName):
                .outputTripwireTriggered(
                    guardrailName: guardrailName,
                    agentName: agentName,
                    message: message,
                    outputInfo: outputInfo
                )
            case let .toolInput(toolName):
                .toolInputTripwireTriggered(
                    guardrailName: guardrailName,
                    toolName: toolName,
                    message: message,
                    outputInfo: outputInfo
                )
            case let .toolOutput(toolName):
                .toolOutputTripwireTriggered(
                    guardrailName: guardrailName,
                    toolName: toolName,
                    message: message,
                    outputInfo: outputInfo
                )
            }
        }
    }

    private func validateWithTimeout<Result: Sendable>(
        guardrailName: String,
        operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        guard let timeout = configuration.timeout else {
            return try await operation()
        }

        // Parent cancellation is not wired into this race (matching the
        // original implementation): a cancelled caller parks until the
        // guardrail finishes or the timeout fires. Unlike the original
        // actor-isolated `Task {}` workers, the helper spawns unisolated
        // tasks, so guardrail operations and their timers no longer queue
        // behind other runner-actor work.
        return try await withTimeoutRace(
            timeout: timeout,
            cancelsOnParentCancellation: false,
            timeoutError: GuardrailTimeoutError(guardrailName: guardrailName, timeout: timeout)
        ) {
            try await operation()
        }
    }

    // MARK: - Input Guardrails

    /// Runs input guardrails on the provided input.
    ///
    /// Executes all input guardrails according to the runner's configuration.
    /// If a tripwire is triggered and `stopOnFirstTripwire` is true, throws
    /// immediately. Otherwise, collects all results and throws at the end if
    /// any guardrail tripwired.
    ///
    /// - Parameters:
    ///   - guardrails: The input guardrails to execute.
    ///   - input: The input string to validate.
    ///   - context: Optional agent context for validation.
    /// - Returns: Array of execution results from all guardrails.
    /// - Throws: `GuardrailError.inputTripwireTriggered` if a tripwire is triggered,
    ///           or `GuardrailError.executionFailed` if execution fails.
    public func runInputGuardrails(
        _ guardrails: [any InputGuardrail],
        input: String,
        context: AgentContext?
    ) async throws -> [GuardrailExecutionResult] {
        try await execute(guardrails.map { guardrail in
            GuardrailUnit(
                subject: .input,
                name: guardrail.name,
                observerContext: context,
                validate: { try await guardrail.validate(input, context: context) }
            )
        })
    }

    // MARK: - Output Guardrails

    /// Runs output guardrails on the provided output.
    ///
    /// Executes all output guardrails according to the runner's configuration.
    /// If a tripwire is triggered and `stopOnFirstTripwire` is true, throws
    /// immediately. Otherwise, collects all results and throws at the end if
    /// any guardrail tripwired.
    ///
    /// - Parameters:
    ///   - guardrails: The output guardrails to execute.
    ///   - output: The output string to validate.
    ///   - agent: The agent that produced the output.
    ///   - context: Optional agent context for validation.
    /// - Returns: Array of execution results from all guardrails.
    /// - Throws: `GuardrailError.outputTripwireTriggered` if a tripwire is triggered,
    ///           or `GuardrailError.executionFailed` if execution fails.
    public func runOutputGuardrails(
        _ guardrails: [any OutputGuardrail],
        output: String,
        agent: any AgentRuntime,
        context: AgentContext?
    ) async throws -> [GuardrailExecutionResult] {
        let agentName = agent.configuration.name
        return try await execute(guardrails.map { guardrail in
            GuardrailUnit(
                subject: .output(agentName: agentName),
                name: guardrail.name,
                observerContext: context,
                validate: { try await guardrail.validate(output, agent: agent, context: context) }
            )
        })
    }

    // MARK: - Tool Input Guardrails

    /// Runs tool input guardrails on the provided tool data.
    ///
    /// Executes all tool input guardrails according to the runner's configuration.
    /// If a tripwire is triggered and `stopOnFirstTripwire` is true, throws
    /// immediately. Otherwise, collects all results and throws at the end if
    /// any guardrail tripwired.
    ///
    /// - Parameters:
    ///   - guardrails: The tool input guardrails to execute.
    ///   - data: The tool execution data to validate.
    /// - Returns: Array of execution results from all guardrails.
    /// - Throws: `GuardrailError.toolInputTripwireTriggered` if a tripwire is triggered,
    ///           or `GuardrailError.executionFailed` if execution fails.
    public func runToolInputGuardrails(
        _ guardrails: [any ToolInputGuardrail],
        data: ToolGuardrailData
    ) async throws -> [GuardrailExecutionResult] {
        let toolName = data.tool.name
        return try await execute(guardrails.map { guardrail in
            GuardrailUnit(
                subject: .toolInput(toolName: toolName),
                name: guardrail.name,
                observerContext: data.context,
                validate: { try await guardrail.validate(data) }
            )
        })
    }

    // MARK: - Tool Output Guardrails

    /// Runs tool output guardrails on the provided tool data and output.
    ///
    /// Executes all tool output guardrails according to the runner's configuration.
    /// If a tripwire is triggered and `stopOnFirstTripwire` is true, throws
    /// immediately. Otherwise, collects all results and throws at the end if
    /// any guardrail tripwired.
    ///
    /// - Parameters:
    ///   - guardrails: The tool output guardrails to execute.
    ///   - data: The tool execution data.
    ///   - output: The output produced by the tool.
    /// - Returns: Array of execution results from all guardrails.
    /// - Throws: `GuardrailError.toolOutputTripwireTriggered` if a tripwire is triggered,
    ///           or `GuardrailError.executionFailed` if execution fails.
    public func runToolOutputGuardrails(
        _ guardrails: [any ToolOutputGuardrail],
        data: ToolGuardrailData,
        output: SendableValue
    ) async throws -> [GuardrailExecutionResult] {
        let toolName = data.tool.name
        return try await execute(guardrails.map { guardrail in
            GuardrailUnit(
                subject: .toolOutput(toolName: toolName),
                name: guardrail.name,
                observerContext: data.context,
                validate: { try await guardrail.validate(data, output: output) }
            )
        })
    }
}

// MARK: - GuardrailRunner + Normalized Decision Core

extension GuardrailRunner {
    /// Dispatches normalized units through the single sequential or parallel
    /// executor selected by the configuration.
    private func execute(_ units: [GuardrailUnit]) async throws -> [GuardrailExecutionResult] {
        if configuration.runInParallel {
            return try await runParallel(units)
        }
        return try await runSequential(units)
    }

    /// Executes every unit one-by-one in order.
    private func runSequential(_ units: [GuardrailUnit]) async throws -> [GuardrailExecutionResult] {
        var results: [GuardrailExecutionResult] = []

        for unit in units {
            try Task.checkCancellation()

            do {
                let result = try await validateWithTimeout(guardrailName: unit.name, operation: unit.validate)
                let executionResult = GuardrailExecutionResult(
                    guardrailName: unit.name,
                    result: result
                )
                results.append(executionResult)

                if let error = Self.tripwireError(
                    subject: unit.subject,
                    guardrailName: unit.name,
                    result: result
                ) {
                    await emitGuardrailEvent(
                        guardrailName: unit.name,
                        guardrailType: unit.kind,
                        result: result,
                        context: unit.observerContext
                    )
                    if configuration.stopOnFirstTripwire {
                        throw error
                    }
                }
            } catch let error as GuardrailError {
                throw error
            } catch {
                throw GuardrailError.executionFailed(
                    guardrailName: unit.name,
                    underlyingError: error.localizedDescription
                )
            }
        }

        // Check if any tripwires were triggered (when not stopping on first)
        if let tripwired = zip(units, results).first(where: { $0.1.didTriggerTripwire }),
           let error = Self.tripwireError(
               subject: tripwired.0.subject,
               guardrailName: tripwired.1.guardrailName,
               result: tripwired.1.result
           ) {
            throw error
        }

        return results
    }

    /// Executes every unit concurrently and returns results in input order.
    private func runParallel(_ units: [GuardrailUnit]) async throws -> [GuardrailExecutionResult] {
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: (Int, GuardrailExecutionResult).self) { group in
            var indexedResults: [(Int, GuardrailExecutionResult)] = []
            indexedResults.reserveCapacity(units.count)

            // Add all units to the task group
            for (index, unit) in units.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.validateWithTimeout(guardrailName: unit.name, operation: unit.validate)
                        return (index, GuardrailExecutionResult(
                            guardrailName: unit.name,
                            result: result
                        ))
                    } catch let error as GuardrailError {
                        throw error
                    } catch {
                        throw GuardrailError.executionFailed(
                            guardrailName: unit.name,
                            underlyingError: error.localizedDescription
                        )
                    }
                }
            }

            // Collect results
            for try await (index, executionResult) in group {
                let unit = units[index]
                if configuration.stopOnFirstTripwire,
                   let error = Self.tripwireError(
                       subject: unit.subject,
                       guardrailName: executionResult.guardrailName,
                       result: executionResult.result
                   ) {
                    await emitGuardrailEvent(
                        guardrailName: executionResult.guardrailName,
                        guardrailType: unit.kind,
                        result: executionResult.result,
                        context: unit.observerContext
                    )
                    // Cancel remaining tasks
                    group.cancelAll()
                    throw error
                }
                indexedResults.append((index, executionResult))
            }

            indexedResults.sort { $0.0 < $1.0 }
            let orderedUnits = indexedResults.map { units[$0.0] }
            let results = indexedResults.map(\.1)

            // Check if any tripwires were triggered (when not stopping on first)
            if let firstTripwire = zip(orderedUnits, results).first(where: { $0.1.didTriggerTripwire }) {
                for (unit, executionResult) in zip(orderedUnits, results) where executionResult.didTriggerTripwire {
                    await emitGuardrailEvent(
                        guardrailName: executionResult.guardrailName,
                        guardrailType: unit.kind,
                        result: executionResult.result,
                        context: unit.observerContext
                    )
                }
                if let error = Self.tripwireError(
                    subject: firstTripwire.0.subject,
                    guardrailName: firstTripwire.1.guardrailName,
                    result: firstTripwire.1.result
                ) {
                    throw error
                }
            }

            return results
        }
    }
}

