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
/// - Deprecated: Store typed values with ``ContextKey`` instead. Define a
/// `ContextKey<Value>` for your value type and use
/// ``AgentContext/setTyped(_:value:)`` /
/// ``AgentContext/getTyped(_:)``, which pair keys and values at compile
/// time. This protocol remains functional over the unified context store
/// but will be removed in a future release.
///
/// Example:
/// ```swift
/// extension ContextKey where Value == String {
///     static let userContext = ContextKey("user_context")
/// }
///
/// struct UserContext: Codable, Sendable {
///     let userId: String
///     let isAdmin: Bool
/// }
///
/// // Store:
/// await context.setTyped(.userContext, value: UserContext(userId: "123", isAdmin: true))
///
/// // Retrieve:
/// if let user = await context.getTyped(.userContext) {
///     print(user.userId)
/// }
/// ```
@available(
    *,
    deprecated,
    message: "Use ContextKey<Value> with setTyped(_:value:)/getTyped(_:) instead"
)
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
    ///
    /// Includes raw string keys plus the names of any typed slots written
    /// through `setTyped(_:value:)`.
    public var allKeys: [String] {
        var keys = Array(values.keys)
        for name in slots.valueNames where values[name] == nil {
            keys.append(name)
        }
        return keys
    }

    /// A snapshot copy of all values.
    ///
    /// Returns a copy of the current key-value storage with typed slot
    /// payloads projected in by name. Raw namespace entries take precedence
    /// over same-named typed slots; when several typed slots share a name
    /// across different value types, the most recently written one wins.
    /// Changes to the returned dictionary do not affect the context.
    public var snapshot: [String: SendableValue] {
        var projected = values
        for (name, payload) in slots.projectedValues() where projected[name] == nil {
            projected[name] = payload
        }
        return projected
    }

    // MARK: - Initialization

    /// Creates a new agent context.
    ///
    /// - Parameters:
    ///   - input: The original input that started orchestration.
    ///   - initialValues: Optional initial key-value pairs. Default: [:]
    public init(input: String, initialValues: [String: SendableValue] = [:]) {
        self.init(input: input, initialValues: initialValues, slots: ContextSlotStore())
    }

    /// Creates a new agent context preloaded with typed slots.
    ///
    /// Package-internal seed used by `copy(additionalValues:)` to carry
    /// typed slot state into the new context.
    ///
    /// - Parameters:
    ///   - input: The original input that started orchestration.
    ///   - initialValues: Initial raw key-value pairs.
    ///   - slots: Typed slots carried over from a source context.
    init(input: String, initialValues: [String: SendableValue], slots: ContextSlotStore) {
        originalInput = input
        executionId = TurnEnvironment.live.newUUID()
        createdAt = TurnEnvironment.live.now()
        values = initialValues
        self.slots = slots
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
        let otherRawValues = await other.rawValues()
        let otherSlots = await other.valueSlotStore()

        for (key, value) in otherRawValues {
            if overwrite || values[key] == nil {
                values[key] = value
            }
        }

        // Merge typed value slots so reads through `getTyped(_:)` observe
        // merged state. Their encoded payloads also project into the raw
        // namespace by name, matching where such values lived before typed
        // storage was unified; projections never displace an existing raw
        // entry or a same-named local slot unless overwriting. Provided
        // slots are intentionally not merged; they were historically
        // instance-specific.
        let projection = otherSlots.projectedValues()
        for (name, payload) in projection {
            if overwrite || (values[name] == nil && !slots.containsValueName(name)) {
                values[name] = payload
            }
        }

        slots.mergeValueSlots(from: otherSlots, overwrite: overwrite)

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

        // Carry typed value slots so reads through `getTyped(_:)` observe
        // copied state. Provided slots are intentionally not copied; they
        // are instance-specific.
        let newContext = AgentContext(
            input: originalInput,
            initialValues: copiedValues,
            slots: slots.copyingValueSlots()
        )

        // Note: Messages and execution path are not copied to the new context
        // to avoid confusion. They are instance-specific.
        // If needed, use merge() after creating the copy.

        return newContext
    }

    // MARK: - Typed Context (deprecated shim)

    /// Stores a typed context object.
    ///
    /// The context is stored in the unified slot store keyed by its concrete
    /// type and `contextKey`, and can be retrieved using `typed(_:)`.
    ///
    /// - Parameter context: The typed context to store.
    public func setTyped<T: AgentContextProviding>(_ context: T) {
        slots.setProvided(context)
    }

    /// Retrieves a typed context object.
    ///
    /// - Parameter type: The type of context to retrieve.
    /// - Returns: The stored context, or nil if not found.
    public func typed<T: AgentContextProviding>(_: T.Type) -> T? {
        slots.provided(of: T.self)
    }

    /// Removes a typed context.
    ///
    /// - Parameter type: The type of context to remove.
    /// - Returns: The removed context, or nil if not found.
    @discardableResult
    public func removeTyped<T: AgentContextProviding>(_: T.Type) -> T? {
        slots.removeProvided(of: T.self)
    }

    /// Returns true if a typed context of the given type is stored.
    ///
    /// - Parameter type: The type to check for.
    /// - Returns: Whether a context of this type exists.
    public func hasTyped<T: AgentContextProviding>(_: T.Type) -> Bool {
        slots.containsProvided(of: T.self)
    }

    // MARK: - Slot Storage Bridge (package-internal)

    /// Stores an encoded payload in the slot identified by `key`.
    /// Package-internal; used by the typed-access helpers in this directory.
    ///
    /// - Parameters:
    ///   - key: The typed key identifying the slot.
    ///   - payload: The encoded value to store.
    func setValueSlot<T>(_ key: ContextKey<T>, payload: SendableValue) {
        slots.setValuePayload(key, payload: payload)
    }

    /// Returns the encoded payload stored for `key`, if any.
    /// Package-internal; used by the typed-access helpers in this directory.
    ///
    /// - Parameter key: The typed key identifying the slot.
    /// - Returns: The stored payload, or nil when the slot is empty.
    func valueSlotPayload<T>(for key: ContextKey<T>) -> SendableValue? {
        slots.valuePayload(for: key)
    }

    /// Removes the slot identified by `key`.
    /// Package-internal; used by the typed-access helpers in this directory.
    ///
    /// - Parameter key: The typed key identifying the slot.
    /// - Returns: The removed payload, or nil when the slot was empty.
    @discardableResult
    func removeValueSlot<T>(_ key: ContextKey<T>) -> SendableValue? {
        slots.removeValuePayload(key)
    }

    /// Returns whether a slot exists for `key`.
    /// Package-internal; used by the typed-access helpers in this directory.
    ///
    /// - Parameter key: The typed key identifying the slot.
    /// - Returns: True when the slot holds a value.
    func hasValueSlot<T>(_ key: ContextKey<T>) -> Bool {
        slots.hasValuePayload(key)
    }

    /// Returns a copy of this context's raw string-keyed namespace.
    /// Package-internal; used by `merge(from:)` across actor boundaries.
    ///
    /// - Returns: The raw key-value storage.
    func rawValues() -> [String: SendableValue] {
        values
    }

    /// Returns a copy of this context's unified slot store for merging and
    /// copying. Package-internal; used by `merge(from:)` across actor
    /// boundaries and by the typed-access helpers in this directory.
    func valueSlotStore() -> ContextSlotStore {
        slots
    }

    // MARK: Private

    // MARK: - Private Storage

    /// Key-value storage for arbitrary data.
    ///
    /// This is the raw string-keyed namespace. Typed `ContextKey<Value>`
    /// values live in `slots` and are projected into snapshots by name.
    private var values: [String: SendableValue]

    /// Message history for conversation continuity.
    private var messages: [MemoryMessage]

    /// List of agent names that have executed.
    private var executionPath: [String]

    /// Unified typed slot storage shared by `ContextKey<Value>` accessors
    /// and the deprecated `AgentContextProviding` shim. See
    /// `ContextSlotStore`.
    private var slots: ContextSlotStore
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
