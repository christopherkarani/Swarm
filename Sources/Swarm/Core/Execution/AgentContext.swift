// AgentContext.swift
// Swarm Framework
//
// Shared context for multi-agent orchestration execution.

import Foundation

// MARK: - AgentContextKey

/// Predefined keys for common agent context values.
///
/// Use these standardized keys when storing and retrieving common
/// orchestration data from `AgentContext`.
///
/// Example:
/// ```swift
/// await context.set(.originalInput, value: .string("User query"))
/// if let input = await context.get(.originalInput)?.stringValue {
///     print("Original: \(input)")
/// }
/// ```
public enum AgentContextKey: String, Sendable {
    /// The original input that started orchestration.
    case originalInput = "original_input"

    /// The output from the previous agent in the chain.
    case previousOutput = "previous_output"

    /// The name of the current executing agent.
    case currentAgentName = "current_agent_name"

    /// The execution path (list of agent names).
    case executionPath = "execution_path"

    /// The start time of orchestration.
    case startTime = "start_time"

    /// General metadata storage.
    case metadata
}

// MARK: - AgentContextProviding

/// A protocol for providing typed context to agents and tools.
///
/// Conform to this protocol to create strongly-typed context objects
/// that can be stored in and retrieved from `AgentContext`, eliminating
/// stringly-typed dictionary access patterns.
///
/// Example:
/// ```swift
/// struct UserContext: AgentContextProviding {
///     static let contextKey = "user_context"
///     let userId: String
///     let isAdmin: Bool
/// }
///
/// // Store:
/// await context.setTyped(UserContext(userId: "123", isAdmin: true))
///
/// // Retrieve:
/// if let user: UserContext = await context.typed(UserContext.self) {
///     print(user.userId)
/// }
/// ```
public protocol AgentContextProviding: Sendable {
    /// The key used to store this context in the key-value storage.
    static var contextKey: String { get }
}

// MARK: - AgentContext

/// Thread-safe shared context for multi-agent orchestration.
///
/// `AgentContext` provides a centralized store for data that needs to be
/// shared across multiple agents during orchestration. It maintains:
/// - Key-value storage for arbitrary data
/// - Message history for conversation continuity
/// - Execution path tracking for observability
///
/// The context is implemented as an actor to ensure thread-safe access
/// across concurrent agent executions.
///
/// Example:
/// ```swift
/// let context = AgentContext(input: "Analyze sales data")
/// await context.set("department", value: .string("sales"))
///
/// // LegacyAgent 1 runs
/// await context.recordExecution(agentName: "DataFetcher")
/// await context.addMessage(.user("Fetch Q4 sales"))
///
/// // LegacyAgent 2 runs
/// await context.recordExecution(agentName: "Analyzer")
/// let path = await context.getExecutionPath()
/// // ["DataFetcher", "Analyzer"]
/// ```
public actor AgentContext {
    // MARK: Public

    /// The original input that started orchestration.
    nonisolated public let originalInput: String

    /// Unique identifier for this execution.
    nonisolated public let executionId: UUID

    /// When this context was created.
    nonisolated public let createdAt: Date

    /// All current keys in the context.
    public var allKeys: [String] {
        Array(values.keys)
    }

    /// A snapshot copy of all values.
    ///
    /// Returns a copy of the current key-value storage.
    /// Changes to the returned dictionary do not affect the context.
    public var snapshot: [String: SendableValue] {
        values
    }

    // MARK: - Initialization

    /// Creates a new agent context.
    ///
    /// - Parameters:
    ///   - input: The original input that started orchestration.
    ///   - initialValues: Optional initial key-value pairs. Default: [:]
    public init(input: String, initialValues: [String: SendableValue] = [:]) {
        originalInput = input
        executionId = TurnEnvironment.live.newUUID()
        createdAt = TurnEnvironment.live.now()
        values = initialValues
        messages = []
        executionPath = []

        // Store original input in values
        values[AgentContextKey.originalInput.rawValue] = .string(input)
        values[AgentContextKey.startTime.rawValue] = .double(createdAt.timeIntervalSince1970)
    }

    // MARK: - Key-Value Storage

    /// Retrieves a value by string key.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The stored value, or nil if not found.
    public func get(_ key: String) -> SendableValue? {
        values[key]
    }

    /// Retrieves a value by predefined context key.
    ///
    /// - Parameter key: The context key to look up.
    /// - Returns: The stored value, or nil if not found.
    public func get(_ key: AgentContextKey) -> SendableValue? {
        values[key.rawValue]
    }

    /// Stores a value by string key.
    ///
    /// - Parameters:
    ///   - key: The key to store under.
    ///   - value: The value to store.
    public func set(_ key: String, value: SendableValue) {
        values[key] = value
    }

    /// Stores a value by predefined context key.
    ///
    /// - Parameters:
    ///   - key: The context key to store under.
    ///   - value: The value to store.
    public func set(_ key: AgentContextKey, value: SendableValue) {
        values[key.rawValue] = value
    }

    /// Removes a value by string key.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: The removed value, or nil if not found.
    @discardableResult
    public func remove(_ key: String) -> SendableValue? {
        values.removeValue(forKey: key)
    }

    // MARK: - Message Management

    /// Adds a message to the context's history.
    ///
    /// - Parameter message: The message to add.
    public func addMessage(_ message: MemoryMessage) {
        messages.append(message)
    }

    /// Gets all stored messages.
    ///
    /// Returns a snapshot copy of the message history. Modifications to the
    /// returned array do not affect the context's internal state.
    ///
    /// - Returns: Array of all messages in chronological order.
    public func getMessages() -> [MemoryMessage] {
        Array(messages)
    }

    /// Clears all stored messages.
    public func clearMessages() {
        messages.removeAll()
    }

    // MARK: - Execution Tracking

    /// Records that an agent has executed.
    ///
    /// Adds the agent name to the execution path for tracking
    /// the sequence of agents that have run.
    ///
    /// - Parameter agentName: The name of the agent that executed.
    public func recordExecution(agentName: String) {
        executionPath.append(agentName)
        values[AgentContextKey.executionPath.rawValue] = .array(
            executionPath.map { .string($0) }
        )
        values[AgentContextKey.currentAgentName.rawValue] = .string(agentName)
    }

    /// Gets the execution path.
    ///
    /// - Returns: Array of agent names in execution order.
    public func getExecutionPath() -> [String] {
        executionPath
    }

    // MARK: - Previous Output

    /// Stores the previous agent's output.
    ///
    /// This is a convenience method that extracts the output from
    /// an `AgentResult` and stores it under the `previousOutput` key.
    ///
    /// - Parameter result: The result from the previous agent.
    public func setPreviousOutput(_ result: AgentResult) {
        values[AgentContextKey.previousOutput.rawValue] = .string(result.output)
    }

    /// Gets the previous agent's output.
    ///
    /// - Returns: The previous output, or nil if not set.
    public func getPreviousOutput() -> String? {
        values[AgentContextKey.previousOutput.rawValue]?.stringValue
    }

    // MARK: - Merging

    /// Merges values from another context into this one.
    ///
    /// This is useful for combining contexts or inheriting values
    /// from a parent orchestration context.
    ///
    /// - Parameters:
    ///   - other: The context to merge from.
    ///   - overwrite: Whether to overwrite existing keys. Default: false
    ///
    /// Example:
    /// ```swift
    /// await context.merge(from: parentContext, overwrite: false)
    /// // Only adds keys that don't exist in current context
    /// ```
    public func merge(from other: AgentContext, overwrite: Bool = false) async {
        let otherSnapshot = await other.snapshot

        for (key, value) in otherSnapshot {
            if overwrite || values[key] == nil {
                values[key] = value
            }
        }

        // Merge messages
        let otherMessages = await other.getMessages()
        for message in otherMessages where !messages.contains(where: { $0.id == message.id }) {
            // Avoid duplicates by checking message ID
            messages.append(message)
        }

        // Merge execution path
        let otherPath = await other.getExecutionPath()
        for agentName in otherPath where !executionPath.contains(agentName) {
            executionPath.append(agentName)
        }
    }

    // MARK: - Copying

    /// Creates a copy of this context with optional additional values.
    ///
    /// This creates a new context with the same original input but
    /// copies all current state. Useful for branching orchestration.
    ///
    /// - Parameter additionalValues: Extra key-value pairs to add. Default: [:]
    /// - Returns: A new context with copied state.
    ///
    /// Example:
    /// ```swift
    /// let childContext = await context.copy(
    ///     additionalValues: ["branch": .string("experimental")]
    /// )
    /// ```
    public func copy(additionalValues: [String: SendableValue] = [:]) -> AgentContext {
        var copiedValues = values

        // Add additional values
        for (key, value) in additionalValues {
            copiedValues[key] = value
        }

        let newContext = AgentContext(input: originalInput, initialValues: copiedValues)

        // Note: Messages and execution path are not copied to the new context
        // to avoid confusion. They are instance-specific.
        // If needed, use merge() after creating the copy.

        return newContext
    }

    // MARK: - Typed Context

    /// Stores a typed context object.
    ///
    /// The context is stored under its `contextKey` and can be retrieved
    /// using `typed(_:)`.
    ///
    /// - Parameter context: The typed context to store.
    public func setTyped<T: AgentContextProviding>(_ context: T) {
        typedContexts[T.contextKey] = context
    }

    /// Retrieves a typed context object.
    ///
    /// - Parameter type: The type of context to retrieve.
    /// - Returns: The stored context, or nil if not found or wrong type.
    public func typed<T: AgentContextProviding>(_: T.Type) -> T? {
        typedContexts[T.contextKey] as? T
    }

    /// Removes a typed context.
    ///
    /// - Parameter type: The type of context to remove.
    /// - Returns: The removed context, or nil if not found.
    @discardableResult
    public func removeTyped<T: AgentContextProviding>(_: T.Type) -> T? {
        typedContexts.removeValue(forKey: T.contextKey) as? T
    }

    /// Returns true if a typed context of the given type is stored.
    ///
    /// - Parameter type: The type to check for.
    /// - Returns: Whether a context of this type exists.
    public func hasTyped<T: AgentContextProviding>(_: T.Type) -> Bool {
        typedContexts[T.contextKey] != nil
    }

    // MARK: Private

    // MARK: - Private Storage

    /// Key-value storage for arbitrary data.
    private var values: [String: SendableValue]

    /// Message history for conversation continuity.
    private var messages: [MemoryMessage]

    /// List of agent names that have executed.
    private var executionPath: [String]

    /// Typed context storage keyed by context key string.
    private var typedContexts: [String: any AgentContextProviding] = [:]
}

// MARK: CustomStringConvertible

extension AgentContext: CustomStringConvertible {
    nonisolated public var description: String {
        """
        AgentContext(
            executionId: \(executionId),
            input: "\(originalInput.prefix(50))\(originalInput.count > 50 ? "..." : "")",
            createdAt: \(createdAt)
        )
        """
    }
}

// MARK: CustomDebugStringConvertible

extension AgentContext: CustomDebugStringConvertible {
    nonisolated public var debugDescription: String {
        """
        AgentContext(
            executionId: \(executionId),
            originalInput: "\(originalInput)",
            createdAt: \(createdAt)
        )
        """
    }
}
