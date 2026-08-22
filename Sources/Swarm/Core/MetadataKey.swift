// MetadataKey.swift
// Swarm Framework
//
// Compiler-checked keys for result and trace metadata dictionaries.

import Foundation

// MARK: - MetadataKey

/// A compiler-checked key pairing a stable string name with a value type.
///
/// Producers and consumers of a ``AgentResult/metadata`` or
/// ``TraceEvent/metadata`` entry share one `MetadataKey` symbol so the stored
/// payload type is verified at compile time instead of by string convention.
/// Keys serialize to their ``name``; the persisted dictionary remains
/// `[String: SendableValue]`, so raw-string access keeps working alongside
/// typed access.
///
/// Example:
/// ```swift
/// var metadata: [String: SendableValue] = [:]
/// metadata[.runtimeEngine] = "graph"
///
/// let engine: String? = metadata[.runtimeEngine]  // same key symbol
/// ```
public struct MetadataKey<Value: Sendable>: Hashable, Sendable {
    // MARK: Public

    /// The stable serialized name written into the metadata dictionary.
    ///
    /// This string must not change across releases: persisted results,
    /// traces, and checkpoints store it verbatim.
    public let name: String

    /// Creates a key with a stable serialized name.
    ///
    /// - Parameter name: String written into the dictionary. Prefer declaring
    ///   one shared constant instead of constructing ad-hoc keys at call sites.
    public init(_ name: String) {
        self.name = name
    }
}

// MARK: - Result Runtime Keys

public extension MetadataKey where Value == String {
    /// Runtime engine recorded on ``AgentResult`` (`"graph"` or `"native"`).
    static let runtimeEngine = MetadataKey("runtime.engine")
}

// MARK: - Workflow Keys

public extension MetadataKey where Value == Bool {
    /// Whether a workflow fallback step ran its backup agent.
    static let fallbackUsed = MetadataKey("workflow.fallback.used")
}

public extension MetadataKey where Value == String {
    /// Description of the error that forced a workflow fallback to its backup.
    static let fallbackError = MetadataKey("workflow.fallback.error")
}

// MARK: - Token Usage Keys

public extension MetadataKey where Value == Int {
    /// Provider-reported input tokens on `agentComplete` trace events.
    static let inputTokens = MetadataKey("input_tokens")

    /// Provider-reported output tokens on `agentComplete` trace events.
    static let outputTokens = MetadataKey("output_tokens")

    /// Provider-reported total tokens on `agentComplete` trace events.
    static let totalTokens = MetadataKey("total_tokens")

    /// Legacy alias of ``totalTokens`` kept for older readers that consume the
    /// pre-namespaced `"tokenCount"` entry.
    static let legacyTokenCount = MetadataKey("tokenCount")
}

// MARK: - Step Timing Keys

public extension MetadataKey where Value == Int {
    /// Zero-based step index recorded on trace events emitted per step.
    static let stepNumber = MetadataKey("stepNumber")
}

public extension MetadataKey where Value == Double {
    /// Duration in milliseconds recorded on trace events (`duration_ms`).
    ///
    /// Written by ``TracingHelper`` spans and `@Traceable` results; readers
    /// share this symbol instead of repeating the raw string.
    static let durationMs = MetadataKey("duration_ms")
}

// MARK: - Tool Outcome Keys

public extension MetadataKey where Value == Bool {
    /// Tool invocation outcome written as a Boolean payload (never
    /// `"true"`/`"false"` strings) on result and trace metadata.
    ///
    /// Graph-runtime stream events carry their stringly counterpart under the
    /// same `"success"` name until those payloads migrate.
    static let toolSuccess = MetadataKey("success")
}

// MARK: - Stream Event Keys

/// Payload field names carried by graph-runtime stream events.
///
/// These events serialize as `[String: String]`, so every field here is a
/// ``MetadataKey``-keyed read over a plain string dictionary. See `GraphAgent`
/// for the consumer side of these payloads.
///
/// Internal because both the producer (`ChatGraph`) and the consumer
/// (`GraphAgent`) live in this module; promote to public if external graph
/// nodes ever need to emit compatible events.
enum StreamEventMetadata {
    /// Model identifier reported when a model invocation starts.
    static let model = MetadataKey<String>("model")

    /// Incremental text chunk reported while a model streams.
    static let text = MetadataKey<String>("text")

    /// Tool name reported when a tool invocation starts or finishes.
    static let name = MetadataKey<String>("name")

    /// Tool invocation outcome (`"true"`/`"false"`) reported when a tool
    /// invocation finishes.
    static let success = MetadataKey<String>("success")

    /// Provider tool-call identifier correlating invocations across events.
    static let toolCallID = MetadataKey<String>("toolCallID")

    /// Tool output reported when a successful tool invocation finishes.
    static let output = MetadataKey<String>("output")
}

// MARK: - Typed Metadata Access

public extension Dictionary where Key == String, Value == SendableValue {
    /// Reads the value stored under the key's stable name as a `String`.
    ///
    /// Returns nil when the entry is absent or holds a non-string payload.
    subscript(key: MetadataKey<String>) -> String? {
        get { self[key.name]?.stringValue }
        set { self[key.name] = newValue.map { SendableValue($0) } }
    }

    /// Reads the value stored under the key's stable name as an `Int`.
    ///
    /// Returns nil when the entry is absent or holds a non-integer payload.
    subscript(key: MetadataKey<Int>) -> Int? {
        get { self[key.name]?.intValue }
        set { self[key.name] = newValue.map { SendableValue($0) } }
    }

    /// Reads the value stored under the key's stable name as a `Double`.
    ///
    /// Returns nil when the entry is absent or holds neither a `.double` nor
    /// an `.int` payload.
    subscript(key: MetadataKey<Double>) -> Double? {
        get { self[key.name]?.doubleValue }
        set { self[key.name] = newValue.map { SendableValue($0) } }
    }

    /// Reads the value stored under the key's stable name as a `Bool`.
    ///
    /// Returns nil when the entry is absent or holds a non-Boolean payload.
    subscript(key: MetadataKey<Bool>) -> Bool? {
        get { self[key.name]?.boolValue }
        set { self[key.name] = newValue.map { SendableValue($0) } }
    }
}

public extension Dictionary where Key == String, Value == String {
    /// Reads the value stored under the key's stable name from a plain string
    /// dictionary, such as graph-runtime stream event payloads.
    subscript(key: MetadataKey<String>) -> String? {
        get { self[key.name] }
        set { self[key.name] = newValue }
    }
}
