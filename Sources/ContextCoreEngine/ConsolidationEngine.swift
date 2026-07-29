import ContextCoreTypes
import Foundation
import Metal

/// Summary metrics from a consolidation pass.
public struct ConsolidationResult: Sendable, Equatable {
    /// Number of duplicate pairs found.
    public let duplicatePairsFound: Int
    /// Number of facts promoted to semantic memory.
    public let factsPromoted: Int
    /// Number of episodic chunks evicted.
    public let chunksEvicted: Int
    /// Consolidation duration in milliseconds.
    public let durationMs: Double

    /// Creates a consolidation result.
    public init(
        duplicatePairsFound: Int,
        factsPromoted: Int,
        chunksEvicted: Int,
        durationMs: Double
    ) {
        self.duplicatePairsFound = duplicatePairsFound
        self.factsPromoted = factsPromoted
        self.chunksEvicted = chunksEvicted
        self.durationMs = durationMs
    }
}

/// GPU-backed consolidation engine for deduplication, promotion, and contradiction detection.
public actor ConsolidationEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pairwisePipeline: MTLComputePipelineState
    private let pairwiseTiledPipeline: MTLComputePipelineState
    private let mergeCandidatePipeline: MTLComputePipelineState
    private let antipodalPipeline: MTLComputePipelineState
    private let embeddingProvider: any EmbeddingProvider

    /// Creates a consolidation engine and compiles required Metal pipelines.
    ///
    /// - Parameters:
    ///   - device: Optional Metal device override.
    ///   - embeddingProvider: Embedding provider used by downstream flows.
    /// - Throws: Metal initialization or pipeline creation failures.
    public init(
        device: MTLDevice? = nil,
        embeddingProvider: any EmbeddingProvider
    ) throws {
        self.device = try device ?? MetalContext.device()
        self.commandQueue = try MetalContext.commandQueue(device: self.device)
        self.embeddingProvider = embeddingProvider

        let library = try MetalContext.library(device: self.device)

        guard let pairwiseFunction = library.makeFunction(name: "pairwise_similarity") else {
            throw ContextCoreError.compressionFailed("Missing pairwise_similarity function")
        }
        guard let pairwiseTiledFunction = library.makeFunction(name: "pairwise_similarity_tiled") else {
            throw ContextCoreError.compressionFailed("Missing pairwise_similarity_tiled function")
        }
        guard let mergeFunction = library.makeFunction(name: "find_merge_candidates") else {
            throw ContextCoreError.compressionFailed("Missing find_merge_candidates function")
        }
        guard let antipodalFunction = library.makeFunction(name: "antipodal_test") else {
            throw ContextCoreError.compressionFailed("Missing antipodal_test function")
        }

        self.pairwisePipeline = try self.device.makeComputePipelineState(function: pairwiseFunction)
        self.pairwiseTiledPipeline = try self.device.makeComputePipelineState(function: pairwiseTiledFunction)
        self.mergeCandidatePipeline = try self.device.makeComputePipelineState(function: mergeFunction)
        self.antipodalPipeline = try self.device.makeComputePipelineState(function: antipodalFunction)
    }

    /// Finds duplicate episodic chunk pairs above a similarity threshold.
    ///
    /// - Parameters:
    ///   - store: Episodic store to scan.
    ///   - threshold: Cosine similarity threshold for duplicate candidacy.
    /// - Returns: Duplicate chunk ID pairs.
    /// - Throws: Dimension mismatch and Metal execution errors.
    public func findDuplicates(
        in store: any ConsolidationEpisodicStore,
        threshold: Float = 0.92
    ) async throws -> [(UUID, UUID)] {
        let allChunks = await store.allChunks()
        let chunks = await unconsolidatedChunks(from: allChunks, store: store)

        guard chunks.count > 1 else {
            return []
        }

        let pairs = try await findDuplicateIndexPairs(in: chunks, threshold: threshold)

        return pairs.map { (chunks[$0.0].id, chunks[$0.1].id) }
    }

    /// Computes pairwise cosine similarity for embedding vectors.
    ///
    /// - Parameter embeddings: Embeddings to compare.
    /// - Returns: Dense symmetric similarity matrix.
    /// - Throws: ``ContextCoreError/dimensionMismatch(expected:got:)`` for inconsistent dimensions.
    public func pairwiseSimilarity(
        embeddings: [[Float]]
    ) async throws -> [[Float]] {
        guard !embeddings.isEmpty else {
            return []
        }
        if embeddings.count == 1 {
            return [[1.0]]
        }

        let dim = embeddings[0].count
        guard embeddings.allSatisfy({ $0.count == dim }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dim,
                got: embeddings.first(where: { $0.count != dim })?.count ?? 0
            )
        }

        let n = embeddings.count
        var matrix = Array(repeating: Array(repeating: Float.zero, count: n), count: n)
        for index in 0..<n {
            matrix[index][index] = 1.0
        }

        if n <= 2048 {
            let flattened = embeddings.flatMap { $0 }
            let upper = try await computePairwiseUpperSimple(
                flattenedEmbeddings: flattened,
                dim: dim,
                n: n
            )

            for i in 0..<n {
                for j in (i + 1)..<n {
                    let value = upper[(i * n) + j]
                    matrix[i][j] = value
                    matrix[j][i] = value
                }
            }
            return matrix
        }

        let flattened = embeddings.flatMap { $0 }
        guard let embeddingsBuffer = device.makeBuffer(from: flattened) else {
            throw ContextCoreError.compressionFailed("Failed to allocate embeddings buffer")
        }

        for rowTile in stride(from: 0, to: n, by: 512) {
            let rowCount = min(512, n - rowTile)
            for colTile in stride(from: rowTile, to: n, by: 512) {
                let colCount = min(512, n - colTile)
                let tile = try await computeTileSimilarities(
                    embeddingsBuffer: embeddingsBuffer,
                    dim: dim,
                    n: n,
                    rowOffset: rowTile,
                    colOffset: colTile,
                    rowCount: rowCount,
                    colCount: colCount
                )

                for localRow in 0..<rowCount {
                    let globalRow = rowTile + localRow
                    for localCol in 0..<colCount {
                        let globalCol = colTile + localCol
                        guard globalCol > globalRow else {
                            continue
                        }

                        let value = tile[(localRow * colCount) + localCol]
                        matrix[globalRow][globalCol] = value
                        matrix[globalCol][globalRow] = value
                    }
                }
            }
        }

        return matrix
    }

    /// Runs a full consolidation pass for the active session.
    ///
    /// - Parameters:
    ///   - session: Session identifier used for bookkeeping.
    ///   - episodicStore: Episodic memory store.
    ///   - semanticStore: Semantic memory store.
    ///   - threshold: Duplicate similarity threshold.
    /// - Returns: Consolidation summary.
    /// - Throws: Store, dimension, and Metal execution errors.
    public func consolidate(
        session _: UUID,
        episodicStore: any ConsolidationEpisodicStore,
        semanticStore: any ConsolidationSemanticStore,
        threshold: Float = 0.92
    ) async throws -> ConsolidationResult {
        let start = Date()
        let allChunks = await episodicStore.allChunks()
        let unconsolidated = await unconsolidatedChunks(from: allChunks, store: episodicStore)
        let pairs = try await findDuplicateIndexPairs(in: unconsolidated, threshold: threshold)

        var chunkMap = Dictionary(uniqueKeysWithValues: allChunks.map { ($0.id, $0) })

        var promotedIDs = Set<UUID>()
        var processedChunkIDs = Set<UUID>()

        for (indexA, indexB) in pairs {
            let chunkA = unconsolidated[indexA]
            let chunkB = unconsolidated[indexB]
            guard !processedChunkIDs.contains(chunkA.id), !processedChunkIDs.contains(chunkB.id) else {
                continue
            }
            guard await !episodicStore.isConsolidated(id: chunkA.id),
                  await !episodicStore.isConsolidated(id: chunkB.id)
            else {
                continue
            }

            processedChunkIDs.insert(chunkA.id)
            processedChunkIDs.insert(chunkB.id)

            let factChunk = chunkA.content.count <= chunkB.content.count ? chunkA : chunkB
            if !promotedIDs.contains(factChunk.id) {
                try await semanticStore.upsert(fact: factChunk.content, embedding: factChunk.embedding)
                promotedIDs.insert(factChunk.id)
            }

            try await episodicStore.updateRetentionScore(id: chunkA.id, delta: -0.2)
            try await episodicStore.updateRetentionScore(id: chunkB.id, delta: -0.2)
            if var updatedA = chunkMap[chunkA.id] {
                updatedA.retentionScore = max(0, min(1, updatedA.retentionScore - 0.2))
                chunkMap[chunkA.id] = updatedA
            }
            if var updatedB = chunkMap[chunkB.id] {
                updatedB.retentionScore = max(0, min(1, updatedB.retentionScore - 0.2))
                chunkMap[chunkB.id] = updatedB
            }
            try await episodicStore.markConsolidated(id: chunkA.id)
            try await episodicStore.markConsolidated(id: chunkB.id)
        }

        var evicted = 0
        for chunk in chunkMap.values where chunk.retentionScore < 0.1 {
            try await episodicStore.evict(id: chunk.id)
            evicted += 1
        }

        let durationMs = Date().timeIntervalSince(start) * 1000
        return ConsolidationResult(
            duplicatePairsFound: pairs.count,
            factsPromoted: promotedIDs.count,
            chunksEvicted: evicted,
            durationMs: durationMs
        )
    }

    /// Finds contradiction candidates from semantic memory.
    ///
    /// - Parameters:
    ///   - store: Semantic store to scan.
    ///   - similarityThreshold: Lower bound for pair similarity.
    ///   - antipodalThreshold: Lower bound for sign-flip fraction.
    /// - Returns: Candidate contradictory fact pairs.
    /// - Throws: Pairwise similarity or antipodal computation errors.
    public func contradictionCandidates(
        in store: any ConsolidationSemanticStore,
        similarityThreshold: Float = 0.75,
        antipodalThreshold: Float = 0.30
    ) async throws -> [(MemoryChunk, MemoryChunk)] {
        let facts = await store.allChunks()
        guard facts.count > 1 else {
            return []
        }

        let embeddings = facts.map(\.embedding)
        let similarities = try await pairwiseSimilarity(embeddings: embeddings)

        var candidateIndices: [(Int, Int)] = []
        for i in 0..<facts.count {
            for j in (i + 1)..<facts.count where similarities[i][j] > similarityThreshold {
                candidateIndices.append((i, j))
            }
        }

        guard !candidateIndices.isEmpty else {
            return []
        }

        let dim = embeddings[0].count
        var embeddingsA: [Float] = []
        var embeddingsB: [Float] = []
        embeddingsA.reserveCapacity(candidateIndices.count * dim)
        embeddingsB.reserveCapacity(candidateIndices.count * dim)

        for (i, j) in candidateIndices {
            embeddingsA.append(contentsOf: embeddings[i])
            embeddingsB.append(contentsOf: embeddings[j])
        }

        let fractions = try await runAntipodalFractions(
            embeddingsA: embeddingsA,
            embeddingsB: embeddingsB,
            dim: dim,
            pairCount: candidateIndices.count
        )

        var matches: [(MemoryChunk, MemoryChunk)] = []
        for idx in candidateIndices.indices where fractions[idx] > antipodalThreshold {
            let (i, j) = candidateIndices[idx]
            matches.append((facts[i], facts[j]))
        }

        return matches
    }

    /// Computes antipodal fractions for embedding pairs.
    ///
    /// - Parameters:
    ///   - embeddingsA: First embedding list.
    ///   - embeddingsB: Second embedding list.
    /// - Returns: Sign-flip fractions per pair.
    /// - Throws: ``ContextCoreError/dimensionMismatch(expected:got:)`` for inconsistent dimensions.
    public func antipodalFractions(
        embeddingsA: [[Float]],
        embeddingsB: [[Float]]
    ) async throws -> [Float] {
        guard embeddingsA.count == embeddingsB.count else {
            throw ContextCoreError.dimensionMismatch(expected: embeddingsA.count, got: embeddingsB.count)
        }
        guard !embeddingsA.isEmpty else {
            return []
        }

        let dim = embeddingsA[0].count
        guard embeddingsA.allSatisfy({ $0.count == dim }), embeddingsB.allSatisfy({ $0.count == dim }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dim,
                got: embeddingsA.first(where: { $0.count != dim })?.count
                    ?? embeddingsB.first(where: { $0.count != dim })?.count
                    ?? 0
            )
        }

        let flatA = embeddingsA.flatMap { $0 }
        let flatB = embeddingsB.flatMap { $0 }
        return try await runAntipodalFractions(
            embeddingsA: flatA,
            embeddingsB: flatB,
            dim: dim,
            pairCount: embeddingsA.count
        )
    }

    private func validateDimensions(_ chunks: [MemoryChunk]) throws -> Int {
        guard let dim = chunks.first?.embedding.count, dim > 0 else {
            throw ContextCoreError.dimensionMismatch(expected: 1, got: 0)
        }
        guard chunks.allSatisfy({ $0.embedding.count == dim }) else {
            throw ContextCoreError.dimensionMismatch(
                expected: dim,
                got: chunks.first(where: { $0.embedding.count != dim })?.embedding.count ?? 0
            )
        }
        return dim
    }

    private func unconsolidatedChunks(
        from allChunks: [MemoryChunk],
        store: any ConsolidationEpisodicStore
    ) async -> [MemoryChunk] {
        var chunks: [MemoryChunk] = []
        chunks.reserveCapacity(allChunks.count)

        for chunk in allChunks {
            if await store.isConsolidated(id: chunk.id) {
                continue
            }
            chunks.append(chunk)
        }

        return chunks
    }

    private func findDuplicateIndexPairs(
        in chunks: [MemoryChunk],
        threshold: Float
    ) async throws -> [(Int, Int)] {
        guard chunks.count > 1 else {
            return []
        }

        let dim = try validateDimensions(chunks)
        if chunks.count <= 2048 {
            return try await findCandidatesSimple(chunks: chunks, dim: dim, threshold: threshold)
        }

        return try await findCandidatesTiled(chunks: chunks, dim: dim, threshold: threshold, tileSize: 512)
    }

    private func findCandidatesSimple(
        chunks: [MemoryChunk],
        dim: Int,
        threshold: Float
    ) async throws -> [(Int, Int)] {
        let n = chunks.count
        let flattened = chunks.flatMap(\.embedding)
        var candidateCountStorage: UInt32 = 0
        let maxCandidates = max(1, n * 10)

        let similarity = try await computePairwiseUpperSimple(
            flattenedEmbeddings: flattened,
            dim: dim,
            n: n
        )

        guard let similarityBuffer = device.makeBuffer(from: similarity),
              let candidatesBuffer = device.makeBuffer(
                length: maxCandidates * MemoryLayout<SIMD2<UInt32>>.stride,
                options: .storageModeShared
              ),
              let candidateCountBuffer = device.makeBuffer(
                bytes: &candidateCountStorage,
                length: MemoryLayout<UInt32>.stride,
                options: .storageModeShared
              ),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let mergeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate consolidation buffers")
        }

        var n32 = UInt32(n)
        var thresholdValue = threshold
        var maxCandidates32 = UInt32(maxCandidates)

        guard let nBuffer = device.makeBuffer(bytes: &n32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let thresholdBuffer = device.makeBuffer(bytes: &thresholdValue, length: MemoryLayout<Float>.stride, options: .storageModeShared),
              let maxCandidatesBuffer = device.makeBuffer(bytes: &maxCandidates32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate consolidation constants")
        }

        mergeEncoder.setComputePipelineState(mergeCandidatePipeline)
        mergeEncoder.setBuffer(similarityBuffer, offset: 0, index: 0)
        mergeEncoder.setBuffer(candidatesBuffer, offset: 0, index: 1)
        mergeEncoder.setBuffer(candidateCountBuffer, offset: 0, index: 2)
        mergeEncoder.setBuffer(thresholdBuffer, offset: 0, index: 3)
        mergeEncoder.setBuffer(nBuffer, offset: 0, index: 4)
        mergeEncoder.setBuffer(maxCandidatesBuffer, offset: 0, index: 5)
        dispatch2D(
            encoder: mergeEncoder,
            width: n,
            height: n,
            pipeline: mergeCandidatePipeline
        )
        mergeEncoder.endEncoding()

        try await awaitCompletion(commandBuffer)

        let countPointer = candidateCountBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
        let rawCount = Int(countPointer[0])
        let boundedCount = min(rawCount, maxCandidates)
        if rawCount > maxCandidates {
            print("ConsolidationEngine warning: merge candidate buffer capped at \(maxCandidates) of \(rawCount)")
        }

        let pairPointer = candidatesBuffer.contents().bindMemory(to: SIMD2<UInt32>.self, capacity: boundedCount)
        return (0..<boundedCount).map { idx in
            let pair = pairPointer[idx]
            return (Int(pair.x), Int(pair.y))
        }
    }

    private func computePairwiseUpperSimple(
        flattenedEmbeddings: [Float],
        dim: Int,
        n: Int
    ) async throws -> [Float] {
        var output = [Float](repeating: 0, count: n * n)

        guard let embeddingsBuffer = device.makeBuffer(from: flattenedEmbeddings),
              let outputBuffer = device.makeBuffer(from: output),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate pairwise buffers")
        }

        var dim32 = UInt32(dim)
        var n32 = UInt32(n)

        guard let dimBuffer = device.makeBuffer(bytes: &dim32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let nBuffer = device.makeBuffer(bytes: &n32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate pairwise constants")
        }

        encoder.setComputePipelineState(pairwisePipeline)
        encoder.setBuffer(embeddingsBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(dimBuffer, offset: 0, index: 2)
        encoder.setBuffer(nBuffer, offset: 0, index: 3)
        dispatch2D(
            encoder: encoder,
            width: n,
            height: n,
            pipeline: pairwisePipeline
        )
        encoder.endEncoding()

        try await awaitCompletion(commandBuffer)

        let pointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: output.count)
        output = Array(UnsafeBufferPointer(start: pointer, count: output.count))
        return output
    }

    private func findCandidatesTiled(
        chunks: [MemoryChunk],
        dim: Int,
        threshold: Float,
        tileSize: Int
    ) async throws -> [(Int, Int)] {
        let n = chunks.count
        let flattened = chunks.flatMap(\.embedding)

        guard let embeddingsBuffer = device.makeBuffer(from: flattened) else {
            throw ContextCoreError.compressionFailed("Failed to allocate embeddings buffer for tiled path")
        }

        var candidates: [(Int, Int)] = []

        for rowTile in stride(from: 0, to: n, by: tileSize) {
            let rowCount = min(tileSize, n - rowTile)
            for colTile in stride(from: rowTile, to: n, by: tileSize) {
                let colCount = min(tileSize, n - colTile)
                let tileSimilarities = try await computeTileSimilarities(
                    embeddingsBuffer: embeddingsBuffer,
                    dim: dim,
                    n: n,
                    rowOffset: rowTile,
                    colOffset: colTile,
                    rowCount: rowCount,
                    colCount: colCount
                )

                for localRow in 0..<rowCount {
                    let globalRow = rowTile + localRow
                    for localCol in 0..<colCount {
                        let globalCol = colTile + localCol
                        guard globalCol > globalRow else {
                            continue
                        }
                        let score = tileSimilarities[(localRow * colCount) + localCol]
                        if score > threshold {
                            candidates.append((globalRow, globalCol))
                        }
                    }
                }
            }
        }

        return candidates
    }

    private func computeTileSimilarities(
        embeddingsBuffer: MTLBuffer,
        dim: Int,
        n: Int,
        rowOffset: Int,
        colOffset: Int,
        rowCount: Int,
        colCount: Int
    ) async throws -> [Float] {
        var output = [Float](repeating: 0, count: rowCount * colCount)

        guard let tileBuffer = device.makeBuffer(from: output),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate tiled consolidation buffers")
        }

        var dim32 = UInt32(dim)
        var n32 = UInt32(n)
        var rowOffset32 = UInt32(rowOffset)
        var colOffset32 = UInt32(colOffset)
        var rowCount32 = UInt32(rowCount)
        var colCount32 = UInt32(colCount)

        guard let dimBuffer = device.makeBuffer(bytes: &dim32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let nBuffer = device.makeBuffer(bytes: &n32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let rowOffsetBuffer = device.makeBuffer(bytes: &rowOffset32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let colOffsetBuffer = device.makeBuffer(bytes: &colOffset32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let rowCountBuffer = device.makeBuffer(bytes: &rowCount32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let colCountBuffer = device.makeBuffer(bytes: &colCount32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate tiled consolidation constants")
        }

        encoder.setComputePipelineState(pairwiseTiledPipeline)
        encoder.setBuffer(embeddingsBuffer, offset: 0, index: 0)
        encoder.setBuffer(tileBuffer, offset: 0, index: 1)
        encoder.setBuffer(dimBuffer, offset: 0, index: 2)
        encoder.setBuffer(nBuffer, offset: 0, index: 3)
        encoder.setBuffer(rowOffsetBuffer, offset: 0, index: 4)
        encoder.setBuffer(colOffsetBuffer, offset: 0, index: 5)
        encoder.setBuffer(rowCountBuffer, offset: 0, index: 6)
        encoder.setBuffer(colCountBuffer, offset: 0, index: 7)

        dispatch2D(
            encoder: encoder,
            width: rowCount,
            height: colCount,
            pipeline: pairwiseTiledPipeline
        )
        encoder.endEncoding()

        try await awaitCompletion(commandBuffer)

        let pointer = tileBuffer.contents().bindMemory(to: Float.self, capacity: output.count)
        output = Array(UnsafeBufferPointer(start: pointer, count: output.count))
        return output
    }

    private func runAntipodalFractions(
        embeddingsA: [Float],
        embeddingsB: [Float],
        dim: Int,
        pairCount: Int
    ) async throws -> [Float] {
        var output = [Float](repeating: 0, count: pairCount)

        guard let embeddingsABuffer = device.makeBuffer(from: embeddingsA),
              let embeddingsBBuffer = device.makeBuffer(from: embeddingsB),
              let outputBuffer = device.makeBuffer(from: output),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate antipodal buffers")
        }

        var dim32 = UInt32(dim)
        var pairCount32 = UInt32(pairCount)

        guard let dimBuffer = device.makeBuffer(bytes: &dim32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let pairCountBuffer = device.makeBuffer(bytes: &pairCount32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate antipodal constants")
        }

        encoder.setComputePipelineState(antipodalPipeline)
        encoder.setBuffer(embeddingsABuffer, offset: 0, index: 0)
        encoder.setBuffer(embeddingsBBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBuffer(dimBuffer, offset: 0, index: 3)
        encoder.setBuffer(pairCountBuffer, offset: 0, index: 4)

        let threads = MetalContext.threadsPerThreadgroup(pipeline: antipodalPipeline, count: pairCount)
        let groups = MetalContext.threadgroups(threadsPerThreadgroup: threads, count: pairCount)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()

        try await awaitCompletion(commandBuffer)

        let pointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: pairCount)
        output = Array(UnsafeBufferPointer(start: pointer, count: pairCount))
        return output
    }

    private func dispatch2D(
        encoder: MTLComputeCommandEncoder,
        width: Int,
        height: Int,
        pipeline: MTLComputePipelineState
    ) {
        let maxThreads = max(1, pipeline.maxTotalThreadsPerThreadgroup)
        let threadWidth = min(16, maxThreads)
        let threadHeight = max(1, min(16, maxThreads / threadWidth))

        let threadsPerThreadgroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let groups = MTLSize(
            width: (width + threadWidth - 1) / threadWidth,
            height: (height + threadHeight - 1) / threadHeight,
            depth: 1
        )

        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    private func awaitCompletion(_ commandBuffer: MTLCommandBuffer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(
                        throwing: ContextCoreError.compressionFailed(
                            "Metal command failed: \(error.localizedDescription)"
                        )
                    )
                    return
                }
                continuation.resume(returning: ())
            }
            commandBuffer.commit()
        }
    }
}

/// Background trigger that schedules consolidation after insertion thresholds.
public actor ConsolidationScheduler {
    private let engine: ConsolidationEngine
    private let countThreshold: Int
    private let insertionThreshold: Int
    private let similarityThreshold: Float

    private var insertionsSinceLastConsolidation = 0
    private var isConsolidating = false
    private var triggerCountValue = 0
    private var lastResultValue: ConsolidationResult?

    /// Creates a consolidation scheduler.
    ///
    /// - Parameters:
    ///   - engine: Consolidation engine to run.
    ///   - countThreshold: Episodic count trigger threshold.
    ///   - insertionThreshold: Insertion count trigger threshold.
    ///   - similarityThreshold: Duplicate similarity threshold for scheduled runs.
    public init(
        engine: ConsolidationEngine,
        countThreshold: Int = 200,
        insertionThreshold: Int = 50,
        similarityThreshold: Float = 0.92
    ) {
        self.engine = engine
        self.countThreshold = countThreshold
        self.insertionThreshold = insertionThreshold
        self.similarityThreshold = similarityThreshold
    }

    /// Notifies scheduler that an insertion occurred and may trigger consolidation.
    ///
    /// - Parameters:
    ///   - episodicCount: Current episodic chunk count.
    ///   - session: Active session identifier.
    ///   - episodicStore: Episodic store.
    ///   - semanticStore: Semantic store.
    public func notifyInsertion(
        episodicCount: Int,
        session: UUID,
        episodicStore: any ConsolidationEpisodicStore,
        semanticStore: any ConsolidationSemanticStore
    ) async {
        insertionsSinceLastConsolidation += 1

        let shouldConsolidate = episodicCount > countThreshold || insertionsSinceLastConsolidation > insertionThreshold
        guard shouldConsolidate, !isConsolidating else {
            return
        }

        isConsolidating = true
        triggerCountValue += 1

        let engine = self.engine
        let threshold = self.similarityThreshold

        Task.detached(priority: .background) {
            do {
                let result = try await engine.consolidate(
                    session: session,
                    episodicStore: episodicStore,
                    semanticStore: semanticStore,
                    threshold: threshold
                )
                await self.finish(result: result)
            } catch {
                await self.finish(result: nil)
            }
        }
    }

    /// Number of consolidation triggers issued.
    public func triggerCount() -> Int {
        triggerCountValue
    }

    /// Indicates whether a background consolidation task is running.
    public func isRunning() -> Bool {
        isConsolidating
    }

    /// Latest successful consolidation result.
    public func lastResult() -> ConsolidationResult? {
        lastResultValue
    }

    private func finish(result: ConsolidationResult?) {
        if let result {
            lastResultValue = result
            resetCounter()
        }
        isConsolidating = false
    }

    private func resetCounter() {
        insertionsSinceLastConsolidation = 0
    }
}
