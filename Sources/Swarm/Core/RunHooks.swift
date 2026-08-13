// AgentObserver.swift
// Swarm Framework
//
// Lifecycle observer for observing agent execution events.

import Foundation

// MARK: - AgentObserver

/// Protocol for receiving callbacks during agent execution.
///
/// `AgentObserver` provides a comprehensive set of lifecycle callbacks that enable
/// monitoring, logging, and custom logic at key points during agent execution.
/// All methods have default no-op implementations, so implementers only need to
/// override the callbacks they care about.
///
/// Use cases:
/// - Logging and observability
/// - Performance monitoring
/// - Debugging and diagnostics
/// - Custom telemetry collection
/// - Usage tracking
///
/// Example:
/// ```swift
/// struct MyObserver: AgentObserver {
///     func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async {
///         print("LegacyAgent started with: \(input)")
///     }
///
///     func onToolStart(context: AgentContext?, agent: any AgentRuntime, tool: any Tool, arguments: [String: SendableValue])
/// async {
///         print("Calling tool: \(tool.name)")
///     }
/// }
///
/// let agent = Agent(
///     tools: [...],
///     instructions: "...",
///     observers: [MyObserver(), LoggingObserver()]
/// )
/// ```
public protocol AgentObserver: Sendable {
    /// Called when an agent begins execution.
    ///
    /// - Parameters:
    ///   - context: LegacyAgent context for orchestration scenarios. `nil` when the agent is run standalone
    ///     (directly via `agent.run()` rather than through an orchestrator like `SupervisorAgent`).
    ///   - agent: The agent that is starting.
    ///   - input: The input string passed to the agent.
    func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async

    /// Called when an agent completes execution successfully.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that completed.
    ///   - result: The result produced by the agent.
    func onAgentEnd(context: AgentContext?, agent: any AgentRuntime, result: AgentResult) async

    /// Called when an agent encounters an error during execution.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that encountered the error.
    ///   - error: The error that occurred.
    func onError(context: AgentContext?, agent: any AgentRuntime, error: Error) async

    /// Called when an agent hands off execution to another agent.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - fromAgent: The agent initiating the handoff.
    ///   - toAgent: The agent receiving control.
    func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async

    /// Called when a tool execution begins.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent calling the tool.
    ///   - tool: The tool being executed.
    ///   - arguments: The arguments passed to the tool.
    func onToolStart(context: AgentContext?, agent: any AgentRuntime, call: ToolCall) async

    /// Called when tool call arguments are streamed (partial JSON fragments).
    ///
    /// This is emitted before tool execution begins and is intended for live UI.
    func onToolCallPartial(context: AgentContext?, agent: any AgentRuntime, update: PartialToolCallUpdate) async

    /// Called when a tool execution completes successfully.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that called the tool.
    ///   - tool: The tool that was executed.
    ///   - result: The result returned by the tool.
    func onToolEnd(context: AgentContext?, agent: any AgentRuntime, result: ToolResult) async

    /// Called when an LLM inference begins.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent making the LLM call.
    ///   - systemPrompt: The system prompt, if any.
    ///   - inputMessages: The input messages sent to the LLM.
    func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [MemoryMessage]) async

    /// Called when an LLM inference completes.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent that made the LLM call.
    ///   - response: The text response from the LLM.
    ///   - usage: Token usage statistics, if available.
    func onLLMEnd(context: AgentContext?, agent: any AgentRuntime, response: String, usage: TokenUsage?) async

    /// Called when a guardrail is triggered during execution.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - guardrailName: The name of the guardrail that was triggered.
    ///   - guardrailType: The type of guardrail (input, output, toolInput, toolOutput).
    ///   - result: The result of the guardrail check.
    func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async

    /// Called when an agent makes a thinking/reasoning step.
    ///
    /// - Parameters:
    ///   - context: Optional agent context.
    ///   - agent: The agent that is thinking.
    ///   - thought: The reasoning or thought content.
    func onThinking(context: AgentContext?, agent: any AgentRuntime, thought: String) async

    /// Called during streaming of a thinking/reasoning step.
    ///
    /// - Parameters:
    ///   - context: Optional agent context.
    ///   - agent: The agent that is thinking.
    ///   - partialThought: The partial reasoning or thought content.
    func onThinkingPartial(context: AgentContext?, agent: any AgentRuntime, partialThought: String) async

    /// Called when a response token is streamed from LLM.
    ///
    /// - Parameters:
    ///   - context: Optional agent context.
    ///   - agent: The agent receiving the token.
    ///   - token: The token string.
    func onOutputToken(context: AgentContext?, agent: any AgentRuntime, token: String) async

    /// Called when a new iteration begins in an agent loop.
    ///
    /// - Parameters:
    ///   - context: Optional agent context.
    ///   - agent: The agent starting an iteration.
    ///   - number: The iteration number (1-indexed).
    func onIterationStart(context: AgentContext?, agent: any AgentRuntime, number: Int) async

    /// Called when an iteration completes in an agent loop.
    ///
    /// - Parameters:
    ///   - context: Optional agent context.
    ///   - agent: The agent completing an iteration.
    ///   - number: The iteration number.
    func onIterationEnd(context: AgentContext?, agent: any AgentRuntime, number: Int) async

    /// Called before a retried provider inference attempt.
    ///
    /// Fired only when ``ResilienceConfiguration/retryPolicy`` allows retries and
    /// the previous attempt failed with a retryable error. `attempt` is 1-indexed
    /// (the first retry is `1`). The initial attempt does not invoke this hook.
    ///
    /// - Parameters:
    ///   - context: Optional agent context for orchestration scenarios.
    ///   - agent: The agent retrying inference.
    ///   - attempt: The retry number (1-indexed, excluding the original attempt).
    ///   - error: The error that triggered the retry.
    func onInferenceRetry(context: AgentContext?, agent: any AgentRuntime, attempt: Int, error: Error) async
}

// MARK: - AgentObserver Default Implementations

public extension AgentObserver {
    /// Default no-op implementation for agent start.
    func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input _: String) async {}

    /// Default no-op implementation for agent end.
    func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result _: AgentResult) async {}

    /// Default no-op implementation for errors.
    func onError(context _: AgentContext?, agent _: any AgentRuntime, error _: Error) async {}

    /// Default no-op implementation for handoffs.
    func onHandoff(context _: AgentContext?, fromAgent _: any AgentRuntime, toAgent _: any AgentRuntime) async {}

    /// Default no-op implementation for tool start.
    func onToolStart(context: AgentContext?, agent: any AgentRuntime, call: ToolCall) async {}

    /// Default no-op implementation for tool call partial updates.
    func onToolCallPartial(context: AgentContext?, agent: any AgentRuntime, update: PartialToolCallUpdate) async {}

    /// Default no-op implementation for tool end.
    func onToolEnd(context: AgentContext?, agent: any AgentRuntime, result: ToolResult) async {}

    /// Default no-op implementation for LLM start.
    func onLLMStart(context _: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages _: [MemoryMessage]) async {}

    /// Default no-op implementation for LLM end.
    func onLLMEnd(context _: AgentContext?, agent _: any AgentRuntime, response _: String, usage _: TokenUsage?) async {}

    /// Default no-op implementation for guardrail triggered.
    func onGuardrailTriggered(context _: AgentContext?, guardrailName _: String, guardrailType _: GuardrailType, result _: GuardrailResult) async {}

    /// Default no-op implementation for thinking.
    func onThinking(context _: AgentContext?, agent _: any AgentRuntime, thought _: String) async {}

    /// Default no-op implementation for partial thinking.
    func onThinkingPartial(context _: AgentContext?, agent _: any AgentRuntime, partialThought _: String) async {}

    /// Default no-op implementation for output tokens.
    func onOutputToken(context _: AgentContext?, agent _: any AgentRuntime, token _: String) async {}

    /// Default no-op implementation for iteration start.
    func onIterationStart(context _: AgentContext?, agent _: any AgentRuntime, number _: Int) async {}

    /// Default no-op implementation for iteration end.
    func onIterationEnd(context _: AgentContext?, agent _: any AgentRuntime, number _: Int) async {}

    /// Default no-op implementation for inference retries.
    func onInferenceRetry(context _: AgentContext?, agent _: any AgentRuntime, attempt _: Int, error _: Error) async {}
}

// MARK: - CompositeObserver

/// Composite hook implementation that delegates to multiple observer.
///
/// `CompositeObserver` allows combining multiple hook implementations so they
/// all receive callbacks. Hooks are executed **concurrently** using structured
/// concurrency for optimal performance.
///
/// - Important: Hooks are **scheduled** in registration order but execute **concurrently**.
///   Completion order is not guaranteed. For strictly ordered execution, use a single hook
///   that coordinates multiple handlers internally.
/// - Note: Hook implementations must be thread-safe and handle concurrent invocation.
///   Since `AgentObserver` methods are not `throws`, implementations cannot propagate errors.
///   Any internal errors should be logged rather than thrown.
///
/// Example:
/// ```swift
/// let composite = CompositeObserver(observers: [
///     LoggingObserver(),
///     MetricsObserver(),
///     CustomDebugObserver()
/// ])
///
/// let agent = Agent(
///     tools: [...],
///     instructions: "...",
///     observers: [composite]
/// )
/// ```
package struct CompositeObserver: AgentObserver {
    // MARK: Public

    // MARK: - Initialization

    /// Creates a composite hook that delegates to multiple observer.
    ///
    /// - Parameter observer: The observer to delegate to.
    package init(observers: [any AgentObserver]) {
        self.observers = observers
    }

    // MARK: - AgentObserver Implementation

    package func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onAgentStart(context: context, agent: agent, input: input)
                }
            }
        }
    }

    package func onAgentEnd(context: AgentContext?, agent: any AgentRuntime, result: AgentResult) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onAgentEnd(context: context, agent: agent, result: result)
                }
            }
        }
    }

    package func onError(context: AgentContext?, agent: any AgentRuntime, error: Error) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onError(context: context, agent: agent, error: error)
                }
            }
        }
    }

    package func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onHandoff(context: context, fromAgent: fromAgent, toAgent: toAgent)
                }
            }
        }
    }

    package func onToolStart(context: AgentContext?, agent: any AgentRuntime, call: ToolCall) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onToolStart(context: context, agent: agent, call: call)
                }
            }
        }
    }

    package func onToolCallPartial(context: AgentContext?, agent: any AgentRuntime, update: PartialToolCallUpdate) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onToolCallPartial(context: context, agent: agent, update: update)
                }
            }
        }
    }

    package func onToolEnd(context: AgentContext?, agent: any AgentRuntime, result: ToolResult) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onToolEnd(context: context, agent: agent, result: result)
                }
            }
        }
    }

    package func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [MemoryMessage]) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onLLMStart(context: context, agent: agent, systemPrompt: systemPrompt, inputMessages: inputMessages)
                }
            }
        }
    }

    package func onLLMEnd(context: AgentContext?, agent: any AgentRuntime, response: String, usage: TokenUsage?) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onLLMEnd(context: context, agent: agent, response: response, usage: usage)
                }
            }
        }
    }

    package func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onGuardrailTriggered(context: context, guardrailName: guardrailName, guardrailType: guardrailType, result: result)
                }
            }
        }
    }

    package func onThinking(context: AgentContext?, agent: any AgentRuntime, thought: String) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onThinking(context: context, agent: agent, thought: thought)
                }
            }
        }
    }

    package func onThinkingPartial(context: AgentContext?, agent: any AgentRuntime, partialThought: String) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onThinkingPartial(context: context, agent: agent, partialThought: partialThought)
                }
            }
        }
    }

    package func onOutputToken(context: AgentContext?, agent: any AgentRuntime, token: String) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onOutputToken(context: context, agent: agent, token: token)
                }
            }
        }
    }

    package func onIterationStart(context: AgentContext?, agent: any AgentRuntime, number: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onIterationStart(context: context, agent: agent, number: number)
                }
            }
        }
    }

    package func onIterationEnd(context: AgentContext?, agent: any AgentRuntime, number: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onIterationEnd(context: context, agent: agent, number: number)
                }
            }
        }
    }

    package func onInferenceRetry(context: AgentContext?, agent: any AgentRuntime, attempt: Int, error: Error) async {
        await withTaskGroup(of: Void.self) { group in
            for hook in observers {
                group.addTask {
                    await hook.onInferenceRetry(context: context, agent: agent, attempt: attempt, error: error)
                }
            }
        }
    }

    // MARK: Private

    /// The observer to delegate to.
    private let observers: [any AgentObserver]
}

// MARK: - LoggingObserver

/// Hook implementation that logs all agent events using swift-log.
///
/// `LoggingObserver` provides comprehensive logging of all agent lifecycle
/// events using the `Log.agents` logger. This is useful for debugging,
/// observability, and understanding agent execution flow.
///
/// Log levels:
/// - `.info`: LegacyAgent start/end, tool start/end, LLM start/end, handoff
/// - `.warning`: Guardrail triggered
/// - `.error`: Error events
///
/// Example:
/// ```swift
/// let agent = Agent(
///     tools: [...],
///     instructions: "...",
///     observers: [LoggingObserver()]
/// )
/// ```
public struct LoggingObserver: AgentObserver {
    // MARK: Public

    // MARK: - Initialization

    /// Creates a new logging hook.
    public init() {}

    // MARK: - AgentObserver Implementation

    public func onAgentStart(context: AgentContext?, agent _: any AgentRuntime, input: String) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let truncatedInput = input.count > 100 ? String(input.prefix(100)) + "..." : input
        Log.agents.info("LegacyAgent started\(contextId) - input: \"\(truncatedInput)\"")
    }

    public func onAgentEnd(context: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("LegacyAgent completed\(contextId) - iterations: \(result.iterationCount), duration: \(result.duration), tools: \(result.toolCalls.count)")
    }

    public func onError(context: AgentContext?, agent _: any AgentRuntime, error: Error) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.error("LegacyAgent error\(contextId) - \(error.localizedDescription)")
    }

    public func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let fromName = agentDisplayName(fromAgent)
        let toName = agentDisplayName(toAgent)
        Log.agents.info("LegacyAgent handoff\(contextId) - from: \(fromName) to: \(toName)")
    }

    public func onToolStart(context: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("Tool started\(contextId) - name: \(call.toolName), args: \(call.arguments.count) parameter(s)")
    }

    public func onToolEnd(context: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        // Can't easily get tool name here unless we look it up or it's added to ToolResult
        // For logging, we'll just log success/failure
        let status = result.isSuccess ? "succeeded" : "failed"
        Log.agents.info("Tool execution \(status)\(contextId) - duration: \(result.duration)")
    }

    public func onLLMStart(context: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages: [MemoryMessage]) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("LLM call started\(contextId) - messages: \(inputMessages.count)")
    }

    public func onLLMEnd(context: AgentContext?, agent _: any AgentRuntime, response _: String, usage: TokenUsage?) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let usageInfo = if let usage {
            ", tokens: \(usage.inputTokens) in / \(usage.outputTokens) out"
        } else {
            ""
        }
        Log.agents.info("LLM call completed\(contextId)\(usageInfo)")
    }

    public func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let message = result.message ?? "No message provided"
        Log.agents.warning("Guardrail triggered\(contextId) - name: \(guardrailName), type: \(guardrailType.rawValue), message: \(message)")
    }

    public func onThinking(context: AgentContext?, agent _: any AgentRuntime, thought: String) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        let truncatedThought = thought.count > 100 ? String(thought.prefix(100)) + "..." : thought
        Log.agents.info("LegacyAgent thinking\(contextId): \"\(truncatedThought)\"")
    }

    public func onOutputToken(context: AgentContext?, agent _: any AgentRuntime, token: String) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.debug("LegacyAgent output token\(contextId): \"\(token)\"")
    }

    public func onIterationStart(context: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.info("Iteration started\(contextId) - number: \(number)")
    }

    public func onInferenceRetry(context: AgentContext?, agent _: any AgentRuntime, attempt: Int, error: Error) async {
        let contextId = if let context {
            " [context: \(context.executionId)]"
        } else {
            ""
        }
        Log.agents.warning(
            "Inference retry\(contextId) - attempt: \(attempt), error: \(error.localizedDescription)"
        )
    }

    // MARK: Private

    // MARK: - Private Helpers

    /// Returns a display name for an agent, falling back to type name if configuration name is empty.
    private func agentDisplayName(_ agent: any AgentRuntime) -> String {
        let name = agent.configuration.name
        return name.isEmpty ? String(describing: type(of: agent)) : name
    }
}
