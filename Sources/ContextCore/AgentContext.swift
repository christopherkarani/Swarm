import Foundation
import OSLog
import os.lock
import ContextCoreEngine

extension Logger {
    static let contextCore = Logger(subsystem: "com.contextcore", category: "AgentContext")
    static let consolidation = Logger(subsystem: "com.contextcore", category: "Consolidation")
    static let scoring = Logger(subsystem: "com.contextcore", category: "Scoring")
}

/// High-level actor API coordinating retrieval, scoring, packing, compression, and persistence.
public actor AgentContext {
    /// Immutable runtime configuration for this context instance.
    public let configuration: ContextConfiguration

    private var sessionStore = SessionStore()

    private let episodicStore: EpisodicStore
    private let semanticStore: SemanticStore
    private let proceduralStore: ProceduralStore

    private let scoringEngine: ScoringEngine
    private let attentionEngine: AttentionEngine
    private let compressionEngine: CompressionEngine
    private let consolidationEngine: ConsolidationEngine
    private let progressiveCompressor: ProgressiveCompressor

    private let windowPacker: WindowPacker
    private let chunkOrderer: ChunkOrderer

    private let embeddingProvider: any EmbeddingProvider
    private let tokenCounter: any TokenCounter

    private let consolidationScheduler: ConsolidationScheduler

    private nonisolated let statsLock = OSAllocatedUnfairLock(initialState: ContextStats())

    /// Latest nonisolated runtime stats snapshot.
    public nonisolated var stats: ContextStats {
        statsLock.withLock { $0 }
    }

    /// Creates an ``AgentContext`` and initializes all processing subsystems.
    ///
    /// - Parameter configuration: Runtime configuration. Defaults to ``ContextConfiguration/default``.
    /// - Throws: `ContextCoreError.metalDeviceUnavailable` when no compatible Metal device exists.
    public init(configuration: ContextConfiguration = .default) throws {
        self.configuration = configuration

        let provider = CachingEmbeddingProvider(
            base: configuration.embeddingProvider,
            cache: EmbeddingCache(capacity: 512)
        )
        self.embeddingProvider = provider
        self.tokenCounter = configuration.tokenCounter

        self.episodicStore = EpisodicStore()
        self.semanticStore = SemanticStore()
        self.proceduralStore = ProceduralStore()

        self.scoringEngine = try ScoringEngine()
        self.attentionEngine = try AttentionEngine()
        self.compressionEngine = try CompressionEngine(
            embeddingProvider: provider,
            tokenCounter: configuration.tokenCounter,
            compressionDelegate: configuration.compressionDelegate
        )
        self.consolidationEngine = try ConsolidationEngine(
            embeddingProvider: provider
        )

        self.progressiveCompressor = ProgressiveCompressor(
            compressionEngine: self.compressionEngine,
            tokenCounter: configuration.tokenCounter
        )
        self.windowPacker = WindowPacker(
            compressionEngine: self.compressionEngine,
            tokenCounter: configuration.tokenCounter,
            minimumChunkSize: 50,
            recentTurnsGuaranteed: configuration.recentTurnsGuaranteed
        )
        self.chunkOrderer = ChunkOrderer()

        self.consolidationScheduler = ConsolidationScheduler(
            engine: self.consolidationEngine,
            countThreshold: configuration.consolidationThreshold,
            insertionThreshold: 50,
            similarityThreshold: configuration.similarityMergeThreshold
        )

        statsLock.withLock { snapshot in
            snapshot.proceduralCount = 0
        }

        Task.detached(priority: .background) {
            _ = try? await provider.embed("warmup")
        }
    }

    /// Restores an ``AgentContext`` from a checkpoint file.
    ///
    /// - Parameter url: Checkpoint file URL.
    /// - Returns: A restored context with persisted stores and session metadata.
    /// - Throws: `ContextCoreError.checkpointCorrupt` when data cannot be decoded or schema is unsupported.
    public static func load(from url: URL) async throws -> AgentContext {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw error
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let checkpoint: ContextCheckpoint
        do {
            checkpoint = try decoder.decode(ContextCheckpoint.self, from: data)
        } catch {
            Logger.contextCore.error("Error in load(from:): \(error.localizedDescription, privacy: .public)")
            throw ContextCoreError.checkpointCorrupt
        }

        guard checkpoint.version == 1 else {
            Logger.contextCore.error("Error in load(from:): unsupported checkpoint version \(checkpoint.version, privacy: .public)")
            throw ContextCoreError.checkpointCorrupt
        }

        let config = checkpoint.configuration.apply(to: .default)
        let context = try AgentContext(configuration: config)
        try await context.restore(from: checkpoint)
        return context
    }

    /// Begins a new session and optionally sets the session system prompt.
    ///
    /// - Parameters:
    ///   - id: Session identifier. Defaults to a new UUID.
    ///   - systemPrompt: Optional system prompt pinned into subsequent windows.
    /// - Throws: Propagates errors from implicit session-end consolidation when a session is already active.
    public func beginSession(id: UUID = UUID(), systemPrompt: String? = nil) async throws {
        if sessionStore.isSessionActive {
            try await endSession()
        }

        sessionStore.begin(id: id, systemPrompt: systemPrompt)
        let totalSessions = sessionStore.totalSessions
        mutateStats { snapshot in
            snapshot.totalSessions = totalSessions
        }

        Logger.contextCore.info("Session started: \(id.uuidString, privacy: .public)")
    }

    /// Ends the active session and runs a consolidation pass.
    ///
    /// - Throws: `ContextCoreError.sessionNotStarted` when no session is active.
    public func endSession() async throws {
        guard let sessionID = sessionStore.currentSessionID else {
            throw ContextCoreError.sessionNotStarted
        }

        Logger.consolidation.info("Consolidation started: session=\(sessionID.uuidString, privacy: .public)")

        let result = try await consolidationEngine.consolidate(
            session: sessionID,
            episodicStore: episodicStore,
            semanticStore: semanticStore,
            threshold: configuration.similarityMergeThreshold
        )

        sessionStore.end()
        await refreshCountStats(lastConsolidationLatencyMs: result.durationMs)

        Logger.consolidation.info(
            "Consolidation complete: promoted=\(result.factsPromoted, privacy: .public) evicted=\(result.chunksEvicted, privacy: .public) durationMs=\(result.durationMs, privacy: .public)"
        )
        Logger.contextCore.info("Session ended: \(sessionID.uuidString, privacy: .public)")
    }

    /// Appends a turn into episodic memory and recent-turn buffers.
    ///
    /// - Parameter turn: Turn to append.
    /// - Throws: `ContextCoreError.sessionNotStarted` if no session is active.
    public func append(turn: Turn) async throws {
        guard let sessionID = sessionStore.currentSessionID else {
            throw ContextCoreError.sessionNotStarted
        }

        var enriched = turn
        if enriched.embedding == nil {
            enriched.embedding = try await embedText(turn.content)
        }

        if enriched.tokenCount <= 0 {
            enriched.tokenCount = tokenCounter.count(turn.content)
        }

        try await episodicStore.insert(turn: enriched)

        let maxRecentBuffer = max(configuration.recentTurnsGuaranteed * 2, configuration.recentTurnsGuaranteed)
        sessionStore.appendRecent(enriched, maxBufferSize: maxRecentBuffer)

        let episodicCount = await episodicStore.count
        await consolidationScheduler.notifyInsertion(
            episodicCount: episodicCount,
            session: sessionID,
            episodicStore: episodicStore,
            semanticStore: semanticStore
        )

        mutateStats { snapshot in
            snapshot.episodicCount = episodicCount
        }
    }

    /// Builds an optimal context window for the current task.
    ///
    /// Scores all memory against the task embedding, packs results into the effective token budget,
    /// and orders chunks for attention-aware model consumption. Episodic and semantic scoring run in
    /// parallel with `async let`.
    ///
    /// - Parameters:
    ///   - currentTask: Natural language task query used for memory relevance scoring.
    ///   - maxTokens: Optional override for ``ContextConfiguration/maxTokens``.
    /// - Returns: A packed ``ContextWindow`` ready for ``ContextWindow/formatted(style:)``.
    /// - Throws: `ContextCoreError.sessionNotStarted` when no session is active.
    /// - Throws: `ContextCoreError.tokenBudgetTooSmall` when guaranteed context exceeds effective budget.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let window = try await context.buildWindow(
    ///     currentTask: "Help debug a Swift concurrency issue",
    ///     maxTokens: 4096
    /// )
    /// let prompt = window.formatted(style: .chatML)
    /// ```
    ///
    /// - Complexity: O(n log n) over retrieved candidates plus GPU scoring dispatch.
    public func buildWindow(
        currentTask: String,
        maxTokens: Int? = nil
    ) async throws -> ContextWindow {
        guard let sessionID = sessionStore.currentSessionID else {
            throw ContextCoreError.sessionNotStarted
        }

        let start = Date()

        let rawBudget = maxTokens ?? configuration.maxTokens
        let effectiveBudget = Int((Float(rawBudget) * (1.0 - configuration.tokenBudgetSafetyMargin)).rounded(.down))
        guard effectiveBudget > 0 else {
            throw ContextCoreError.tokenBudgetTooSmall
        }

        let guaranteedTokens = guaranteedTokenUsage()
        guard guaranteedTokens <= effectiveBudget else {
            throw ContextCoreError.tokenBudgetTooSmall
        }

        let taskEmbedding = try await embedText(currentTask)

        let allEpisodic = await episodicStore.allChunks()
        let allSemantic = await semanticStore.allChunks()

        async let episodicScoring = scoreMemory(
            taskEmbedding: taskEmbedding,
            chunks: allEpisodic,
            halfLifeDays: configuration.episodicHalfLifeDays
        )

        async let semanticScoring = scoreMemory(
            taskEmbedding: taskEmbedding,
            chunks: allSemantic,
            halfLifeDays: configuration.semanticHalfLifeDays
        )

        let scoredEpisodic = try await episodicScoring
        let scoredSemantic = try await semanticScoring

        let proceduralTools = await proceduralStore.retrieve(taskType: currentTask)
        let scoredProcedural = makeProceduralCandidates(
            tools: proceduralTools,
            taskEmbedding: taskEmbedding,
            sessionID: sessionID
        )

        var merged: [(chunk: MemoryChunk, score: Float)] = []
        merged.append(contentsOf: scoredEpisodic.prefix(configuration.episodicMemoryK))
        merged.append(contentsOf: scoredSemantic.prefix(configuration.semanticMemoryK))
        merged.append(contentsOf: scoredProcedural)

        let reranked = try await applyAttentionRerank(
            query: taskEmbedding,
            scoredMemory: merged
        )

        let recentTurns = sessionStore.guaranteedRecentTurns(count: configuration.recentTurnsGuaranteed)

        let packed = try await windowPacker.pack(
            systemPrompt: sessionStore.systemPrompt,
            recentTurns: recentTurns,
            scoredMemory: reranked,
            budget: effectiveBudget
        )

        let ordered = chunkOrderer.order(packed.chunks, strategy: .typeGrouped)
        let finalWindow = ContextWindow(chunks: ordered, budget: effectiveBudget)

        let elapsedMs = Date().timeIntervalSince(start) * 1000
        let averageScore: Float
        if finalWindow.chunks.isEmpty {
            averageScore = 0
        } else {
            averageScore = finalWindow.chunks.reduce(Float.zero) { $0 + $1.score } / Float(finalWindow.chunks.count)
        }

        let compressionRatio: Float
        if finalWindow.chunks.isEmpty {
            compressionRatio = 0
        } else {
            compressionRatio = Float(finalWindow.compressedChunks) / Float(finalWindow.chunks.count)
        }

        mutateStats { snapshot in
            snapshot.lastBuildWindowLatencyMs = elapsedMs
            snapshot.averageRelevanceScore = averageScore
            snapshot.compressionRatio = compressionRatio
        }

        Logger.scoring.debug(
            "Window built: tokens=\(finalWindow.totalTokens, privacy: .public) chunks=\(finalWindow.chunks.count, privacy: .public) latencyMs=\(elapsedMs, privacy: .public)"
        )

        return finalWindow
    }

    /// Stores a semantic fact for long-term retrieval.
    ///
    /// - Parameter fact: Fact text to embed and upsert.
    /// - Throws: Embedding or semantic-store failures.
    public func remember(_ fact: String) async throws {
        let embedding = try await embedText(fact)
        try await semanticStore.upsert(fact: fact, embedding: embedding)

        let semanticCount = await semanticStore.count
        mutateStats { snapshot in
            snapshot.semanticCount = semanticCount
        }
    }

    /// Soft-forgets a chunk by reducing its retention score.
    ///
    /// - Parameter id: Chunk identifier to demote.
    /// - Throws: `ContextCoreError.chunkNotFound` when the chunk does not exist.
    public func forget(id: UUID) async throws {
        var found = false

        do {
            try await episodicStore.updateRetentionScore(id: id, delta: -1.0)
            found = true
        } catch let error as ContextCoreError {
            if case .chunkNotFound = error {
                // Ignore and try semantic.
            } else {
                throw error
            }
        }

        do {
            try await semanticStore.updateRetentionScore(id: id, delta: -1.0)
            found = true
        } catch let error as ContextCoreError {
            if case .chunkNotFound = error {
                // Ignore.
            } else {
                throw error
            }
        }

        if !found {
            throw ContextCoreError.chunkNotFound(id: id)
        }
    }

    /// Recalls top semantic and episodic chunks for a query.
    ///
    /// - Parameters:
    ///   - query: Natural language query.
    ///   - k: Maximum number of chunks to return.
    /// - Returns: Top chunks sorted by similarity and recency tie-breaker.
    /// - Throws: Embedding and retrieval errors.
    public func recall(query: String, k: Int = 5) async throws -> [MemoryChunk] {
        let resolvedK = max(0, k)
        guard resolvedK > 0 else {
            return []
        }

        let embedding = try await embedText(query)

        async let episodicResults = episodicStore.retrieve(query: embedding, k: resolvedK)
        async let semanticResults = semanticStore.retrieve(query: embedding, k: resolvedK)

        let combined = try await episodicResults + semanticResults
        let deduped = deduplicate(chunks: combined)

        let scored = deduped.compactMap { chunk -> (MemoryChunk, Float)? in
            guard chunk.retentionScore > 0.01 else {
                return nil
            }
            let score = Self.cosineSimilarity(embedding, chunk.embedding)
            return (chunk, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.createdAt > rhs.0.createdAt
                }
                return lhs.1 > rhs.1
            }
            .prefix(resolvedK)
            .map(\.0)
    }

    /// Runs an explicit consolidation pass for the active session.
    ///
    /// - Throws: `ContextCoreError.sessionNotStarted` when no session is active.
    public func consolidate() async throws {
        guard let sessionID = sessionStore.currentSessionID else {
            throw ContextCoreError.sessionNotStarted
        }

        Logger.consolidation.info("Consolidation started: session=\(sessionID.uuidString, privacy: .public)")

        let result = try await consolidationEngine.consolidate(
            session: sessionID,
            episodicStore: episodicStore,
            semanticStore: semanticStore,
            threshold: configuration.similarityMergeThreshold
        )

        await refreshCountStats(lastConsolidationLatencyMs: result.durationMs)

        Logger.consolidation.info(
            "Consolidation complete: promoted=\(result.factsPromoted, privacy: .public) evicted=\(result.chunksEvicted, privacy: .public) durationMs=\(result.durationMs, privacy: .public)"
        )
    }

    /// Persists full runtime state to a checkpoint file.
    ///
    /// Writes atomically through a temporary file and move operation.
    ///
    /// - Parameter url: Destination checkpoint URL.
    /// - Throws: `ContextCoreError.checkpointCorrupt` when encoding or file I/O fails.
    public func checkpoint(to url: URL) async throws {
        let checkpoint = ContextCheckpoint(
            episodicChunks: await episodicStore.allChunks(),
            semanticChunks: await semanticStore.allChunks(),
            proceduralPatterns: await proceduralStore.allPatterns(),
            lastSessionID: sessionStore.currentSessionID,
            systemPrompt: sessionStore.systemPrompt,
            recentTurns: sessionStore.recentTurns,
            totalSessions: sessionStore.totalSessions,
            configuration: .init(configuration: configuration)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(checkpoint)
        } catch {
            Logger.contextCore.error("Error in checkpoint(to:): \(error.localizedDescription, privacy: .public)")
            throw ContextCoreError.checkpointCorrupt
        }

        let parent = url.deletingLastPathComponent()
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

            let tempURL = parent.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
            try data.write(to: tempURL, options: .atomic)

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: tempURL, to: url)
            Logger.contextCore.info("Checkpoint saved to \(url.path, privacy: .public)")
        } catch {
            Logger.contextCore.error("Error in checkpoint(to:): \(error.localizedDescription, privacy: .public)")
            throw ContextCoreError.checkpointCorrupt
        }
    }

    private func restore(from checkpoint: ContextCheckpoint) async throws {
        for chunk in checkpoint.episodicChunks {
            try await episodicStore.insert(chunk: chunk)
        }

        for chunk in checkpoint.semanticChunks {
            try await semanticStore.insert(chunk: chunk)
        }

        for (taskType, tools) in checkpoint.proceduralPatterns {
            await proceduralStore.record(taskType: taskType, tools: tools)
        }

        sessionStore = SessionStore(
            currentSessionID: checkpoint.lastSessionID,
            systemPrompt: checkpoint.systemPrompt,
            recentTurns: checkpoint.recentTurns,
            totalSessions: checkpoint.totalSessions
        )

        await refreshCountStats()
        let proceduralCount = await proceduralStore.count
        mutateStats { snapshot in
            snapshot.totalSessions = checkpoint.totalSessions
            snapshot.proceduralCount = proceduralCount
        }
    }

    private func scoreMemory(
        taskEmbedding: [Float],
        chunks: [MemoryChunk],
        halfLifeDays: Double
    ) async throws -> [(chunk: MemoryChunk, score: Float)] {
        guard !chunks.isEmpty else {
            return []
        }

        let timestamps = chunks.map(\.createdAt)
        let halfLife = max(halfLifeDays * 86_400, 1)

        let recencyWeights = try await scoringEngine.computeRecencyWeights(
            timestamps: timestamps,
            halfLife: halfLife
        )

        let baseScores = try await scoringEngine.scoreChunksUnsorted(
            query: taskEmbedding,
            chunks: chunks,
            recencyWeights: recencyWeights,
            relevanceWeight: configuration.relevanceWeight,
            recencyWeight: max(0, 1.0 - configuration.relevanceWeight)
        )

        return baseScores
            .map { item in
                let weightedScore = item.score * max(item.chunk.retentionScore, 0)
                return (chunk: item.chunk, score: weightedScore)
            }
            .filter { $0.score > 0.0001 }
            .sorted {
                if $0.score == $1.score {
                    return $0.chunk.createdAt > $1.chunk.createdAt
                }
                return $0.score > $1.score
            }
    }

    private func makeProceduralCandidates(
        tools: [ToolCall],
        taskEmbedding: [Float],
        sessionID: UUID
    ) -> [(chunk: MemoryChunk, score: Float)] {
        guard !tools.isEmpty else {
            return []
        }

        return tools.enumerated().map { index, tool in
            let content = "Tool \(tool.name): input=\(tool.input) output=\(tool.output)"
            let chunk = MemoryChunk(
                content: content,
                embedding: taskEmbedding,
                type: .procedural,
                createdAt: .now,
                lastAccessedAt: .now,
                accessCount: 1,
                retentionScore: 1.0,
                sourceSessionID: sessionID,
                metadata: ["durationMs": String(format: "%.2f", tool.durationMs)]
            )

            let decay = Float(index) * 0.01
            let score = max(0.25, 0.75 - decay)
            return (chunk: chunk, score: score)
        }
    }

    private func applyAttentionRerank(
        query: [Float],
        scoredMemory: [(chunk: MemoryChunk, score: Float)]
    ) async throws -> [(chunk: MemoryChunk, score: Float)] {
        guard scoredMemory.count > 1 else {
            return scoredMemory
        }

        let chunks = scoredMemory.map(\.chunk)
        let attentionScores = try await attentionEngine.scoreWindowForEviction(
            taskQuery: query,
            windowChunks: chunks,
            relevanceWeight: configuration.relevanceWeight,
            centralityWeight: configuration.centralityWeight
        )

        let evictionByID = Dictionary(uniqueKeysWithValues: attentionScores.map { ($0.chunk.id, $0.evictionScore) })
        let values = attentionScores.map(\.evictionScore)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = max(maxValue - minValue, 0.000_001)

        let reranked = scoredMemory.map { item -> (chunk: MemoryChunk, score: Float) in
            let eviction = evictionByID[item.chunk.id] ?? minValue
            let normalized = (eviction - minValue) / range
            let keepScore = 1.0 - normalized
            let blended = (item.score * 0.85) + (keepScore * 0.15)
            return (chunk: item.chunk, score: blended)
        }

        return reranked.sorted {
            if $0.score == $1.score {
                return $0.chunk.createdAt > $1.chunk.createdAt
            }
            return $0.score > $1.score
        }
    }

    private func embedText(_ text: String) async throws -> [Float] {
        do {
            return try await embeddingProvider.embed(text)
        } catch let error as ContextCoreError {
            throw error
        } catch {
            Logger.contextCore.error("Error in embedText(_:): \(error.localizedDescription, privacy: .public)")
            throw ContextCoreError.embeddingFailed(error.localizedDescription)
        }
    }

    private func guaranteedTokenUsage() -> Int {
        var total = 0

        if let systemPrompt = sessionStore.systemPrompt {
            total += tokenCounter.count(systemPrompt)
        }

        for turn in sessionStore.guaranteedRecentTurns(count: configuration.recentTurnsGuaranteed) {
            total += max(0, turn.tokenCount > 0 ? turn.tokenCount : tokenCounter.count(turn.content))
        }

        return total
    }

    private func deduplicate(chunks: [MemoryChunk]) -> [MemoryChunk] {
        var seen = Set<UUID>()
        var deduped: [MemoryChunk] = []
        deduped.reserveCapacity(chunks.count)

        for chunk in chunks where !seen.contains(chunk.id) {
            seen.insert(chunk.id)
            deduped.append(chunk)
        }

        return deduped
    }

    private func mutateStats(_ mutation: @Sendable (inout ContextStats) -> Void) {
        statsLock.withLock { snapshot in
            mutation(&snapshot)
        }
    }

    private func refreshCountStats(lastConsolidationLatencyMs: Double? = nil) async {
        let episodicCount = await episodicStore.count
        let semanticCount = await semanticStore.count
        let proceduralCount = await proceduralStore.count
        let totalSessions = sessionStore.totalSessions

        mutateStats { snapshot in
            snapshot.episodicCount = episodicCount
            snapshot.semanticCount = semanticCount
            snapshot.proceduralCount = proceduralCount
            snapshot.totalSessions = totalSessions
            if let lastConsolidationLatencyMs {
                snapshot.lastConsolidationLatencyMs = lastConsolidationLatencyMs
            }
        }
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 0
        }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }

        let denominator = lhsNorm.squareRoot() * rhsNorm.squareRoot()
        guard denominator > 0 else {
            return 0
        }

        return dot / denominator
    }
}
