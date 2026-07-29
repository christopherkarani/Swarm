import Foundation

/// Identifies the speaker or producer of a conversational turn.
public enum TurnRole: String, Codable, Sendable, Hashable {
    /// A user-authored turn.
    case user
    /// A model-authored assistant turn.
    case assistant
    /// Output emitted by a tool invocation.
    case tool
    /// A system instruction or policy turn.
    case system
}

/// A single conversational event tracked by ContextCore.
public struct Turn: Identifiable, Codable, Sendable, Hashable {
    /// Stable identifier used for deduplication and retrieval tracking.
    public let id: UUID
    /// Role associated with this turn.
    public let role: TurnRole
    /// Raw textual content of the turn.
    public let content: String
    /// Timestamp when the turn was produced.
    public let timestamp: Date
    /// Token count estimate used for budgeting.
    public var tokenCount: Int
    /// Optional embedding vector for semantic retrieval.
    public var embedding: [Float]?
    /// Arbitrary metadata associated with the turn.
    public var metadata: [String: String]

    /// Creates a turn with optional precomputed metadata and embedding.
    ///
    /// - Parameters:
    ///   - id: Stable identifier for the turn.
    ///   - role: Logical speaker role.
    ///   - content: Textual content.
    ///   - timestamp: Creation time. Defaults to the current time.
    ///   - tokenCount: Token estimate. Defaults to `0` and can be computed later.
    ///   - embedding: Optional embedding vector.
    ///   - metadata: Additional key-value metadata.
    public init(
        id: UUID = UUID(),
        role: TurnRole,
        content: String,
        timestamp: Date = .now,
        tokenCount: Int = 0,
        embedding: [Float]? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenCount = tokenCount
        self.embedding = embedding
        self.metadata = metadata
    }

    /// Compares two turns by identity.
    public static func == (lhs: Turn, rhs: Turn) -> Bool {
        lhs.id == rhs.id
    }

    /// Hashes the turn by identity.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Captures a single tool execution summary.
public struct ToolCall: Codable, Sendable, Hashable {
    /// Tool name.
    public let name: String
    /// Serialized input passed to the tool.
    public let input: String
    /// Serialized output returned by the tool.
    public let output: String
    /// Wall-clock duration of the call, in milliseconds.
    public let durationMs: Double

    /// Creates a tool call summary.
    ///
    /// - Parameters:
    ///   - name: Tool name.
    ///   - input: Serialized tool input.
    ///   - output: Serialized tool output.
    ///   - durationMs: Tool call duration in milliseconds.
    public init(name: String, input: String, output: String, durationMs: Double) {
        self.name = name
        self.input = input
        self.output = output
        self.durationMs = durationMs
    }
}
