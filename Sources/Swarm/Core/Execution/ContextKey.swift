// ContextKey.swift
// Swarm Framework
//
// Type-safe context keys for AgentContext.

import Foundation

// MARK: - ContextKey

/// A type-safe key for accessing values in `AgentContext`.
///
/// `ContextKey` provides compile-time type safety for context values,
/// eliminating runtime type errors when storing and retrieving data.
///
/// Typed storage is a namespace separate from untyped string storage:
/// unlike ``MetadataKey`` — whose entries remain visible to raw-string
/// dictionary access — a value written through
/// ``AgentContext/setTyped(_:value:)`` is readable only through
/// ``AgentContext/getTyped(_:)``, not by its string name.
///
/// Example:
/// ```swift
/// // Define typed keys
/// extension ContextKey where Value == String {
///     static let userID = ContextKey("user_id")
/// }
///
/// extension ContextKey where Value == Int {
///     static let retryCount = ContextKey("retry_count")
/// }
///
/// // Use with type safety
/// await context.set(.originalInput, "User query")
/// let input: String? = await context.get(.originalInput)
/// await context.setTyped(.userID, value: "user-123")
/// let id: String? = await context.getTyped(.userID)
/// ```
public struct ContextKey<Value: Sendable>: Hashable, Sendable {
    /// The string name of the key.
    public let name: String

    /// Creates a new context key.
    ///
    /// - Parameter name: The string name for the key.
    public init(_ name: String) {
        self.name = name
    }

    // MARK: - Equatable

    public static func == (lhs: ContextKey<Value>, rhs: ContextKey<Value>) -> Bool {
        lhs.name == rhs.name
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - Standard String Keys

public extension ContextKey where Value == String {
    /// User identifier key.
    static let userID = ContextKey("user_id")

    /// Session identifier key.
    static let sessionID = ContextKey("session_id")

    /// Correlation ID for tracing.
    static let correlationID = ContextKey("correlation_id")

    /// Current language/locale.
    static let language = ContextKey("language")

    /// API version being used.
    static let apiVersion = ContextKey("api_version")

    /// The original input that started orchestration (`original_input`).
    static let originalInput = ContextKey("original_input")

    /// The output from the previous agent in the chain (`previous_output`).
    static let previousOutput = ContextKey("previous_output")

    /// The name of the current executing agent (`current_agent_name`).
    static let currentAgentName = ContextKey("current_agent_name")
}

// MARK: - Standard Int Keys

public extension ContextKey where Value == Int {
    /// Request counter key.
    static let requestCount = ContextKey("request_count")

    /// Retry counter key.
    static let retryCount = ContextKey("retry_count")

    /// Iteration counter key.
    static let iterationCount = ContextKey("iteration_count")

    /// Current depth in orchestration.
    static let depth = ContextKey("depth")
}

// MARK: - Standard Bool Keys

public extension ContextKey where Value == Bool {
    /// Whether the user is authenticated.
    static let isAuthenticated = ContextKey("is_authenticated")

    /// Whether debug mode is enabled.
    static let isDebugMode = ContextKey("is_debug_mode")

    /// Whether to enable verbose logging.
    static let verboseLogging = ContextKey("verbose_logging")

    /// Whether the request is a dry run.
    static let isDryRun = ContextKey("is_dry_run")
}

// MARK: - Standard Array Keys

public extension ContextKey where Value == [String] {
    /// User permissions/roles.
    static let permissions = ContextKey("permissions")

    /// Tags associated with the request.
    static let tags = ContextKey("tags")

    /// Feature flags enabled.
    static let featureFlags = ContextKey("feature_flags")

    /// The execution path as a list of agent names (`execution_path`).
    static let executionPath = ContextKey("execution_path")
}

// MARK: - Standard Date Keys

public extension ContextKey where Value == Date {
    /// Request timestamp.
    static let timestamp = ContextKey("timestamp")

    /// Expiration time.
    static let expiresAt = ContextKey("expires_at")

    /// The start time of orchestration (`start_time`).
    static let startTime = ContextKey("start_time")
}

// MARK: - AgentContext Typed Extensions

/// Typed context access over `AgentContext`'s unified slot store.
///
/// Keys and values are paired at compile time: a slot is identified by the
/// key's string name together with its static `Value` type, so two keys
/// sharing a name across different value types occupy distinct slots and a
/// read can never observe another key's payload. Values are encoded once on
/// write and decoded once on read by `ContextValueCodec`; no runtime casting
/// participates in typed reads.
public extension AgentContext {
    /// Stores a string under a typed context key.
    ///
    /// Writes the slot store and clears any raw entry of the same name so
    /// ``snapshot`` projects this value.
    func set(_ key: ContextKey<String>, _ value: String) {
        setTyped(key, value: value)
        _ = remove(key.name)
    }

    /// Reads a string stored under a typed context key, falling back to the
    /// raw namespace when the slot is empty.
    func get(_ key: ContextKey<String>) -> String? {
        getTyped(key) ?? get(key.name)?.stringValue
    }

    /// Stores an integer under a typed context key.
    func set(_ key: ContextKey<Int>, _ value: Int) {
        setTyped(key, value: value)
        _ = remove(key.name)
    }

    /// Reads an integer stored under a typed context key.
    func get(_ key: ContextKey<Int>) -> Int? {
        getTyped(key) ?? get(key.name)?.intValue
    }

    /// Stores a Boolean under a typed context key.
    func set(_ key: ContextKey<Bool>, _ value: Bool) {
        setTyped(key, value: value)
        _ = remove(key.name)
    }

    /// Reads a Boolean stored under a typed context key.
    func get(_ key: ContextKey<Bool>) -> Bool? {
        getTyped(key) ?? get(key.name)?.boolValue
    }

    /// Stores a double under a typed context key.
    func set(_ key: ContextKey<Double>, _ value: Double) {
        setTyped(key, value: value)
        _ = remove(key.name)
    }

    /// Reads a double stored under a typed context key.
    func get(_ key: ContextKey<Double>) -> Double? {
        getTyped(key) ?? get(key.name)?.doubleValue
    }

    /// Stores a string array under a typed context key.
    func set(_ key: ContextKey<[String]>, _ value: [String]) {
        setTyped(key, value: value)
        _ = remove(key.name)
    }

    /// Reads a string array stored under a typed context key.
    func get(_ key: ContextKey<[String]>) -> [String]? {
        if let typed = getTyped(key) {
            return typed
        }
        return get(key.name)?.arrayValue?.compactMap(\.stringValue)
    }

    /// Stores a date under a typed context key.
    func set(_ key: ContextKey<Date>, _ value: Date) {
        setTyped(key, value: value)
        _ = remove(key.name)
    }

    /// Reads a date stored under a typed context key.
    func get(_ key: ContextKey<Date>) -> Date? {
        if let typed = getTyped(key) {
            return typed
        }
        guard let timestamp = get(key.name)?.doubleValue else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Sets a typed value in the context.
    ///
    /// The value is encoded into the unified slot store under this key's
    /// `(Value type, name)` identity. Untyped string storage is a separate
    /// raw namespace; raw writes are not visible to typed reads.
    ///
    /// - Parameters:
    ///   - key: The typed context key.
    ///   - value: The value to store.
    ///
    /// Example:
    /// ```swift
    /// await context.setTyped(.userID, value: "user-123")
    /// await context.setTyped(.isAuthenticated, value: true)
    /// ```
    func setTyped<T: Sendable & Encodable>(_ key: ContextKey<T>, value: T) {
        setValueSlot(key, payload: ContextValueCodec.encode(value))
    }

    /// Gets a typed value from the context.
    ///
    /// - Parameter key: The typed context key.
    /// - Returns: The stored value decoded as the key's value type, or nil
    ///   when nothing is stored under this slot. When the value type is
    ///   itself Optional, storing `nil` creates a null slot whose read
    ///   succeeds with a nil payload rather than returning nil for absence.
    ///
    /// Example:
    /// ```swift
    /// let userID: String? = await context.getTyped(.userID)
    /// let isAuth: Bool? = await context.getTyped(.isAuthenticated)
    /// ```
    func getTyped<T: Sendable & Decodable>(_ key: ContextKey<T>) -> T? {
        guard let payload = valueSlotPayload(for: key) else { return nil }
        return ContextValueCodec.decode(payload, as: T.self)
    }

    /// Gets a typed value from the context with a default.
    ///
    /// - Parameters:
    ///   - key: The typed context key.
    ///   - defaultValue: The default value if not found.
    /// - Returns: The stored value or the default.
    ///
    /// Example:
    /// ```swift
    /// let count = await context.getTyped(.retryCount, default: 0)
    /// ```
    func getTyped<T: Sendable & Decodable>(_ key: ContextKey<T>, default defaultValue: T) -> T {
        getTyped(key) ?? defaultValue
    }

    /// Removes a typed value from the context.
    ///
    /// Only this key's own slot is removed; same-named slots of other value
    /// types and raw namespace entries are untouched.
    ///
    /// - Parameter key: The typed context key.
    ///
    /// Example:
    /// ```swift
    /// await context.removeTyped(.userID)
    /// ```
    func removeTyped(_ key: ContextKey<some Sendable>) {
        removeValueSlot(key)
    }

    /// Checks if a typed key exists in the context.
    ///
    /// - Parameter key: The typed context key.
    /// - Returns: True if a value exists for this exact slot.
    ///
    /// Example:
    /// ```swift
    /// if await context.hasTyped(.userID) {
    ///     // User ID is set
    /// }
    /// ```
    func hasTyped(_ key: ContextKey<some Sendable>) -> Bool {
        hasValueSlot(key)
    }
}
