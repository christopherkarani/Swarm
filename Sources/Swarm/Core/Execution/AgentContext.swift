// AgentContext.swift
// Swarm Framework
//
// Shared context for multi-agent orchestration execution.

import Foundation

// MARK: - AgentContextKey

/// Predefined keys for common agent context values.
///
/// Use typed ``ContextKey`` orchestration statics such as
/// ``ContextKey/originalInput``. These string keys remain for source
/// compatibility.
///
/// Example:
/// ```swift
/// await context.set(.originalInput, "User query")
/// if let input = await context.get(.originalInput) {
///     print("Original: \(input)")
/// }
/// ```
@available(*, deprecated, message: "Use typed ContextKey orchestration statics such as ContextKey.originalInput.")
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

        // Isolated ContextKey setters cannot run from init. Seed the same
        // raw names and typed slots the orchestration setters use.
        values[ContextKey<String>.originalInput.name] = .string(input)
        values[ContextKey<Date>.startTime.name] = .double(createdAt.timeIntervalSince1970)
        self.slots.setValuePayload(
            ContextKey<String>.originalInput,
            payload: ContextValueCodec.encode(input)
        )
        self.slots.setValuePayload(
            ContextKey<Date>.startTime,
            payload: ContextValueCodec.encode(createdAt)
        )
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
    @available(*, deprecated, message: "Use typed ContextKey accessors such as get(.originalInput).")
    @_disfavoredOverload
    public func get(_ key: AgentContextKey) -> SendableValue? {
        snapshot[key.rawValue]
    }

    /// Stores a value by string key.
    ///
    /// - Parameters:
    ///   - key: The key to store under.
    ///   - value: The value to store.
    public func set(_ key: String, value: SendableValue) {
        values[key] = value
        // Orchestration names are also typed slots. A raw write must drop the
        // matching slot so `get(.originalInput)` cannot keep serving init's
        // seed after this name has been overwritten.
        clearTypedOrchestrationSlot(named: key)
    }

    /// Stores a value by predefined context key.
    ///
    /// - Parameters:
    ///   - key: The context key to store under.
    ///   - value: The value to store.
    @available(*, deprecated, message: "Use typed ContextKey accessors such as set(.originalInput, _).")
    @_disfavoredOverload
    public func set(_ key: AgentContextKey, value: SendableValue) {
        switch key {
        case .originalInput:
            if let string = value.stringValue {
                set(ContextKey<String>.originalInput, string)
                return
            }
        case .previousOutput:
            if let string = value.stringValue {
                set(ContextKey<String>.previousOutput, string)
                return
            }
        case .currentAgentName:
            if let string = value.stringValue {
                set(ContextKey<String>.currentAgentName, string)
                return
            }
        case .executionPath:
            if let elements = value.arrayValue {
                let path = elements.compactMap(\.stringValue)
                if path.count == elements.count {
                    set(ContextKey<[String]>.executionPath, path)
                    return
                }
            }
        case .startTime:
            if let timestamp = value.doubleValue {
                set(ContextKey<Date>.startTime, Date(timeIntervalSince1970: timestamp))
                return
            }
        case .metadata:
            break
        }

        values[key.rawValue] = value
        clearTypedOrchestrationSlot(named: key.rawValue)
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
        set(.executionPath, executionPath)
        set(.currentAgentName, agentName)
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
        set(.previousOutput, result.output)
    }

    /// Gets the previous agent's output.
    ///
    /// - Returns: The previous output, or nil if not set.
    public func getPreviousOutput() -> String? {
        get(.previousOutput)
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
        // Raw and slots must come from one parent hop. ContextKey data used
        // to live in `values` as a single snapshot; two awaits let another
        // task mutate `other` in between and drop a replacement or duplicate
        // it across namespaces so snapshot, getTyped, and removeTyped disagree.
        let (otherRawValues, otherSlots) = await other.rawValuesAndValueSlots()

        // Typed slot names occupy the key for overwrite:false even though
        // they live outside the raw namespace. Copying parent raw under a
        // live local slot would steal the snapshot (raw wins) and survive
        // removeTyped as a shadow.
        for (key, value) in otherRawValues {
            if overwrite || (values[key] == nil && !slots.containsValueName(key)) {
                values[key] = value
            }
        }

        // Merge typed value slots so reads through `getTyped(_:)` observe
        // merged state. Snapshot already projects those slots by name; they
        // are not copied into the raw namespace, matching `setTyped` and
        // `copy(additionalValues:)`.
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
        // copied state.
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

    /// Returns a copy of this context's raw namespace and typed slot store
    /// captured together. Package-internal; used by `merge(from:)` so a
    /// concurrent mutation of the parent cannot tear ContextKey data across
    /// the two namespaces.
    func rawValuesAndValueSlots() -> (raw: [String: SendableValue], slots: ContextSlotStore) {
        (values, slots)
    }

    /// Drops the typed orchestration slot for `name`, if this name is one of
    /// the five slots that also live behind `ContextKey` statics.
    private func clearTypedOrchestrationSlot(named name: String) {
        switch name {
        case ContextKey<String>.originalInput.name:
            removeTyped(ContextKey<String>.originalInput)
        case ContextKey<String>.previousOutput.name:
            removeTyped(ContextKey<String>.previousOutput)
        case ContextKey<String>.currentAgentName.name:
            removeTyped(ContextKey<String>.currentAgentName)
        case ContextKey<[String]>.executionPath.name:
            removeTyped(ContextKey<[String]>.executionPath)
        case ContextKey<Date>.startTime.name:
            removeTyped(ContextKey<Date>.startTime)
        default:
            break
        }
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

    /// Unified typed slot storage used by `ContextKey<Value>` accessors.
    /// See `ContextSlotStore`.
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
