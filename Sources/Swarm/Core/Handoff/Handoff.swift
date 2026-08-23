// Handoff.swift
// Swarm Framework
//
// LegacyAgent handoff system for multi-agent orchestration.

import Foundation

// MARK: - HandoffRequest

/// A request to transfer execution from one agent to another.
///
/// HandoffRequest encapsulates all information needed to hand off
/// control from a source agent to a target agent, including the
/// input for the target and any contextual information.
///
/// Example:
/// ```swift
/// let request = HandoffRequest(
///     sourceAgentName: "planner",
///     targetAgentName: "executor",
///     input: "Execute step 1: Fetch data",
///     reason: "Planning complete, ready to execute",
///     context: [
///         "plan_id": .string("plan-123"),
///         "step": .int(1)
///     ]
/// )
/// ```
public struct HandoffRequest: Sendable {
    /// The name of the agent initiating the handoff.
    public let sourceAgentName: String

    /// The name of the agent receiving the handoff.
    public let targetAgentName: String

    /// The input to provide to the target agent.
    public let input: String

    /// Optional reason explaining why the handoff is happening.
    public let reason: String?

    /// Additional context to transfer to the target agent.
    public let context: [String: SendableValue]

    /// Creates a new handoff request.
    ///
    /// - Parameters:
    ///   - sourceAgentName: The agent initiating the handoff.
    ///   - targetAgentName: The agent receiving the handoff.
    ///   - input: The input for the target agent.
    ///   - reason: Optional reason for the handoff. Default: nil
    ///   - context: Additional context to transfer. Default: [:]
    public init(
        sourceAgentName: String,
        targetAgentName: String,
        input: String,
        reason: String? = nil,
        context: [String: SendableValue] = [:]
    ) {
        self.sourceAgentName = sourceAgentName
        self.targetAgentName = targetAgentName
        self.input = input
        self.reason = reason
        self.context = context
    }
}

// MARK: - HandoffResult

/// The result of a completed agent handoff.
///
/// HandoffResult captures the outcome of transferring execution
/// from one agent to another, including the target agent's result
/// and metadata about the handoff.
///
/// Example:
/// ```swift
/// let result = try await coordinator.executeHandoff(request, context: context)
/// print("Target: \(result.targetAgentName)")
/// print("Output: \(result.result.output)")
/// print("Context transferred: \(result.transferredContext)")
/// ```
public struct HandoffResult: Sendable, Equatable {
    /// The name of the agent that received the handoff.
    public let targetAgentName: String

    /// The input that was provided to the target agent.
    public let input: String

    /// The result from the target agent's execution.
    public let result: AgentResult

    /// Context that was transferred to the target agent.
    public let transferredContext: [String: SendableValue]

    /// When the handoff was completed.
    public let timestamp: Date

    /// Creates a new handoff result.
    ///
    /// - Parameters:
    ///   - targetAgentName: The agent that received the handoff.
    ///   - input: The input provided to the target.
    ///   - result: The target agent's execution result.
    ///   - transferredContext: Context that was transferred.
    ///   - timestamp: When the handoff completed. Default: now
    public init(
        targetAgentName: String,
        input: String,
        result: AgentResult,
        transferredContext: [String: SendableValue],
        timestamp: Date = TurnEnvironment.live.now()
    ) {
        self.targetAgentName = targetAgentName
        self.input = input
        self.result = result
        self.transferredContext = transferredContext
        self.timestamp = timestamp
    }
}

// MARK: - HandoffReceiver

/// A protocol for agents that can receive handoffs from other agents.
///
/// Agents conforming to this protocol gain the ability to handle
/// control being transferred to them by other agents, including
/// receiving context and input from the source agent.
///
/// This protocol extends `LegacyAgent`, adding specialized handoff handling
/// while maintaining compatibility with standard agent execution.
///
/// Example:
/// ```swift
/// struct ExecutorAgent: LegacyAgent, HandoffReceiver {
///     let tools: [any Tool] = []
///     let instructions = "Execute tasks"
///     let configuration = AgentConfiguration.default
///
///     func run(_ input: String) async throws -> AgentResult {
///         // Standard execution
///         return AgentResult(output: "Executed: \(input)")
///     }
///
///     func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
///         // Standard streaming
///         AsyncThrowingStream { continuation in
///             continuation.finish()
///         }
///     }
///
///     func cancel() async {
///         // Standard cancellation
///     }
///
///     // HandoffReceiver can use the default implementation
/// }
/// ```
public protocol HandoffReceiver: AgentRuntime {
    /// Handles a handoff from another agent.
    ///
    /// This method is called when another agent transfers control
    /// to this agent. It receives the handoff request and the
    /// orchestration context.
    ///
    /// The default implementation merges the handoff context into
    /// the orchestration context and executes the agent normally.
    ///
    /// - Parameters:
    ///   - request: The handoff request containing input and context.
    ///   - context: The shared orchestration context.
    /// - Returns: The result of handling the handoff.
    /// - Throws: `AgentError` if execution fails.
    func handleHandoff(
        _ request: HandoffRequest,
        context: AgentContext
    ) async throws -> AgentResult
}

// MARK: - HandoffReceiver Default Implementation

public extension HandoffReceiver {
    /// Default implementation of handoff handling.
    ///
    /// This implementation:
    /// 1. Merges the handoff context into the orchestration context
    /// 2. Records the handoff in the execution path
    /// 3. Executes the agent with the provided input
    ///
    /// Override this method to provide custom handoff behavior.
    ///
    /// - Parameters:
    ///   - request: The handoff request.
    ///   - context: The shared orchestration context.
    /// - Returns: The agent's execution result.
    /// - Throws: `AgentError` if execution fails.
    func handleHandoff(
        _ request: HandoffRequest,
        context: AgentContext
    ) async throws -> AgentResult {
        // Merge handoff context into orchestration context
        for (key, value) in request.context {
            await context.set(key, value: value)
        }

        // Record the handoff source in context
        await context.set(
            "handoff_source",
            value: .string(request.sourceAgentName)
        )

        if let reason = request.reason {
            await context.set("handoff_reason", value: .string(reason))
        }

        // Record this agent's execution
        await context.recordExecution(agentName: request.targetAgentName)

        // Execute the agent normally
        return try await run(request.input)
    }
}

// MARK: - HandoffCoordinator

/// Coordinates agent handoffs in a multi-agent system.
///
/// HandoffCoordinator manages a registry of agents and facilitates
/// transferring execution from one agent to another. It ensures
/// thread-safe access to agents and handles context propagation
/// during handoffs.
///
/// Example:
/// ```swift
/// let coordinator = HandoffCoordinator()
///
/// // Register agents
/// await coordinator.register(plannerAgent, as: "planner")
/// await coordinator.register(executorAgent, as: "executor")
///
/// // Execute a handoff
/// let request = HandoffRequest(
///     sourceAgentName: "planner",
///     targetAgentName: "executor",
///     input: "Execute task",
///     context: ["plan_id": .string("123")]
/// )
/// let result = try await coordinator.executeHandoff(request, context: context)
/// print(result.result.output)
/// ```
actor HandoffCoordinator {
    // MARK: Internal

    /// Returns the names of all registered agents.
    var registeredAgents: [String] {
        Array(agents.keys)
    }

    // MARK: - Initialization

    /// Creates a new handoff coordinator.
    init() {}

    // MARK: - LegacyAgent Registration

    /// Registers an agent with a specific name.
    func register(_ agent: any AgentRuntime, as name: String) {
        agents[name] = agent
    }

    /// Unregisters an agent by name.
    func unregister(_ name: String) {
        agents.removeValue(forKey: name)
    }

    /// Retrieves an agent by name.
    func agent(named name: String) -> (any AgentRuntime)? {
        agents[name]
    }

    // MARK: - Handoff Execution

    /// Executes a handoff from one agent to another.
    func executeHandoff(
        _ request: HandoffRequest,
        context: AgentContext
    ) async throws -> HandoffResult {
        // Look up the target agent
        guard let targetAgent = agents[request.targetAgentName] else {
            throw WorkflowError.agentNotFound(name: request.targetAgentName)
        }

        // Execute handoff based on agent capabilities
        let result: AgentResult

        if let handoffReceiver = targetAgent as? HandoffReceiver {
            // LegacyAgent implements HandoffReceiver, use specialized handling
            result = try await handoffReceiver.handleHandoff(request, context: context)
        } else {
            // Agent doesn't implement HandoffReceiver, use standard execution
            // Merge context manually, filtering out reserved keys to prevent injection
            let reservedPrefixes = ["auth", "user_id", "authorization", "session", "internal."]
            for (key, value) in request.context {
                let lowerKey = key.lowercased()
                guard !reservedPrefixes.contains(where: { lowerKey.hasPrefix($0) }) else {
                    Log.agents.warning("Handoff context key '\(key)' blocked: matches reserved prefix")
                    continue
                }
                await context.set(key, value: value)
            }

            // Record execution
            await context.recordExecution(agentName: request.targetAgentName)

            // Execute normally
            result = try await targetAgent.run(request.input)
        }

        // Store the result in context
        await context.setPreviousOutput(result)

        // Create and return handoff result
        return HandoffResult(
            targetAgentName: request.targetAgentName,
            input: request.input,
            result: result,
            transferredContext: request.context,
            timestamp: TurnEnvironment.live.now()
        )
    }

    /// Executes a handoff with configuration callbacks.
    func executeHandoff(
        _ request: HandoffRequest,
        context: AgentContext,
        configuration: AnyHandoffConfiguration?,
        observer: (any AgentObserver)?
    ) async throws -> HandoffResult {
        // Look up the target agent
        guard let targetAgent = agents[request.targetAgentName] else {
            throw WorkflowError.agentNotFound(name: request.targetAgentName)
        }

        // Process configuration callbacks if provided
        var effectiveInput = request.input
        var effectiveContext = request.context

        if let config = configuration {
            // Check if handoff is enabled
            if let when = config.when {
                let enabled = await when(context, targetAgent)
                if !enabled {
                    Log.orchestration.info(
                        "Handoff skipped: \(request.sourceAgentName) -> \(request.targetAgentName) (disabled by when callback)"
                    )
                    throw WorkflowError.handoffSkipped(
                        from: request.sourceAgentName,
                        to: request.targetAgentName,
                        reason: "Handoff disabled by when callback"
                    )
                }
            }

            // Create HandoffInputData for callbacks
            var inputData = HandoffInputData(
                sourceAgentName: request.sourceAgentName,
                targetAgentName: request.targetAgentName,
                input: request.input,
                context: request.context,
                metadata: [:]
            )

            // Apply input filter if present
            if let transform = config.transform {
                inputData = transform(inputData)
            }

            // Call onTransfer callback if present
            if let onTransfer = config.onTransfer {
                do {
                    try await onTransfer(context, inputData)
                } catch {
                    // Log callback errors but don't fail the handoff
                    Log.orchestration.warning(
                        "onTransfer callback failed for \(request.sourceAgentName) -> \(request.targetAgentName): \(error.localizedDescription)"
                    )
                }
            }

            // Use potentially modified input from filter
            effectiveInput = inputData.input

            // Merge filter metadata into context
            for (key, value) in inputData.metadata {
                effectiveContext[key] = value
            }
        }

        // Invoke AgentObserver.onHandoff if observer provided
        if let observer, let sourceAgent = agents[request.sourceAgentName] {
            await observer.onHandoff(context: context, fromAgent: sourceAgent, toAgent: targetAgent)
        }

        // Execute handoff based on agent capabilities
        let result: AgentResult

        // Create modified request with effective values
        let effectiveRequest = HandoffRequest(
            sourceAgentName: request.sourceAgentName,
            targetAgentName: request.targetAgentName,
            input: effectiveInput,
            reason: request.reason,
            context: effectiveContext
        )

        if let handoffReceiver = targetAgent as? HandoffReceiver {
            // LegacyAgent implements HandoffReceiver, use specialized handling
            result = try await handoffReceiver.handleHandoff(effectiveRequest, context: context)
        } else {
            // LegacyAgent doesn't implement HandoffReceiver, use standard execution
            // Merge context manually
            for (key, value) in effectiveContext {
                await context.set(key, value: value)
            }

            // Record execution
            await context.recordExecution(agentName: request.targetAgentName)

            // Execute normally
            result = try await targetAgent.run(effectiveInput)
        }

        // Store the result in context
        await context.setPreviousOutput(result)

        // Create and return handoff result
        return HandoffResult(
            targetAgentName: request.targetAgentName,
            input: effectiveInput,
            result: result,
            transferredContext: effectiveContext,
            timestamp: TurnEnvironment.live.now()
        )
    }

    // MARK: Private

    // MARK: - Private Storage

    /// Registry of agents by name.
    private var agents: [String: any AgentRuntime] = [:]
}

// MARK: - HandoffRequest + CustomStringConvertible

extension HandoffRequest: CustomStringConvertible {
    public var description: String {
        """
        HandoffRequest(
            from: "\(sourceAgentName)",
            to: "\(targetAgentName)",
            input: "\(input.prefix(50))\(input.count > 50 ? "..." : "")",
            reason: \(reason ?? "none")
        )
        """
    }
}

// MARK: - HandoffResult + CustomStringConvertible

extension HandoffResult: CustomStringConvertible {
    public var description: String {
        """
        HandoffResult(
            target: "\(targetAgentName)",
            output: "\(result.output.prefix(50))\(result.output.count > 50 ? "..." : "")",
            timestamp: \(timestamp)
        )
        """
    }
}
