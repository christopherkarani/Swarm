import Foundation

protocol SentenceRanker: Sendable {
    func rankSentences(
        in chunk: String,
        chunkEmbedding: [Float]
    ) async throws -> [(sentence: String, importance: Float)]
}

extension CompressionEngine: SentenceRanker {}

/// Packs system prompt, recent turns, and ranked memory into a token budget.
public actor WindowPacker {
    private let sentenceRanker: any SentenceRanker
    private let tokenCounter: any TokenCounter
    private let minimumChunkSize: Int
    private let recentTurnsGuaranteed: Int
    private let progressiveCompressor: ProgressiveCompressor?

    /// Creates a production window packer.
    ///
    /// - Parameters:
    ///   - compressionEngine: Compression engine used for sentence ranking and fallback compression.
    ///   - tokenCounter: Token counter used for budget accounting.
    ///   - minimumChunkSize: Remaining budget threshold below which packing stops.
    ///   - recentTurnsGuaranteed: Number of latest turns that must always be included.
    public init(
        compressionEngine: CompressionEngine,
        tokenCounter: any TokenCounter,
        minimumChunkSize: Int = 50,
        recentTurnsGuaranteed: Int = 3
    ) {
        self.sentenceRanker = compressionEngine
        self.tokenCounter = tokenCounter
        self.minimumChunkSize = max(0, minimumChunkSize)
        self.recentTurnsGuaranteed = max(0, recentTurnsGuaranteed)
        self.progressiveCompressor = ProgressiveCompressor(
            compressionEngine: compressionEngine,
            tokenCounter: tokenCounter
        )
    }

    init(
        sentenceRanker: any SentenceRanker,
        tokenCounter: any TokenCounter,
        minimumChunkSize: Int = 50,
        recentTurnsGuaranteed: Int = 3,
        progressiveCompressor: ProgressiveCompressor? = nil
    ) {
        self.sentenceRanker = sentenceRanker
        self.tokenCounter = tokenCounter
        self.minimumChunkSize = max(0, minimumChunkSize)
        self.recentTurnsGuaranteed = max(0, recentTurnsGuaranteed)
        self.progressiveCompressor = progressiveCompressor
    }

    /// Packs context candidates into a budget-constrained ``ContextWindow``.
    ///
    /// - Parameters:
    ///   - systemPrompt: Optional system instruction to pin at the top.
    ///   - recentTurns: Turn buffer eligible for guaranteed inclusion.
    ///   - scoredMemory: Ranked memory candidates.
    ///   - budget: Effective token budget.
    /// - Returns: Packed context window.
    /// - Throws: Propagates compression and embedding errors from dependencies.
    ///
    /// - Complexity: O(n log n) for candidate sorting plus optional compression work.
    public func pack(
        systemPrompt: String?,
        recentTurns: [Turn],
        scoredMemory: [(chunk: MemoryChunk, score: Float)],
        budget: Int
    ) async throws -> ContextWindow {
        var remainingTokens = budget
        var packedChunks: [ContextChunk] = []

        if let systemPrompt {
            let chunk = makeSystemPromptChunk(from: systemPrompt)
            remainingTokens -= chunk.tokenCount
            packedChunks.append(chunk)
        }

        let guaranteedTurns = recentTurns.suffix(recentTurnsGuaranteed)
        for turn in guaranteedTurns {
            let chunk = makeChunk(from: turn, isGuaranteedRecent: true)
            remainingTokens -= chunk.tokenCount
            packedChunks.append(chunk)
        }

        let sortedMemory = scoredMemory.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.chunk.createdAt == rhs.chunk.createdAt {
                    return lhs.chunk.id.uuidString < rhs.chunk.id.uuidString
                }
                return lhs.chunk.createdAt < rhs.chunk.createdAt
            }
            return lhs.score > rhs.score
        }

        var index = 0
        while index < sortedMemory.count {
            if remainingTokens < minimumChunkSize {
                break
            }

            let candidate = sortedMemory[index]
            let fullChunk = makeChunk(from: candidate.chunk, score: candidate.score)
            if fullChunk.tokenCount <= remainingTokens {
                packedChunks.append(fullChunk)
                remainingTokens -= fullChunk.tokenCount
                index += 1
                continue
            }

            if let progressiveCompressor {
                let tail = Array(sortedMemory[index...])
                let tailTotalTokens = tail.reduce(into: 0) { partial, value in
                    partial += tokenCounter.count(value.chunk.content)
                }
                let deficit = max(0, tailTotalTokens - remainingTokens)

                let ascendingCandidates = tail.sorted(by: ascendingScoreOrder)
                let progressiveResults = try await progressiveCompressor.compress(
                    candidates: ascendingCandidates.map { (chunk: $0.chunk, evictionScore: $0.score) },
                    tokenDeficit: deficit
                )
                let resultByID = Dictionary(
                    uniqueKeysWithValues: progressiveResults.map { ($0.originalChunk.id, $0) }
                )

                for memoryCandidate in tail {
                    guard let result = resultByID[memoryCandidate.chunk.id] else {
                        continue
                    }
                    guard let contextChunk = result.toContextChunk(
                        score: memoryCandidate.score,
                        source: memoryCandidate.chunk.type
                    ) else {
                        continue
                    }
                    guard contextChunk.tokenCount <= remainingTokens else {
                        break
                    }

                    packedChunks.append(contextChunk)
                    remainingTokens -= contextChunk.tokenCount
                }
                break
            } else if let compressedChunk = try await attemptCompression(
                from: candidate.chunk,
                score: candidate.score,
                targetTokens: remainingTokens
            ), compressedChunk.tokenCount <= remainingTokens {
                packedChunks.append(compressedChunk)
                remainingTokens -= compressedChunk.tokenCount
            }

            index += 1
        }

        return ContextWindow(chunks: packedChunks, budget: budget)
    }

    private func ascendingScoreOrder(
        _ lhs: (chunk: MemoryChunk, score: Float),
        _ rhs: (chunk: MemoryChunk, score: Float)
    ) -> Bool {
        if lhs.score == rhs.score {
            if lhs.chunk.createdAt == rhs.chunk.createdAt {
                return lhs.chunk.id.uuidString < rhs.chunk.id.uuidString
            }
            return lhs.chunk.createdAt < rhs.chunk.createdAt
        }
        return lhs.score < rhs.score
    }

    private func makeSystemPromptChunk(from prompt: String) -> ContextChunk {
        ContextChunk(
            content: prompt,
            role: .system,
            tokenCount: tokenCounter.count(prompt),
            score: 1.0,
            source: .semantic,
            compressionLevel: .none,
            timestamp: .now,
            isGuaranteedRecent: false,
            isSystemPrompt: true
        )
    }

    private func makeChunk(
        from turn: Turn,
        isGuaranteedRecent: Bool = false
    ) -> ContextChunk {
        ContextChunk(
            id: turn.id,
            content: turn.content,
            role: turn.role,
            tokenCount: tokenCounter.count(turn.content),
            score: 1.0,
            source: .episodic,
            compressionLevel: .none,
            timestamp: turn.timestamp,
            isGuaranteedRecent: isGuaranteedRecent,
            isSystemPrompt: false
        )
    }

    private func makeChunk(
        from memory: MemoryChunk,
        score: Float,
        content: String? = nil,
        compressionLevel: CompressionLevel = .none
    ) -> ContextChunk {
        let resolvedContent = content ?? memory.content
        return ContextChunk(
            id: memory.id,
            content: resolvedContent,
            role: .system,
            tokenCount: tokenCounter.count(resolvedContent),
            score: score,
            source: memory.type,
            compressionLevel: compressionLevel,
            timestamp: memory.createdAt,
            isGuaranteedRecent: false,
            isSystemPrompt: false
        )
    }

    private func attemptCompression(
        from memory: MemoryChunk,
        score: Float,
        targetTokens: Int
    ) async throws -> ContextChunk? {
        guard targetTokens > 0 else {
            return nil
        }

        let ranked = try await sentenceRanker.rankSentences(
            in: memory.content,
            chunkEmbedding: memory.embedding
        )

        guard !ranked.isEmpty else {
            return nil
        }

        let topSentence = ranked[0].sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topSentence.isEmpty else {
            return nil
        }

        if tokenCounter.count(topSentence) > targetTokens {
            return nil
        }

        var selectedSentences: [String] = []
        var runningTokenTotal = 0

        for candidate in ranked {
            let sentence = candidate.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else {
                continue
            }

            let sentenceTokens = tokenCounter.count(sentence)
            if runningTokenTotal + sentenceTokens <= targetTokens {
                selectedSentences.append(sentence)
                runningTokenTotal += sentenceTokens
            }
        }

        guard !selectedSentences.isEmpty else {
            return nil
        }

        var compressedContent = selectedSentences.joined(separator: " ")
        var compressedTokens = tokenCounter.count(compressedContent)

        while compressedTokens > targetTokens && !selectedSentences.isEmpty {
            selectedSentences.removeLast()
            compressedContent = selectedSentences.joined(separator: " ")
            compressedTokens = tokenCounter.count(compressedContent)
        }

        guard !selectedSentences.isEmpty else {
            return nil
        }

        return makeChunk(
            from: memory,
            score: score,
            content: compressedContent,
            compressionLevel: .light
        )
    }
}
