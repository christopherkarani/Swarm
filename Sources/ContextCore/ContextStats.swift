import Foundation

/// Runtime counters and latency snapshots for ``AgentContext``.
public struct ContextStats: Sendable, Codable, Hashable {
    /// Number of episodic chunks currently stored.
    public var episodicCount: Int
    /// Number of semantic chunks currently stored.
    public var semanticCount: Int
    /// Number of procedural patterns currently stored.
    public var proceduralCount: Int
    /// Total number of sessions started.
    public var totalSessions: Int
    /// Latest ``AgentContext/buildWindow(currentTask:maxTokens:)`` latency in milliseconds.
    public var lastBuildWindowLatencyMs: Double
    /// Latest consolidation latency in milliseconds.
    public var lastConsolidationLatencyMs: Double
    /// Average chunk score in the last built window.
    public var averageRelevanceScore: Float
    /// Ratio of compressed chunks in the last built window.
    public var compressionRatio: Float

    /// Creates a stats snapshot.
    ///
    /// - Parameters:
    ///   - episodicCount: Episodic chunk count.
    ///   - semanticCount: Semantic chunk count.
    ///   - proceduralCount: Procedural pattern count.
    ///   - totalSessions: Started session count.
    ///   - lastBuildWindowLatencyMs: Last build latency in milliseconds.
    ///   - lastConsolidationLatencyMs: Last consolidation latency in milliseconds.
    ///   - averageRelevanceScore: Mean score in last window.
    ///   - compressionRatio: Ratio of compressed chunks in last window.
    public init(
        episodicCount: Int = 0,
        semanticCount: Int = 0,
        proceduralCount: Int = 0,
        totalSessions: Int = 0,
        lastBuildWindowLatencyMs: Double = 0,
        lastConsolidationLatencyMs: Double = 0,
        averageRelevanceScore: Float = 0,
        compressionRatio: Float = 0
    ) {
        self.episodicCount = episodicCount
        self.semanticCount = semanticCount
        self.proceduralCount = proceduralCount
        self.totalSessions = totalSessions
        self.lastBuildWindowLatencyMs = lastBuildWindowLatencyMs
        self.lastConsolidationLatencyMs = lastConsolidationLatencyMs
        self.averageRelevanceScore = averageRelevanceScore
        self.compressionRatio = compressionRatio
    }
}
