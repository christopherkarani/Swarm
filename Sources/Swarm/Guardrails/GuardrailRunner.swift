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

private final class GuardrailTimeoutRace<Result: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func setOperationTask(_ task: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = completed
        if !completed {
            operationTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = completed
        if !completed {
            timeoutTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func complete(_ resume: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let operationTask = operationTask
        let timeoutTask = timeoutTask
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        resume()
    }
}

private struct GuardrailTimeoutError: Error, LocalizedError, Sendable {
    let guardrailName: String
    let timeout: Duration

    var errorDescription: String? {
        "Guardrail '\(guardrailName)' timed out after \(timeout)."
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
/// **Note:** When running in parallel mode, the order of results in the returned
/// array may not match the order of guardrails in the input array due to the
/// non-deterministic nature of concurrent execution.
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

    private func inputTripwireError(
        guardrailName: String,
        result: GuardrailResult
    ) -> GuardrailError? {
        switch result {
        case .passed:
            nil
        case let .tripwire(message, outputInfo, _):
            .inputTripwireTriggered(
                guardrailName: guardrailName,
                message: message,
                outputInfo: outputInfo
            )
        }
    }

    private func outputTripwireError(
        guardrailName: String,
        agentName: String,
        result: GuardrailResult
    ) -> GuardrailError? {
        switch result {
        case .passed:
            nil
        case let .tripwire(message, outputInfo, _):
            .outputTripwireTriggered(
                guardrailName: guardrailName,
                agentName: agentName,
                message: message,
                outputInfo: outputInfo
            )
        }
    }

    private func toolInputTripwireError(
        guardrailName: String,
        toolName: String,
        result: GuardrailResult
    ) -> GuardrailError? {
        switch result {
        case .passed:
            nil
        case let .tripwire(message, outputInfo, _):
            .toolInputTripwireTriggered(
                guardrailName: guardrailName,
                toolName: toolName,
                message: message,
                outputInfo: outputInfo
            )
        }
    }

    private func toolOutputTripwireError(
        guardrailName: String,
        toolName: String,
        result: GuardrailResult
    ) -> GuardrailError? {
        switch result {
        case .passed:
            nil
        case let .tripwire(message, outputInfo, _):
            .toolOutputTripwireTriggered(
                guardrailName: guardrailName,
                toolName: toolName,
                message: message,
                outputInfo: outputInfo
            )
        }
    }

    private func validateWithTimeout<Result: Sendable>(
        guardrailName: String,
        operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        guard let timeout = configuration.timeout else {
            return try await operation()
        }

        let race = GuardrailTimeoutRace<Result>()
        return try await withCheckedThrowingContinuation { continuation in
            let operationTask = Task {
                do {
                    let result = try await operation()
                    race.complete {
                        continuation.resume(returning: result)
                    }
                } catch {
                    race.complete {
                        continuation.resume(throwing: error)
                    }
                }
            }
            race.setOperationTask(operationTask)

            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                race.complete {
                    continuation.resume(throwing: GuardrailTimeoutError(guardrailName: guardrailName, timeout: timeout))
                }
            }
            race.setTimeoutTask(timeoutTask)
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
        if configuration.runInParallel {
            try await runInputGuardrailsParallel(guardrails, input: input, context: context)
        } else {
            try await runInputGuardrailsSequential(guardrails, input: input, context: context)
        }
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
        if configuration.runInParallel {
            try await runOutputGuardrailsParallel(guardrails, output: output, agent: agent, context: context)
        } else {
            try await runOutputGuardrailsSequential(guardrails, output: output, agent: agent, context: context)
        }
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
        if configuration.runInParallel {
            try await runToolInputGuardrailsParallel(guardrails, data: data)
        } else {
            try await runToolInputGuardrailsSequential(guardrails, data: data)
        }
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
        if configuration.runInParallel {
            try await runToolOutputGuardrailsParallel(guardrails, data: data, output: output)
        } else {
            try await runToolOutputGuardrailsSequential(guardrails, data: data, output: output)
        }
    }
}

// MARK: - GuardrailRunner + Sequential Execution

extension GuardrailRunner {
    func runInputGuardrailsSequential(
        _ guardrails: [any InputGuardrail],
        input: String,
        context: AgentContext?
    ) async throws -> [GuardrailExecutionResult] {
        var results: [GuardrailExecutionResult] = []

        for guardrail in guardrails {
            try Task.checkCancellation()

            do {
                let result = try await validateWithTimeout(guardrailName: guardrail.name) {
                    try await guardrail.validate(input, context: context)
                }
                let executionResult = GuardrailExecutionResult(
                    guardrailName: guardrail.name,
                    result: result
                )
                results.append(executionResult)

                if let error = inputTripwireError(guardrailName: guardrail.name, result: result) {
                    await emitGuardrailEvent(
                        guardrailName: guardrail.name,
                        guardrailType: .input,
                        result: result,
                        context: context
                    )
                    if configuration.stopOnFirstTripwire {
                        throw error
                    }
                }
            } catch let error as GuardrailError {
                throw error
            } catch {
                throw GuardrailError.executionFailed(
                    guardrailName: guardrail.name,
                    underlyingError: error.localizedDescription
                )
            }
        }

        // Check if any tripwires were triggered (when not stopping on first)
        if let tripwiredResult = results.first(where: \.didTriggerTripwire),
           let error = inputTripwireError(
               guardrailName: tripwiredResult.guardrailName,
               result: tripwiredResult.result
           ) {
            throw error
        }

        return results
    }

    func runOutputGuardrailsSequential(
        _ guardrails: [any OutputGuardrail],
        output: String,
        agent: any AgentRuntime,
        context: AgentContext?
    ) async throws -> [GuardrailExecutionResult] {
        var results: [GuardrailExecutionResult] = []

        for guardrail in guardrails {
            try Task.checkCancellation()

            do {
                let result = try await validateWithTimeout(guardrailName: guardrail.name) {
                    try await guardrail.validate(output, agent: agent, context: context)
                }
                let executionResult = GuardrailExecutionResult(
                    guardrailName: guardrail.name,
                    result: result
                )
                results.append(executionResult)

                if let error = outputTripwireError(
                    guardrailName: guardrail.name,
                    agentName: agent.configuration.name,
                    result: result
                ) {
                    await emitGuardrailEvent(
                        guardrailName: guardrail.name,
                        guardrailType: .output,
                        result: result,
                        context: context
                    )
                    if configuration.stopOnFirstTripwire {
                        throw error
                    }
                }
            } catch let error as GuardrailError {
                throw error
            } catch {
                throw GuardrailError.executionFailed(
                    guardrailName: guardrail.name,
                    underlyingError: error.localizedDescription
                )
            }
        }

        // Check if any tripwires were triggered (when not stopping on first)
        if let tripwiredResult = results.first(where: \.didTriggerTripwire),
           let error = outputTripwireError(
               guardrailName: tripwiredResult.guardrailName,
               agentName: agent.configuration.name,
               result: tripwiredResult.result
           ) {
            throw error
        }

        return results
    }

    func runToolInputGuardrailsSequential(
        _ guardrails: [any ToolInputGuardrail],
        data: ToolGuardrailData
    ) async throws -> [GuardrailExecutionResult] {
        var results: [GuardrailExecutionResult] = []

        for guardrail in guardrails {
            try Task.checkCancellation()

            do {
                let result = try await validateWithTimeout(guardrailName: guardrail.name) {
                    try await guardrail.validate(data)
                }
                let executionResult = GuardrailExecutionResult(
                    guardrailName: guardrail.name,
                    result: result
                )
                results.append(executionResult)

                if let error = toolInputTripwireError(
                    guardrailName: guardrail.name,
                    toolName: data.tool.name,
                    result: result
                ) {
                    await emitGuardrailEvent(
                        guardrailName: guardrail.name,
                        guardrailType: .toolInput,
                        result: result,
                        context: data.context
                    )
                    if configuration.stopOnFirstTripwire {
                        throw error
                    }
                }
            } catch let error as GuardrailError {
                throw error
            } catch {
                throw GuardrailError.executionFailed(
                    guardrailName: guardrail.name,
                    underlyingError: error.localizedDescription
                )
            }
        }

        // Check if any tripwires were triggered (when not stopping on first)
        if let tripwiredResult = results.first(where: \.didTriggerTripwire),
           let error = toolInputTripwireError(
               guardrailName: tripwiredResult.guardrailName,
               toolName: data.tool.name,
               result: tripwiredResult.result
           ) {
            throw error
        }

        return results
    }

    func runToolOutputGuardrailsSequential(
        _ guardrails: [any ToolOutputGuardrail],
        data: ToolGuardrailData,
        output: SendableValue
    ) async throws -> [GuardrailExecutionResult] {
        var results: [GuardrailExecutionResult] = []

        for guardrail in guardrails {
            try Task.checkCancellation()

            do {
                let result = try await validateWithTimeout(guardrailName: guardrail.name) {
                    try await guardrail.validate(data, output: output)
                }
                let executionResult = GuardrailExecutionResult(
                    guardrailName: guardrail.name,
                    result: result
                )
                results.append(executionResult)

                if let error = toolOutputTripwireError(
                    guardrailName: guardrail.name,
                    toolName: data.tool.name,
                    result: result
                ) {
                    await emitGuardrailEvent(
                        guardrailName: guardrail.name,
                        guardrailType: .toolOutput,
                        result: result,
                        context: data.context
                    )
                    if configuration.stopOnFirstTripwire {
                        throw error
                    }
                }
            } catch let error as GuardrailError {
                throw error
            } catch {
                throw GuardrailError.executionFailed(
                    guardrailName: guardrail.name,
                    underlyingError: error.localizedDescription
                )
            }
        }

        // Check if any tripwires were triggered (when not stopping on first)
        if let tripwiredResult = results.first(where: \.didTriggerTripwire),
           let error = toolOutputTripwireError(
               guardrailName: tripwiredResult.guardrailName,
               toolName: data.tool.name,
               result: tripwiredResult.result
           ) {
            throw error
        }

        return results
    }
}

// MARK: - GuardrailRunner + Parallel Execution

extension GuardrailRunner {
    func runInputGuardrailsParallel(
        _ guardrails: [any InputGuardrail],
        input: String,
        context: AgentContext?
    ) async throws -> [GuardrailExecutionResult] {
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: (Int, GuardrailExecutionResult).self) { group in
            var indexedResults: [(Int, GuardrailExecutionResult)] = []
            indexedResults.reserveCapacity(guardrails.count)

            // Add all guardrails to the task group
            for (index, guardrail) in guardrails.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.validateWithTimeout(guardrailName: guardrail.name) {
                            try await guardrail.validate(input, context: context)
                        }
                        return (index, GuardrailExecutionResult(
                            guardrailName: guardrail.name,
                            result: result
                        ))
                    } catch let error as GuardrailError {
                        throw error
                    } catch {
                        throw GuardrailError.executionFailed(
                            guardrailName: guardrail.name,
                            underlyingError: error.localizedDescription
                        )
                    }
                }
            }

            // Collect results
            for try await (index, executionResult) in group {
                if configuration.stopOnFirstTripwire,
                   let error = inputTripwireError(
                       guardrailName: executionResult.guardrailName,
                       result: executionResult.result
                   ) {
                    await emitGuardrailEvent(
                        guardrailName: executionResult.guardrailName,
                        guardrailType: .input,
                        result: executionResult.result,
                        context: context
                    )
                    // Cancel remaining tasks
                    group.cancelAll()
                    throw error
                }
                indexedResults.append((index, executionResult))
            }

            indexedResults.sort { $0.0 < $1.0 }
            let results = indexedResults.map(\.1)

            // Check if any tripwires were triggered (when not stopping on first)
            if let tripwiredResult = results.first(where: \.didTriggerTripwire),
               let error = inputTripwireError(
                   guardrailName: tripwiredResult.guardrailName,
                   result: tripwiredResult.result
               ) {
                for result in results where result.didTriggerTripwire {
                    await emitGuardrailEvent(
                        guardrailName: result.guardrailName,
                        guardrailType: .input,
                        result: result.result,
                        context: context
                    )
                }
                throw error
            }

            return results
        }
    }

    func runOutputGuardrailsParallel(
        _ guardrails: [any OutputGuardrail],
        output: String,
        agent: any AgentRuntime,
        context: AgentContext?
    ) async throws -> [GuardrailExecutionResult] {
        try Task.checkCancellation()

        let agentName = agent.configuration.name

        return try await withThrowingTaskGroup(of: (Int, GuardrailExecutionResult).self) { group in
            var indexedResults: [(Int, GuardrailExecutionResult)] = []
            indexedResults.reserveCapacity(guardrails.count)

            // Add all guardrails to the task group
            for (index, guardrail) in guardrails.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.validateWithTimeout(guardrailName: guardrail.name) {
                            try await guardrail.validate(output, agent: agent, context: context)
                        }
                        return (index, GuardrailExecutionResult(
                            guardrailName: guardrail.name,
                            result: result
                        ))
                    } catch let error as GuardrailError {
                        throw error
                    } catch {
                        throw GuardrailError.executionFailed(
                            guardrailName: guardrail.name,
                            underlyingError: error.localizedDescription
                        )
                    }
                }
            }

            // Collect results
            for try await (index, executionResult) in group {
                if configuration.stopOnFirstTripwire,
                   let error = outputTripwireError(
                       guardrailName: executionResult.guardrailName,
                       agentName: agentName,
                       result: executionResult.result
                   ) {
                    await emitGuardrailEvent(
                        guardrailName: executionResult.guardrailName,
                        guardrailType: .output,
                        result: executionResult.result,
                        context: context
                    )
                    // Cancel remaining tasks
                    group.cancelAll()
                    throw error
                }
                indexedResults.append((index, executionResult))
            }

            indexedResults.sort { $0.0 < $1.0 }
            let results = indexedResults.map(\.1)

            // Check if any tripwires were triggered (when not stopping on first)
            if let tripwiredResult = results.first(where: \.didTriggerTripwire),
               let error = outputTripwireError(
                   guardrailName: tripwiredResult.guardrailName,
                   agentName: agentName,
                   result: tripwiredResult.result
               ) {
                for result in results where result.didTriggerTripwire {
                    await emitGuardrailEvent(
                        guardrailName: result.guardrailName,
                        guardrailType: .output,
                        result: result.result,
                        context: context
                    )
                }
                throw error
            }

            return results
        }
    }

    func runToolInputGuardrailsParallel(
        _ guardrails: [any ToolInputGuardrail],
        data: ToolGuardrailData
    ) async throws -> [GuardrailExecutionResult] {
        try Task.checkCancellation()

        let toolName = data.tool.name

        return try await withThrowingTaskGroup(of: (Int, GuardrailExecutionResult).self) { group in
            var indexedResults: [(Int, GuardrailExecutionResult)] = []
            indexedResults.reserveCapacity(guardrails.count)

            // Add all guardrails to the task group
            for (index, guardrail) in guardrails.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.validateWithTimeout(guardrailName: guardrail.name) {
                            try await guardrail.validate(data)
                        }
                        return (index, GuardrailExecutionResult(
                            guardrailName: guardrail.name,
                            result: result
                        ))
                    } catch let error as GuardrailError {
                        throw error
                    } catch {
                        throw GuardrailError.executionFailed(
                            guardrailName: guardrail.name,
                            underlyingError: error.localizedDescription
                        )
                    }
                }
            }

            // Collect results
            for try await (index, executionResult) in group {
                if configuration.stopOnFirstTripwire,
                   let error = toolInputTripwireError(
                       guardrailName: executionResult.guardrailName,
                       toolName: toolName,
                       result: executionResult.result
                   ) {
                    await emitGuardrailEvent(
                        guardrailName: executionResult.guardrailName,
                        guardrailType: .toolInput,
                        result: executionResult.result,
                        context: data.context
                    )
                    // Cancel remaining tasks
                    group.cancelAll()
                    throw error
                }
                indexedResults.append((index, executionResult))
            }

            indexedResults.sort { $0.0 < $1.0 }
            let results = indexedResults.map(\.1)

            // Check if any tripwires were triggered (when not stopping on first)
            if let tripwiredResult = results.first(where: \.didTriggerTripwire),
               let error = toolInputTripwireError(
                   guardrailName: tripwiredResult.guardrailName,
                   toolName: toolName,
                   result: tripwiredResult.result
               ) {
                for result in results where result.didTriggerTripwire {
                    await emitGuardrailEvent(
                        guardrailName: result.guardrailName,
                        guardrailType: .toolInput,
                        result: result.result,
                        context: data.context
                    )
                }
                throw error
            }

            return results
        }
    }

    func runToolOutputGuardrailsParallel(
        _ guardrails: [any ToolOutputGuardrail],
        data: ToolGuardrailData,
        output: SendableValue
    ) async throws -> [GuardrailExecutionResult] {
        try Task.checkCancellation()

        let toolName = data.tool.name

        return try await withThrowingTaskGroup(of: (Int, GuardrailExecutionResult).self) { group in
            var indexedResults: [(Int, GuardrailExecutionResult)] = []
            indexedResults.reserveCapacity(guardrails.count)

            // Add all guardrails to the task group
            for (index, guardrail) in guardrails.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.validateWithTimeout(guardrailName: guardrail.name) {
                            try await guardrail.validate(data, output: output)
                        }
                        return (index, GuardrailExecutionResult(
                            guardrailName: guardrail.name,
                            result: result
                        ))
                    } catch let error as GuardrailError {
                        throw error
                    } catch {
                        throw GuardrailError.executionFailed(
                            guardrailName: guardrail.name,
                            underlyingError: error.localizedDescription
                        )
                    }
                }
            }

            // Collect results
            for try await (index, executionResult) in group {
                if configuration.stopOnFirstTripwire,
                   let error = toolOutputTripwireError(
                       guardrailName: executionResult.guardrailName,
                       toolName: toolName,
                       result: executionResult.result
                   ) {
                    await emitGuardrailEvent(
                        guardrailName: executionResult.guardrailName,
                        guardrailType: .toolOutput,
                        result: executionResult.result,
                        context: data.context
                    )
                    // Cancel remaining tasks
                    group.cancelAll()
                    throw error
                }
                indexedResults.append((index, executionResult))
            }

            indexedResults.sort { $0.0 < $1.0 }
            let results = indexedResults.map(\.1)

            // Check if any tripwires were triggered (when not stopping on first)
            if let tripwiredResult = results.first(where: \.didTriggerTripwire),
               let error = toolOutputTripwireError(
                   guardrailName: tripwiredResult.guardrailName,
                   toolName: toolName,
                   result: tripwiredResult.result
               ) {
                for result in results where result.didTriggerTripwire {
                    await emitGuardrailEvent(
                        guardrailName: result.guardrailName,
                        guardrailType: .toolOutput,
                        result: result.result,
                        context: data.context
                    )
                }
                throw error
            }

            return results
        }
    }
}
