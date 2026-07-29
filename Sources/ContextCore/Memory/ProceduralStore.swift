import Foundation

/// LRU-bounded store of tool usage patterns keyed by task type.
public actor ProceduralStore {
    private let capacity: Int
    private var entries: [String: [ToolCall]] = [:]
    private var lastAccessedAt: [String: Date] = [:]

    /// Creates a procedural store.
    ///
    /// - Parameter capacity: Maximum number of task-type keys retained.
    public init(capacity: Int = 1_000) {
        self.capacity = capacity
    }

    /// Number of task-type entries currently retained.
    public var count: Int {
        entries.count
    }

    /// Records tool calls for a task type.
    ///
    /// - Parameters:
    ///   - taskType: Task key.
    ///   - tools: Tool-call sequence to retain.
    public func record(taskType: String, tools: [ToolCall]) async {
        let now = Date()
        let isNewKey = entries[taskType] == nil

        if isNewKey && entries.count >= capacity {
            evictLeastRecentlyAccessed()
        }

        entries[taskType] = tools
        lastAccessedAt[taskType] = now
    }

    /// Retrieves tool calls by prefix-matching task type.
    ///
    /// - Parameter taskType: Prefix used to match stored task keys.
    /// - Returns: Flattened tool calls from matched entries.
    public func retrieve(taskType: String) async -> [ToolCall] {
        let matchingKeys = entries.keys.filter { $0.hasPrefix(taskType) }.sorted()
        guard !matchingKeys.isEmpty else {
            return []
        }

        let now = Date()
        for key in matchingKeys {
            lastAccessedAt[key] = now
        }

        return matchingKeys.flatMap { entries[$0] ?? [] }
    }

    /// Returns all stored task patterns.
    public func allPatterns() async -> [String: [ToolCall]] {
        entries
    }

    private func evictLeastRecentlyAccessed() {
        guard let oldestKey = lastAccessedAt.min(by: { $0.value < $1.value })?.key else {
            return
        }
        entries.removeValue(forKey: oldestKey)
        lastAccessedAt.removeValue(forKey: oldestKey)
    }
}
