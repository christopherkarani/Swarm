import Foundation

/// Compression outcome for a single candidate chunk.
public struct ProgressiveCompressionResult: Sendable {
    /// Original uncompressed chunk.
    public let originalChunk: MemoryChunk
    /// Compressed content when retained; `nil` when dropped.
    public let compressedContent: String?
    /// Compression level applied.
    public let compressionLevel: CompressionLevel
    /// Original token count.
    public let originalTokens: Int
    /// Token count after compression.
    public let compressedTokens: Int
    /// Tokens removed by compression or dropping.
    public let tokensSaved: Int

    /// Creates a progressive compression result.
    ///
    /// - Parameters:
    ///   - originalChunk: Source chunk.
    ///   - compressedContent: Compressed content or `nil` when dropped.
    ///   - compressionLevel: Applied compression level.
    ///   - originalTokens: Original token count.
    ///   - compressedTokens: Compressed token count.
    ///   - tokensSaved: Tokens removed.
    public init(
        originalChunk: MemoryChunk,
        compressedContent: String?,
        compressionLevel: CompressionLevel,
        originalTokens: Int,
        compressedTokens: Int,
        tokensSaved: Int
    ) {
        self.originalChunk = originalChunk
        self.compressedContent = compressedContent
        self.compressionLevel = compressionLevel
        self.originalTokens = originalTokens
        self.compressedTokens = compressedTokens
        self.tokensSaved = tokensSaved
    }

    /// Converts the result into a context chunk when retained.
    ///
    /// - Parameters:
    ///   - score: Score assigned to this candidate.
    ///   - source: Memory source for the resulting context chunk.
    /// - Returns: A context chunk or `nil` when compression level is `.dropped`.
    public func toContextChunk(score: Float, source: MemoryType) -> ContextChunk? {
        guard compressionLevel != .dropped else {
            return nil
        }

        let content = compressedContent ?? originalChunk.content
        return ContextChunk(
            id: originalChunk.id,
            content: content,
            role: .system,
            tokenCount: compressedTokens,
            score: score,
            source: source,
            compressionLevel: compressionLevel,
            timestamp: originalChunk.createdAt,
            isGuaranteedRecent: false,
            isSystemPrompt: false
        )
    }
}

/// Applies progressive, score-aware compression to satisfy budget deficits.
public actor ProgressiveCompressor {
    private let compressionEngine: CompressionEngine
    private let tokenCounter: any TokenCounter

    /// Creates a progressive compressor.
    ///
    /// - Parameters:
    ///   - compressionEngine: Engine used for light/heavy compression passes.
    ///   - tokenCounter: Token counter used for deficit accounting.
    public init(
        compressionEngine: CompressionEngine,
        tokenCounter: any TokenCounter
    ) {
        self.compressionEngine = compressionEngine
        self.tokenCounter = tokenCounter
    }

    /// Progressively compresses low-priority candidates until deficit is recovered.
    ///
    /// - Parameters:
    ///   - candidates: Candidates ordered by eviction preference.
    ///   - tokenDeficit: Number of tokens that must be removed.
    /// - Returns: Compression outcomes aligned with input order.
    /// - Throws: Propagates compression-engine failures.
    public func compress(
        candidates: [(chunk: MemoryChunk, evictionScore: Float)],
        tokenDeficit: Int
    ) async throws -> [ProgressiveCompressionResult] {
        if tokenDeficit <= 0 {
            return candidates.map { makeUnchangedResult(for: $0.chunk) }
        }

        var remainingDeficit = tokenDeficit
        var results: [ProgressiveCompressionResult] = []
        results.reserveCapacity(candidates.count)

        for candidate in candidates {
            let chunk = candidate.chunk

            if remainingDeficit <= 0 {
                results.append(makeUnchangedResult(for: chunk))
                continue
            }

            let originalTokens = tokenCounter.count(chunk.content)
            if originalTokens == 0 {
                results.append(makeUnchangedResult(for: chunk))
                continue
            }

            let lightTarget = max(1, originalTokens / 2)
            let lightCompressed = try await compressionEngine.compress(
                chunk: chunk,
                targetTokens: lightTarget
            )
            let lightTokens = min(originalTokens, tokenCounter.count(lightCompressed.content))
            let lightSaved = max(0, originalTokens - lightTokens)

            if lightSaved >= remainingDeficit {
                remainingDeficit -= lightSaved
                results.append(
                    ProgressiveCompressionResult(
                        originalChunk: chunk,
                        compressedContent: lightCompressed.content,
                        compressionLevel: .light,
                        originalTokens: originalTokens,
                        compressedTokens: lightTokens,
                        tokensSaved: lightSaved
                    )
                )
                continue
            }

            let heavyTarget = max(1, originalTokens / 4)
            let heavyCompressed = try await compressionEngine.compress(
                chunk: chunk,
                targetTokens: heavyTarget
            )
            let heavyTokens = min(originalTokens, tokenCounter.count(heavyCompressed.content))
            let heavySaved = max(0, originalTokens - heavyTokens)

            if heavySaved >= remainingDeficit {
                remainingDeficit -= heavySaved
                results.append(
                    ProgressiveCompressionResult(
                        originalChunk: chunk,
                        compressedContent: heavyCompressed.content,
                        compressionLevel: .heavy,
                        originalTokens: originalTokens,
                        compressedTokens: heavyTokens,
                        tokensSaved: heavySaved
                    )
                )
                continue
            }

            remainingDeficit -= originalTokens
            results.append(
                ProgressiveCompressionResult(
                    originalChunk: chunk,
                    compressedContent: nil,
                    compressionLevel: .dropped,
                    originalTokens: originalTokens,
                    compressedTokens: 0,
                    tokensSaved: originalTokens
                )
            )
        }

        return results
    }

    private func makeUnchangedResult(for chunk: MemoryChunk) -> ProgressiveCompressionResult {
        let originalTokens = tokenCounter.count(chunk.content)
        return ProgressiveCompressionResult(
            originalChunk: chunk,
            compressedContent: chunk.content,
            compressionLevel: .none,
            originalTokens: originalTokens,
            compressedTokens: originalTokens,
            tokensSaved: 0
        )
    }
}
