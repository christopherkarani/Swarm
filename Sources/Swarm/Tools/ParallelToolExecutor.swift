// ParallelToolExecutor.swift
// Swarm Framework
//
// Executes multiple tool calls in parallel using structured concurrency.

import Foundation

// MARK: - ParallelToolExecutor

/// Executes multiple tool calls in parallel using structured concurrency.
///
/// `ParallelToolExecutor` enables concurrent execution of independent tool calls
/// while preserving the order of results to match the input order. This is essential
/// for LLM workflows where multiple tools can be invoked simultaneously, but results
/// must be correlated back to their original requests.
///
/// ## Order Preservation
///
/// Results are always returned in the same order as the input tool calls,
/// regardless of which tools complete first. This is achieved by tracking
/// each task with an index and sorting results before returning.
///
/// ## Thread Safety
///
/// As an actor, `ParallelToolExecutor` provides thread-safe execution.
/// All tool calls are executed concurrently using Swift's structured
/// concurrency (`withThrowingTaskGroup`), ensuring proper cancellation
/// propagation and resource cleanup.
///
/// ## Error Handling
///
/// By default, individual tool failures are captured in the results without
/// throwing. Use the `errorStrategy` parameter to customize this behavior:
/// - `.failFast`: Throws on first error found in results
/// - `.collectErrors`: Throws composite error if any failures
/// - `.continueOnError`: Returns results with failures included
///
/// ## Example
///
/// ```swift
/// let executor = ParallelToolExecutor()
/// let calls = [
///     ToolCall(toolName: "weather", arguments: ["city": .string("NYC")]),
///     ToolCall(toolName: "stocks", arguments: ["symbol": .string("AAPL")]),
///     ToolCall(toolName: "news", arguments: ["topic": .string("tech")])
/// ]
///
/// let results = try await executor.executeInParallel(
///     calls,
///     using: registry,
///     agent: agent,
///     context: nil
/// )
///
/// // results[0] is weather (guaranteed, regardless of completion order)
/// // results[1] is stocks
/// // results[2] is news
///
/// for result in results {
///     if result.isSuccess {
///         print("\(result.toolName): \(result.value!)")
///     } else {
///         print("\(result.toolName) failed: \(result.error!)")
///     }
/// }
/// ```
///
/// ## Performance Considerations
///
/// - All tools are validated for existence before any execution begins
/// - Duration is measured by the shared tool execution engine's injectable clock
/// - Failed tools do not block successful ones from completing
/// - Consecutive tools that ``ToolExecutionSemantics/runtimePolicy()`` marks
///   parallel-eligible still run concurrently; each explicit
///   ``ToolSideEffectLevel/externalMutation`` is its own serial step so it
///   does not overlap any other call. ``ToolExecutionSemantics/automatic``
///   remains parallel-eligible.
public actor ParallelToolExecutor {
    // MARK: Public

    // MARK: - Initialization

    /// Creates a new parallel tool executor using the live Engine clock.
    public init() {
        engine = ToolExecutionEngine()
    }

    /// Creates an executor that runs every call through the given Engine.
    init(engine: ToolExecutionEngine) {
        self.engine = engine
    }

    // MARK: - Public Methods

    /// Executes multiple tool calls in parallel.
    ///
    /// This method validates all tools exist in the registry before starting
    /// any execution, then runs consecutive parallel-eligible tools concurrently.
    /// Each explicit ``ToolSideEffectLevel/externalMutation`` is a serial step
    /// so it does not overlap any other call. Results are returned in the same
    /// order as the input calls, regardless of completion order.
    ///
    /// Individual tool failures are captured as `ToolExecutionResult.failure`
    /// entries rather than throwing. This allows the caller to handle partial
    /// successes appropriately.
    ///
    /// - Parameters:
    ///   - calls: Array of tool calls to execute concurrently.
    ///   - registry: Tool registry containing the tool implementations.
    ///   - agent: The agent making the tool calls.
    ///   - context: Optional execution context for agent state.
    /// - Returns: Array of results in the same order as input calls.
    /// - Throws: `AgentError.toolNotFound` if any tool doesn't exist in the registry.
    ///
    /// ## Validation
    ///
    /// All tools are validated for existence before any execution begins.
    /// This fail-fast approach prevents partial execution when a required
    /// tool is missing.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let calls = [
    ///     ToolCall(toolName: "search", arguments: ["query": .string("Swift")]),
    ///     ToolCall(toolName: "calculate", arguments: ["expr": .string("2+2")])
    /// ]
    ///
    /// let results = try await executor.executeInParallel(
    ///     calls,
    ///     using: registry,
    ///     agent: myAgent,
    ///     context: nil
    /// )
    /// ```
    public func executeInParallel(
        _ calls: [ToolCall],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?
    ) async throws -> [ToolExecutionResult] {
        // Handle empty calls array
        guard !calls.isEmpty else {
            return []
        }

        let eligibility = try await validatedEligibility(for: calls, registry: registry)
        return try await executeCalls(
            calls,
            eligibility: eligibility,
            using: registry,
            agent: agent,
            context: context,
            stopOnToolError: false
        )
    }

    /// Executes multiple tool calls in parallel with an error handling strategy.
    ///
    /// This method extends the basic parallel execution with configurable
    /// error handling behavior. After all tools complete (or fail), the
    /// error strategy is applied to determine whether to throw or return.
    ///
    /// - Parameters:
    ///   - calls: Array of tool calls to execute concurrently.
    ///   - registry: Tool registry containing the tool implementations.
    ///   - agent: The agent making the tool calls.
    ///   - context: Optional execution context for agent state.
    ///   - errorStrategy: Strategy for handling errors in results.
    /// - Returns: Array of results in the same order as input calls.
    /// - Throws: `AgentError.toolNotFound` if any tool doesn't exist,
    ///           or errors based on the specified error strategy.
    ///
    /// ## Error Strategies
    ///
    /// - **`.failFast`**: Throws the first tool error and cancels remaining
    ///   work in the current concurrent group; later serial or concurrent
    ///   groups never start.
    ///
    /// - **`.collectErrors`**: Throws a composite error if any tool failed.
    ///   The error message includes all failure descriptions.
    ///
    /// - **`.continueOnError`**: Returns results as-is with failures included.
    ///   Callers inspect individual results to handle failures.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Fail fast on any error
    /// let results = try await executor.executeInParallel(
    ///     calls,
    ///     using: registry,
    ///     agent: myAgent,
    ///     context: nil,
    ///     errorStrategy: .failFast
    /// )
    ///
    /// // Continue and handle failures individually
    /// let results = try await executor.executeInParallel(
    ///     calls,
    ///     using: registry,
    ///     agent: myAgent,
    ///     context: nil,
    ///     errorStrategy: .continueOnError
    /// )
    /// for result in results where !result.isSuccess {
    ///     print("Tool \(result.toolName) failed: \(result.error!)")
    /// }
    /// ```
    public func executeInParallel(
        _ calls: [ToolCall],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        errorStrategy: ParallelExecutionErrorStrategy
    ) async throws -> [ToolExecutionResult] {
        // For failFast, use implementation with true cancellation
        if case .failFast = errorStrategy {
            return try await executeWithFailFast(
                calls,
                using: registry,
                agent: agent,
                context: context
            )
        }

        // Execute all tools (failures are captured in results)
        let results = try await executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: context
        )

        // Apply error strategy
        switch errorStrategy {
        case .failFast:
            // Handled above with true cancellation - this case should never be reached
            // If we reach here, it indicates a logic error in the implementation
            throw AgentError.internalError(reason: "ParallelToolExecutor: failFast case reached unexpectedly in error strategy switch")

        case .collectErrors:
            // Collect all errors and throw composite error
            let errors = results.compactMap(\.error)
            if !errors.isEmpty {
                let errorDescriptions = errors.map(\.localizedDescription)
                throw AgentError.toolFailure(
                    toolName: "parallel_execution",
                    message: "Multiple tools failed: \(errorDescriptions.joined(separator: "; "))",
                    cause: errors.first
                )
            }

        case .continueOnError:
            // Return results as-is with failures included
            break
        }

        return results
    }

    // MARK: Private

    private let engine: ToolExecutionEngine

    // MARK: - Private Methods

    /// Executes tools with true fail-fast cancellation.
    ///
    /// Unlike the standard parallel execution, this method cancels remaining
    /// work when the first Engine invocation throws.
    private func executeWithFailFast(
        _ calls: [ToolCall],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?
    ) async throws -> [ToolExecutionResult] {
        guard !calls.isEmpty else { return [] }

        let eligibility = try await validatedEligibility(for: calls, registry: registry)
        return try await executeCalls(
            calls,
            eligibility: eligibility,
            using: registry,
            agent: agent,
            context: context,
            stopOnToolError: true
        )
    }

    /// Fail-fast validation plus per-tool parallel eligibility from `runtimePolicy()`.
    ///
    /// Missing or disabled tools throw before any Engine invocation. A tool that
    /// is disabled *after* this pre-pass still goes through Engine and surfaces
    /// as a per-call failure when `stopOnToolError` is false.
    private func validatedEligibility(
        for calls: [ToolCall],
        registry: ToolRegistry
    ) async throws -> [Bool] {
        var eligibility: [Bool] = []
        eligibility.reserveCapacity(calls.count)
        for call in calls {
            guard let tool = await registry.tool(named: call.toolName), tool.isEnabled else {
                throw AgentError.toolNotFound(name: call.toolName)
            }
            eligibility.append(tool.executionSemantics.runtimePolicy().mayRunInParallel)
        }
        return eligibility
    }

    private func executeCalls(
        _ calls: [ToolCall],
        eligibility: [Bool],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        stopOnToolError: Bool
    ) async throws -> [ToolExecutionResult] {
        var results: [ToolExecutionResult] = []
        results.reserveCapacity(calls.count)
        var index = 0
        while index < calls.count {
            if eligibility[index] {
                var end = index + 1
                while end < calls.count, eligibility[end] {
                    end += 1
                }
                let concurrentResults = try await executeConcurrent(
                    Array(calls[index..<end]),
                    using: registry,
                    agent: agent,
                    context: context,
                    stopOnToolError: stopOnToolError
                )
                results.append(contentsOf: concurrentResults)
                index = end
            } else {
                try Task.checkCancellation()
                let mapped = try await engine.executeMapped(
                    call: calls[index],
                    registry: registry,
                    agent: agent,
                    context: context,
                    stopOnToolError: stopOnToolError
                )
                results.append(mapped)
                index += 1
            }
        }
        return results
    }

    private func executeConcurrent(
        _ calls: [ToolCall],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        stopOnToolError: Bool
    ) async throws -> [ToolExecutionResult] {
        try await withThrowingTaskGroup(of: (Int, ToolExecutionResult).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask { [engine, registry, agent, context] in
                    let mapped = try await engine.executeMapped(
                        call: call,
                        registry: registry,
                        agent: agent,
                        context: context,
                        stopOnToolError: stopOnToolError
                    )
                    return (index, mapped)
                }
            }

            var indexedResults: [(Int, ToolExecutionResult)] = []
            indexedResults.reserveCapacity(calls.count)

            for try await result in group {
                try Task.checkCancellation()
                indexedResults.append(result)
            }

            indexedResults.sort { $0.0 < $1.0 }
            return indexedResults.map(\.1)
        }
    }
}

// MARK: - Convenience Extensions

public extension ParallelToolExecutor {
    /// Executes multiple tool calls in parallel, continuing on errors.
    ///
    /// This is a convenience method equivalent to calling `executeInParallel`
    /// with `.continueOnError` strategy. Failures are captured in the results
    /// rather than thrown.
    ///
    /// - Parameters:
    ///   - calls: Array of tool calls to execute concurrently.
    ///   - registry: Tool registry containing the tool implementations.
    ///   - agent: The agent making the tool calls.
    ///   - context: Optional execution context.
    /// - Returns: Array of results in the same order as input calls.
    /// - Throws: Only `AgentError.toolNotFound` if any tool doesn't exist.
    func executeAllCapturingErrors(
        _ calls: [ToolCall],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext? = nil
    ) async throws -> [ToolExecutionResult] {
        try await executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: context,
            errorStrategy: .continueOnError
        )
    }

    /// Executes multiple tool calls, failing immediately on any error.
    ///
    /// This is a convenience method equivalent to calling `executeInParallel`
    /// with `.failFast` strategy. The first error encountered in results
    /// will be thrown.
    ///
    /// - Parameters:
    ///   - calls: Array of tool calls to execute concurrently.
    ///   - registry: Tool registry containing the tool implementations.
    ///   - agent: The agent making the tool calls.
    ///   - context: Optional execution context.
    /// - Returns: Array of successful results in the same order as input calls.
    /// - Throws: The first error encountered, or `AgentError.toolNotFound`.
    func executeAllOrFail(
        _ calls: [ToolCall],
        using registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext? = nil
    ) async throws -> [ToolExecutionResult] {
        try await executeInParallel(
            calls,
            using: registry,
            agent: agent,
            context: context,
            errorStrategy: .failFast
        )
    }
}
