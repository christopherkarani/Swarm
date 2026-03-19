// AgentError.swift
// Swarm Framework
//
// Comprehensive error types for agent operations.

import Foundation

// MARK: - AgentError

/// Errors that can occur during agent execution.
///
/// `AgentError` represents the various failure modes that can occur
/// when running an agent. Each case includes context to help diagnose
/// and recover from the error.
///
/// ## Error Handling
///
/// Catch specific errors to handle them appropriately:
///
/// ```swift
/// do {
///     let result = try await agent.run("Task")
/// } catch let error as AgentError {
///     switch error {
///     case .maxIterationsExceeded:
///         print("Agent needed more iterations")
///     case .toolExecutionFailed(let name, let underlying):
///         print("Tool '\(name)' failed: \(underlying)")
///     case .rateLimitExceeded(let retryAfter):
///         if let delay = retryAfter {
///             try await Task.sleep(for: .seconds(delay))
///             // Retry...
///         }
///     default:
///         print("Error: \(error.localizedDescription)")
///     }
/// }
/// ```
///
/// ## Retryable Errors
///
/// Some errors are transient and can be retried:
/// - ``rateLimitExceeded(retryAfter:)``
/// - ``inferenceProviderUnavailable(reason:)``
/// - ``generationFailed(reason:)``
///
/// ## Error Categories
///
/// Errors are organized into categories based on their source:
///
/// ### Input Errors
/// - ``invalidInput(reason:)``
///
/// ### Execution Errors
/// - ``cancelled``
/// - ``maxIterationsExceeded(iterations:)``
/// - ``timeout(duration:)``
/// - ``invalidLoop(reason:)``
///
/// ### Tool Errors
/// - ``toolNotFound(name:)``
/// - ``toolExecutionFailed(toolName:underlyingError:)``
/// - ``invalidToolArguments(toolName:reason:)``
///
/// ### Model Errors
/// - ``inferenceProviderUnavailable(reason:)``
/// - ``contextWindowExceeded(tokenCount:limit:)``
/// - ``guardrailViolation(reason:)``
/// - ``contentFiltered(reason:)``
/// - ``unsupportedLanguage(language:)``
/// - ``generationFailed(reason:)``
/// - ``modelNotAvailable(model:)``
///
/// ### Rate Limiting Errors
/// - ``rateLimitExceeded(retryAfter:)``
///
/// ### Embedding Errors
/// - ``embeddingFailed(reason:)``
///
/// ### Internal Errors
/// - ``agentNotFound(name:)``
/// - ``internalError(reason:)``
/// - ``toolCallingRequiresCloudProvider``
///
/// ## See Also
/// - ``GuardrailError``
/// - ``WorkflowError``
public enum AgentError: Error, Sendable, Equatable {

    // MARK: - Input Errors

    /// The input provided to the agent was empty or invalid.
    ///
    /// This error is thrown when:
    /// - The input string is empty or whitespace-only
    /// - The input exceeds maximum length limits
    /// - The input contains invalid characters or encoding
    /// - The input violates input schema constraints
    ///
    /// ## Recovery
    ///
    /// Validate input before sending:
    ///
    /// ```swift
    /// guard !input.trimmingCharacters(in: .whitespaces).isEmpty else {
    ///     // Handle empty input
    ///     return
    /// }
    /// ```
    ///
    /// - Parameter reason: A description of why the input was invalid
    case invalidInput(reason: String)

    // MARK: - Execution Errors

    /// The agent was cancelled before completion.
    ///
    /// This error is thrown when:
    /// - The `Task` running the agent is cancelled
    /// - An explicit cancellation token is triggered
    /// - A parent task is cancelled, propagating cancellation
    ///
    /// ## Recovery
    ///
    /// Check for cancellation before retrying:
    ///
    /// ```swift
    /// do {
    ///     let result = try await agent.run(task)
    /// } catch AgentError.cancelled {
    ///     // Clean up and exit
    ///     return
    /// }
    /// ```
    ///
    /// ## Note
    /// This error is non-retryable. The operation was intentionally stopped.
    case cancelled

    /// The agent exceeded the maximum number of iterations.
    ///
    /// This error is thrown when an agent performs more reasoning steps
    /// than allowed by the `maxIterations` configuration. This typically
    /// indicates:
    /// - The task is too complex for the current limit
    /// - The agent is stuck in a loop
    /// - Tool calls are not resolving the task
    ///
    /// ## Recovery
    ///
    /// Increase the iteration limit or break the task into smaller subtasks:
    ///
    /// ```swift
    /// let config = AgentConfiguration(
    ///     maxIterations: 50  // Increase from default
    /// )
    /// let agent = Agent(configuration: config)
    /// ```
    ///
    /// - Parameter iterations: The number of iterations that were performed
    ///                         before the limit was exceeded
    case maxIterationsExceeded(iterations: Int)

    /// The agent execution timed out.
    ///
    /// This error is thrown when agent execution exceeds the configured
    /// timeout duration. This can occur due to:
    /// - Slow model inference responses
    /// - Long-running tool executions
    /// - Network latency with cloud providers
    ///
    /// ## Recovery
    ///
    /// Increase the timeout or implement chunked processing:
    ///
    /// ```swift
    /// let config = AgentConfiguration(
    ///     timeout: .seconds(120)  // Increase from default
    /// )
    /// ```
    ///
    /// - Parameter duration: The duration after which the timeout occurred
    case timeout(duration: Duration)

    /// The agent's declarative loop is invalid.
    ///
    /// This error is thrown when the agent's loop configuration contains
    /// logical errors such as:
    /// - Invalid state transitions
    /// - Missing required states
    /// - Circular dependencies in state graph
    /// - Invalid loop conditions
    ///
    /// ## Recovery
    ///
    /// Review and fix the loop configuration:
    ///
    /// ```swift
    /// // Ensure all states have valid transitions
    /// let loop = AgentLoop(
    ///     states: [
    ///         .start: .init(transitions: [.process]),
    ///         .process: .init(transitions: [.complete, .error]),
    ///         .complete: .init(transitions: []),
    ///         .error: .init(transitions: [])
    ///     ]
    /// )
    /// ```
    ///
    /// - Parameter reason: A description of why the loop is invalid
    case invalidLoop(reason: String)

    // MARK: - Tool Errors

    /// A tool with the given name was not found.
    ///
    /// This error is thrown when:
    /// - The agent attempts to call a tool that doesn't exist
    /// - A tool name is misspelled in the configuration
    /// - A required tool was not registered with the agent
    ///
    /// ## Recovery
    ///
    /// Ensure all tools are properly registered:
    ///
    /// ```swift
    /// let agent = Agent(
    ///     tools: [calculatorTool, searchTool]
    /// )
    ///
    /// // Verify tool names match what the model might request
    /// for tool in agent.tools {
    ///     print("Available: \(tool.name)")
    /// }
    /// ```
    ///
    /// - Parameter name: The name of the tool that was not found
    case toolNotFound(name: String)

    /// A tool failed to execute.
    ///
    /// This error is thrown when a tool's execution function throws an
    /// error or returns an unexpected result. Common causes include:
    /// - Network failures in API-based tools
    /// - File system errors in file tools
    /// - Invalid tool implementation
    ///
    /// ## Recovery
    ///
    /// Implement retry logic with exponential backoff:
    ///
    /// ```swift
    /// } catch let error as AgentError {
    ///     if case .toolExecutionFailed(let name, let underlying) = error {
    ///         if isTransientError(underlying) {
    ///             // Retry with backoff
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that failed
    ///   - underlyingError: A string description of the underlying error
    case toolExecutionFailed(toolName: String, underlyingError: String)

    /// Invalid arguments were provided to a tool.
    ///
    /// This error is thrown when:
    /// - Required parameters are missing
    /// - Parameter types don't match the schema
    /// - Parameter values are out of valid range
    /// - The model generated invalid tool call arguments
    ///
    /// ## Recovery
    ///
    /// Improve tool description or add validation:
    ///
    /// ```swift
    /// let tool = Tool(
    ///     name: "calculate",
    ///     parameters: [
    ///         .init(
    ///             name: "expression",
    ///             type: .string,
    ///             description: "A valid mathematical expression",
    ///             required: true
    ///         )
    ///     ]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that received invalid arguments
    ///   - reason: A description of why the arguments were invalid
    case invalidToolArguments(toolName: String, reason: String)

    // MARK: - Model Errors

    /// The inference provider is not available.
    ///
    /// This error is thrown when:
    /// - The configured inference provider cannot be reached
    /// - API credentials are invalid or missing
    /// - The local model is not properly loaded
    /// - Network connectivity issues
    ///
    /// ## Recovery
    ///
    /// Retry with fallback provider or check configuration:
    ///
    /// ```swift
    /// do {
    ///     return try await primaryProvider.generate(prompt)
    /// } catch AgentError.inferenceProviderUnavailable {
    ///     // Fallback to secondary provider
    ///     return try await fallbackProvider.generate(prompt)
    /// }
    /// ```
    ///
    /// - Parameter reason: A description of why the provider is unavailable
    case inferenceProviderUnavailable(reason: String)

    /// The model context window was exceeded.
    ///
    /// This error is thrown when the total token count (input + generated)
    /// exceeds the model's context window limit. This commonly occurs:
    /// - With long conversation histories
    /// - When large documents are processed
    /// - With recursive tool outputs
    ///
    /// ## Recovery
    ///
    /// Implement context window management:
    ///
    /// ```swift
    /// // Truncate or summarize conversation history
    /// let trimmedHistory = conversation.history.suffix(10)
    ///
    /// // Or use a model with larger context
    /// let config = AgentConfiguration(
    ///     model: .claudeSonnet  // Larger context window
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - tokenCount: The actual number of tokens in the context
    ///   - limit: The maximum token limit for the model
    case contextWindowExceeded(tokenCount: Int, limit: Int)

    /// The model response violated content guidelines.
    ///
    /// This error is thrown when the model generates content that violates
    /// configured guardrails or safety policies. This may indicate:
    /// - Harmful content generation attempts
    /// - Policy violations in the request
    /// - Misaligned safety thresholds
    ///
    /// ## Recovery
    ///
    /// Review the request and adjust guardrails if needed:
    ///
    /// ```swift
    /// let config = AgentConfiguration(
    ///     guardrails: GuardrailConfiguration(
    ///         blockedTopics: [...],
    ///         allowedDomains: [...]
    ///     )
    /// )
    /// ```
    ///
    /// - Parameter reason: A description of which guideline was violated
    case guardrailViolation(reason: String)

    /// Content was filtered by the model's safety systems.
    ///
    /// This error is thrown when the model's built-in safety filters
    /// block content generation. This differs from ``guardrailViolation(reason:)``
    /// in that it comes from the model provider's safety systems rather than
    /// application-defined guardrails.
    ///
    /// ## Recovery
    ///
    /// Rephrase the request or adjust safety settings:
    ///
    /// ```swift
    /// // Try with a more neutral prompt
    /// let result = try await agent.run(rephrasedPrompt)
    /// ```
    ///
    /// - Parameter reason: A description of why the content was filtered
    case contentFiltered(reason: String)

    /// The language is not supported by the model.
    ///
    /// This error is thrown when the input or requested output language
    /// is not supported by the configured model. This may occur:
    /// - With low-resource languages
    /// - When using specialized models with limited language support
    ///
    /// ## Recovery
    ///
    /// Switch to a model with broader language support:
    ///
    /// ```swift
    /// let config = AgentConfiguration(
    ///     model: .claudeSonnet  // Supports many languages
    /// )
    /// ```
    ///
    /// - Parameter language: The language code that is not supported
    case unsupportedLanguage(language: String)

    /// The model failed to generate a response.
    ///
    /// This error is thrown when the model encounters an internal error
    /// during generation. This is typically a transient error that may
    /// resolve on retry.
    ///
    /// ## Recovery
    ///
    /// Retry with exponential backoff:
    ///
    /// ```swift
    /// for attempt in 1...3 {
    ///     do {
    ///         return try await agent.run(prompt)
    ///     } catch AgentError.generationFailed {
    ///         if attempt < 3 {
    ///             try await Task.sleep(for: .seconds(Double(attempt) * 2))
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter reason: A description of why generation failed
    case generationFailed(reason: String)

    /// The requested model is not available.
    ///
    /// This error is thrown when:
    /// - The specified model name doesn't exist
    /// - The model is deprecated or removed
    /// - The model is not accessible with current credentials
    /// - A local model file is missing or corrupted
    ///
    /// ## Recovery
    ///
    /// Check available models and update configuration:
    ///
    /// ```swift
    /// // List available models
    /// let models = await provider.availableModels()
    ///
    /// // Use a valid model
    /// let config = AgentConfiguration(model: .gpt4)
    /// ```
    ///
    /// - Parameter model: The name of the unavailable model
    case modelNotAvailable(model: String)

    // MARK: - Rate Limiting Errors

    /// Rate limit was exceeded.
    ///
    /// This error is thrown when API rate limits are exceeded. Most providers
    /// return this with a retry-after header indicating when to retry.
    ///
    /// ## Recovery
    ///
    /// Wait for the specified duration before retrying:
    ///
    /// ```swift
    /// } catch AgentError.rateLimitExceeded(let retryAfter) {
    ///     if let delay = retryAfter {
    ///         try await Task.sleep(for: .seconds(delay))
    ///         // Retry the request
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter retryAfter: The recommended delay in seconds before retrying,
    ///                         or `nil` if not specified by the provider
    case rateLimitExceeded(retryAfter: TimeInterval?)

    // MARK: - Embedding Errors

    /// Embedding operation failed.
    ///
    /// This error is thrown when text embedding generation fails.
    /// Common causes include:
    /// - Embedding model unavailability
    /// - Text too long for embedding model
    /// - Vector database connection issues
    ///
    /// ## Recovery
    ///
    /// Retry with text chunking:
    ///
    /// ```swift
    /// // Split long text into chunks
    /// let chunks = longText.chunked(maxLength: 1000)
    /// let embeddings = try await chunks.asyncMap { chunk in
    ///     try await embeddingProvider.embed(chunk)
    /// }
    /// ```
    ///
    /// - Parameter reason: A description of why embedding failed
    case embeddingFailed(reason: String)

    // MARK: - Internal Errors

    /// An agent with the specified name was not registered.
    ///
    /// This error is thrown when attempting to reference an agent by name
    /// that hasn't been registered with the swarm or workflow.
    ///
    /// ## Recovery
    ///
    /// Register the agent before use:
    ///
    /// ```swift
    /// swarm.register(agent, name: "researcher")
    ///
    /// // Now you can reference it
    /// let result = try await swarm.handoff(
    ///     to: "researcher",  // This will succeed
    ///     task: "Research topic"
    /// )
    /// ```
    ///
    /// - Parameter name: The name of the unregistered agent
    case agentNotFound(name: String)

    /// An internal error occurred.
    ///
    /// This error is thrown for unexpected internal failures that don't
    /// fit into other categories. This typically indicates:
    /// - A bug in the Swarm framework
    /// - Unexpected state corruption
    /// - Internal assertion failures
    ///
    /// ## Recovery
    ///
    /// Report the error and consider restarting the agent:
    ///
    /// ```swift
    /// } catch AgentError.internalError(let reason) {
    ///     logger.critical("Swarm internal error: \(reason)")
    ///     // Recreate agent or restart service
    /// }
    /// ```
    ///
    /// - Parameter reason: A description of the internal error
    case internalError(reason: String)

    /// Tool calling was requested but the selected provider path could not satisfy it.
    ///
    /// This error is thrown when:
    /// - A local provider is configured but the request requires cloud-based tool calling
    /// - The provider doesn't support native tool calling and prompt-based emulation is disabled
    /// - The tool calling schema is incompatible with the provider
    ///
    /// ## Recovery
    ///
    /// Configure a cloud provider with native tool support:
    ///
    /// ```swift
    /// Swarm.configure(cloudProvider: openAIProvider)
    ///
    /// // Or enable prompt-based tool emulation
    /// let config = AgentConfiguration(
    ///     allowPromptBasedTools: true
    /// )
    /// ```
    ///
    /// ## Note
    /// See ``recoverySuggestion`` for the default recovery suggestion.
    case toolCallingRequiresCloudProvider
}

// MARK: - LocalizedError

extension AgentError: LocalizedError {

    /// A localized description of the error suitable for display to users.
    ///
    /// This property provides human-readable descriptions for each error case,
    /// suitable for displaying in UI alerts or logs.
    public var errorDescription: String? {
        switch self {
        case let .invalidInput(reason):
            "Invalid input: \(reason)"
        case .cancelled:
            "Agent execution was cancelled"
        case let .maxIterationsExceeded(iterations):
            "Agent exceeded maximum iterations (\(iterations))"
        case let .timeout(duration):
            "Agent execution timed out after \(duration)"
        case let .invalidLoop(reason):
            "Invalid agent loop: \(reason)"
        case let .toolNotFound(name):
            "Tool not found: \(name)"
        case let .toolExecutionFailed(toolName, underlyingError):
            "Tool '\(toolName)' failed: \(underlyingError)"
        case let .invalidToolArguments(toolName, reason):
            "Invalid arguments for tool '\(toolName)': \(reason)"
        case let .inferenceProviderUnavailable(reason):
            "Inference provider unavailable: \(reason)"
        case let .contextWindowExceeded(count, limit):
            "Context window exceeded: \(count) tokens (limit: \(limit))"
        case let .guardrailViolation(reason):
            "Response violated content guidelines: \(reason)"
        case let .contentFiltered(reason):
            "Content filtered: \(reason)"
        case let .unsupportedLanguage(language):
            "Language not supported: \(language)"
        case let .generationFailed(reason):
            "Generation failed: \(reason)"
        case let .modelNotAvailable(model):
            "Model not available: \(model)"
        case let .rateLimitExceeded(retryAfter):
            if let retryAfter {
                "Rate limit exceeded, retry after \(retryAfter) seconds"
            } else {
                "Rate limit exceeded"
            }
        case let .embeddingFailed(reason):
            "Embedding failed: \(reason)"
        case let .agentNotFound(name):
            "Agent not found: '\(name)'"
        case let .internalError(reason):
            "Internal error: \(reason)"
        case .toolCallingRequiresCloudProvider:
            "The selected provider could not satisfy this tool calling request."
        }
    }

    /// A localized recovery suggestion for the error.
    ///
    /// This property provides actionable guidance on how to recover from
    /// specific error cases. Not all errors include recovery suggestions.
    ///
    /// ## See Also
    /// - ``AgentError/toolCallingRequiresCloudProvider``
    public var recoverySuggestion: String? {
        switch self {
        case .toolCallingRequiresCloudProvider:
            "Configure `Swarm.configure(cloudProvider:)` or pass a provider with native tool-calling support if this request cannot rely on prompt-based tool emulation."
        case .inferenceProviderUnavailable:
            "Check your network connection and API credentials, or try again later."
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                "Wait \(Int(seconds)) seconds before retrying the request."
            } else {
                "Wait a moment before retrying the request."
            }
        case .contextWindowExceeded:
            "Reduce the conversation history length or use a model with a larger context window."
        case .toolNotFound(let name):
            "Ensure the tool '\(name)' is registered with the agent and the name is spelled correctly."
        case .modelNotAvailable(let model):
            "Check that '\(model)' is a valid model name and your API key has access to it."
        case .maxIterationsExceeded:
            "Increase the maxIterations configuration or break the task into smaller subtasks."
        case .timeout:
            "Increase the timeout duration or optimize the task to complete faster."
        case .invalidToolArguments(let toolName, _):
            "Review the tool '\(toolName)' documentation and ensure all required parameters are provided."
        default:
            nil
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension AgentError: CustomDebugStringConvertible {

    /// A debug description of the error with detailed context.
    ///
    /// This property provides detailed debug information including all
    /// associated values, suitable for logging and debugging.
    public var debugDescription: String {
        switch self {
        case let .invalidInput(reason):
            "AgentError.invalidInput(reason: \(reason))"
        case .cancelled:
            "AgentError.cancelled"
        case let .maxIterationsExceeded(iterations):
            "AgentError.maxIterationsExceeded(iterations: \(iterations))"
        case let .timeout(duration):
            "AgentError.timeout(duration: \(duration))"
        case let .invalidLoop(reason):
            "AgentError.invalidLoop(reason: \(reason))"
        case let .toolNotFound(name):
            "AgentError.toolNotFound(name: \(name))"
        case let .toolExecutionFailed(toolName, underlyingError):
            "AgentError.toolExecutionFailed(toolName: \(toolName), underlyingError: \(underlyingError))"
        case let .invalidToolArguments(toolName, reason):
            "AgentError.invalidToolArguments(toolName: \(toolName), reason: \(reason))"
        case let .inferenceProviderUnavailable(reason):
            "AgentError.inferenceProviderUnavailable(reason: \(reason))"
        case let .contextWindowExceeded(tokenCount, limit):
            "AgentError.contextWindowExceeded(tokenCount: \(tokenCount), limit: \(limit))"
        case let .guardrailViolation(reason):
            "AgentError.guardrailViolation(reason: \(reason))"
        case let .contentFiltered(reason):
            "AgentError.contentFiltered(reason: \(reason))"
        case let .unsupportedLanguage(language):
            "AgentError.unsupportedLanguage(language: \(language))"
        case let .generationFailed(reason):
            "AgentError.generationFailed(reason: \(reason))"
        case let .modelNotAvailable(model):
            "AgentError.modelNotAvailable(model: \(model))"
        case let .rateLimitExceeded(retryAfter):
            "AgentError.rateLimitExceeded(retryAfter: \(String(describing: retryAfter)))"
        case let .embeddingFailed(reason):
            "AgentError.embeddingFailed(reason: \(reason))"
        case let .agentNotFound(name):
            "AgentError.agentNotFound(name: \(name))"
        case let .internalError(reason):
            "AgentError.internalError(reason: \(reason))"
        case .toolCallingRequiresCloudProvider:
            "AgentError.toolCallingRequiresCloudProvider"
        }
    }
}
