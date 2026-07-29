import ContextCoreTypes
import Foundation
import Metal

/// GPU-backed relevance and recency scoring engine.
public actor ScoringEngine {
    package final class PreparedScoringInputs: @unchecked Sendable {
        fileprivate let queryBuffer: MTLBuffer
        fileprivate let chunksBuffer: MTLBuffer
        fileprivate let recencyBuffer: MTLBuffer
        fileprivate let outputBuffer: MTLBuffer
        fileprivate let count: Int
        fileprivate let dimension: Int
        fileprivate let queryNorm: Float

        fileprivate init(
            queryBuffer: MTLBuffer,
            chunksBuffer: MTLBuffer,
            recencyBuffer: MTLBuffer,
            outputBuffer: MTLBuffer,
            count: Int,
            dimension: Int,
            queryNorm: Float
        ) {
            self.queryBuffer = queryBuffer
            self.chunksBuffer = chunksBuffer
            self.recencyBuffer = recencyBuffer
            self.outputBuffer = outputBuffer
            self.count = count
            self.dimension = dimension
            self.queryNorm = queryNorm
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let relevancePipeline: MTLComputePipelineState
    private let recencyPipeline: MTLComputePipelineState
    private var scoringBuffers = ScoringBuffers()
    private var recencyBuffers = RecencyBuffers()

    private struct ScoringBuffers {
        var query: MTLBuffer?
        var chunks: MTLBuffer?
        var recency: MTLBuffer?
        var output: MTLBuffer?
    }

    private struct RecencyBuffers {
        var timestamps: MTLBuffer?
        var output: MTLBuffer?
    }

    /// Creates a scoring engine and compiles required Metal pipelines.
    ///
    /// - Parameter device: Optional Metal device override.
    /// - Throws: ``ContextCoreError/metalDeviceUnavailable`` or pipeline creation failures.
    public init(device: MTLDevice? = nil) throws {
        self.device = try device ?? MetalContext.device()
        self.commandQueue = try MetalContext.commandQueue(device: self.device)

        let library = try MetalContext.library(device: self.device)

        guard let relevanceFunction = library.makeFunction(name: "relevance_score") else {
            throw ContextCoreError.compressionFailed("Missing relevance_score function")
        }

        guard let recencyFunction = library.makeFunction(name: "compute_recency_weights") else {
            throw ContextCoreError.compressionFailed("Missing compute_recency_weights function")
        }

        self.relevancePipeline = try self.device.makeComputePipelineState(function: relevanceFunction)
        self.recencyPipeline = try self.device.makeComputePipelineState(function: recencyFunction)
    }

    /// Scores candidate chunks against a query vector.
    ///
    /// - Parameters:
    ///   - query: Query embedding.
    ///   - chunks: Candidate chunks.
    ///   - recencyWeights: Per-chunk recency weights.
    ///   - relevanceWeight: Similarity contribution.
    ///   - recencyWeight: Recency contribution.
    /// - Returns: Scored chunks sorted by descending score.
    /// - Throws: ``ContextCoreError/dimensionMismatch(expected:got:)`` for inconsistent dimensions.
    public func scoreChunks(
        query: [Float],
        chunks: [MemoryChunk],
        recencyWeights: [Float],
        relevanceWeight: Float = 0.7,
        recencyWeight: Float = 0.3
    ) async throws -> [(chunk: MemoryChunk, score: Float)] {
        let unsorted = try await scoreChunksUnsorted(
            query: query,
            chunks: chunks,
            recencyWeights: recencyWeights,
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )

        return unsorted.sorted(by: { $0.score > $1.score })
    }

    package func scoreChunksUnsorted(
        query: [Float],
        chunks: [MemoryChunk],
        recencyWeights: [Float],
        relevanceWeight: Float = 0.7,
        recencyWeight: Float = 0.3
    ) async throws -> [(chunk: MemoryChunk, score: Float)] {
        guard !chunks.isEmpty else {
            return []
        }
        guard chunks.count == recencyWeights.count else {
            throw ContextCoreError.dimensionMismatch(expected: chunks.count, got: recencyWeights.count)
        }

        let dim = query.count
        var flattened: [Float] = []
        flattened.reserveCapacity(chunks.count * dim)
        for chunk in chunks {
            guard chunk.embedding.count == dim else {
                throw ContextCoreError.dimensionMismatch(expected: dim, got: chunk.embedding.count)
            }
            flattened.append(contentsOf: chunk.embedding)
        }

        let scores = try await scoreFlattenedEmbeddings(
            query: query,
            flattenedEmbeddings: flattened,
            count: chunks.count,
            dimension: dim,
            recencyWeights: recencyWeights,
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )

        return zip(chunks, scores)
            .map { (chunk: $0.0, score: $0.1) }
    }

    /// Returns indices of top-k values from a score vector using GPU selection.
    ///
    /// - Parameters:
    ///   - scores: Score values.
    ///   - k: Number of indices to return.
    /// - Returns: Top-k score indices.
    /// - Throws: Buffer and command construction failures.
    public func topKIndices(
        scores: [Float],
        k: Int
    ) async throws -> [Int] {
        guard !scores.isEmpty, k > 0 else {
            return []
        }

        let cappedK = min(k, scores.count)
        return scores.enumerated()
            .sorted { lhs, rhs in
                if lhs.element == rhs.element {
                    return lhs.offset < rhs.offset
                }
                return lhs.element > rhs.element
            }
            .prefix(cappedK)
            .map(\.offset)
    }

    /// Computes exponential recency weights using a half-life decay function.
    ///
    /// - Parameters:
    ///   - timestamps: Source timestamps.
    ///   - halfLife: Half-life duration in seconds.
    ///   - currentTime: Reference time for decay calculation.
    /// - Returns: Recency weights in `[0, 1]`.
    /// - Throws: ``ContextCoreError/compressionFailed(_:)`` when `halfLife <= 0` or buffer setup fails.
    public func computeRecencyWeights(
        timestamps: [Date],
        halfLife: TimeInterval,
        currentTime: Date = .now
    ) async throws -> [Float] {
        guard !timestamps.isEmpty else {
            return []
        }
        guard halfLife > 0 else {
            throw ContextCoreError.compressionFailed("halfLife must be positive")
        }

        let timestampValues = timestamps.map { Float($0.timeIntervalSince1970) }
        let n = timestampValues.count
        let timestampBuffer = try reusableBuffer(
            current: &recencyBuffers.timestamps,
            minimumLength: timestampValues.count * MemoryLayout<Float>.stride,
            failureMessage: "Failed to allocate recency timestamp buffer"
        )
        let outputBuffer = try reusableBuffer(
            current: &recencyBuffers.output,
            minimumLength: n * MemoryLayout<Float>.stride,
            failureMessage: "Failed to allocate recency output buffer"
        )

        write(timestampValues, to: timestampBuffer)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate recency buffers")
        }

        var currentTimeSeconds = Float(currentTime.timeIntervalSince1970)
        var halfLifeF = Float(halfLife)
        var n32 = UInt32(n)

        encoder.setComputePipelineState(recencyPipeline)
        encoder.setBuffer(timestampBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBytes(&currentTimeSeconds, length: MemoryLayout<Float>.stride, index: 2)
        encoder.setBytes(&halfLifeF, length: MemoryLayout<Float>.stride, index: 3)
        encoder.setBytes(&n32, length: MemoryLayout<UInt32>.stride, index: 4)

        let threads = MetalContext.threadsPerThreadgroup(pipeline: recencyPipeline, count: n)
        let groups = MetalContext.threadgroups(threadsPerThreadgroup: threads, count: n)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()

        try await awaitCompletion(of: commandBuffer)

        let raw = outputBuffer.contents().bindMemory(to: Float.self, capacity: n)
        return Array(UnsafeBufferPointer(start: raw, count: n))
    }

    package func scoreFlattenedEmbeddings(
        query: [Float],
        flattenedEmbeddings: [Float],
        count: Int,
        dimension: Int,
        recencyWeights: [Float],
        relevanceWeight: Float,
        recencyWeight: Float
    ) async throws -> [Float] {
        guard count > 0 else {
            return []
        }
        guard query.count == dimension else {
            throw ContextCoreError.dimensionMismatch(expected: dimension, got: query.count)
        }
        guard flattenedEmbeddings.count == count * dimension else {
            throw ContextCoreError.dimensionMismatch(expected: count * dimension, got: flattenedEmbeddings.count)
        }
        guard recencyWeights.count == count else {
            throw ContextCoreError.dimensionMismatch(expected: count, got: recencyWeights.count)
        }

        return try await scoreEmbeddings(
            query: query,
            flattenedEmbeddings: flattenedEmbeddings,
            count: count,
            dimension: dimension,
            recencyWeights: recencyWeights,
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )
    }

    package func makePreparedScoringInputs(
        query: [Float],
        flattenedEmbeddings: [Float],
        count: Int,
        dimension: Int,
        recencyWeights: [Float]
    ) throws -> PreparedScoringInputs {
        guard count > 0 else {
            throw ContextCoreError.compressionFailed("Prepared scoring inputs require at least one chunk")
        }
        guard query.count == dimension else {
            throw ContextCoreError.dimensionMismatch(expected: dimension, got: query.count)
        }
        guard flattenedEmbeddings.count == count * dimension else {
            throw ContextCoreError.dimensionMismatch(expected: count * dimension, got: flattenedEmbeddings.count)
        }
        guard recencyWeights.count == count else {
            throw ContextCoreError.dimensionMismatch(expected: count, got: recencyWeights.count)
        }

        guard let queryBuffer = device.makeBuffer(length: query.count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let chunksBuffer = device.makeBuffer(length: flattenedEmbeddings.count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let recencyBuffer = device.makeBuffer(length: recencyWeights.count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let outputBuffer = device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate prepared scoring buffers")
        }

        write(query, to: queryBuffer)
        write(flattenedEmbeddings, to: chunksBuffer)
        write(recencyWeights, to: recencyBuffer)

        return PreparedScoringInputs(
            queryBuffer: queryBuffer,
            chunksBuffer: chunksBuffer,
            recencyBuffer: recencyBuffer,
            outputBuffer: outputBuffer,
            count: count,
            dimension: dimension,
            queryNorm: l2Norm(query)
        )
    }

    package func scorePreparedEmbeddings(
        _ prepared: PreparedScoringInputs,
        relevanceWeight: Float,
        recencyWeight: Float
    ) async throws -> [Float] {
        try await dispatchScore(
            queryBuffer: prepared.queryBuffer,
            chunksBuffer: prepared.chunksBuffer,
            recencyBuffer: prepared.recencyBuffer,
            outputBuffer: prepared.outputBuffer,
            count: prepared.count,
            dimension: prepared.dimension,
            queryNorm: prepared.queryNorm,
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )
    }

    private func scoreEmbeddings(
        query: [Float],
        flattenedEmbeddings: [Float],
        count: Int,
        dimension: Int,
        recencyWeights: [Float],
        relevanceWeight: Float,
        recencyWeight: Float
    ) async throws -> [Float] {
        let queryBuffer = try reusableBuffer(
            current: &scoringBuffers.query,
            minimumLength: query.count * MemoryLayout<Float>.stride,
            failureMessage: "Failed to allocate query buffer"
        )
        let chunksBuffer = try reusableBuffer(
            current: &scoringBuffers.chunks,
            minimumLength: flattenedEmbeddings.count * MemoryLayout<Float>.stride,
            failureMessage: "Failed to allocate chunk buffer"
        )
        let recencyBuffer = try reusableBuffer(
            current: &scoringBuffers.recency,
            minimumLength: recencyWeights.count * MemoryLayout<Float>.stride,
            failureMessage: "Failed to allocate recency buffer"
        )
        let outputBuffer = try reusableBuffer(
            current: &scoringBuffers.output,
            minimumLength: count * MemoryLayout<Float>.stride,
            failureMessage: "Failed to allocate scoring output buffer"
        )

        write(query, to: queryBuffer)
        write(flattenedEmbeddings, to: chunksBuffer)
        write(recencyWeights, to: recencyBuffer)

        return try await dispatchScore(
            queryBuffer: queryBuffer,
            chunksBuffer: chunksBuffer,
            recencyBuffer: recencyBuffer,
            outputBuffer: outputBuffer,
            count: count,
            dimension: dimension,
            queryNorm: l2Norm(query),
            relevanceWeight: relevanceWeight,
            recencyWeight: recencyWeight
        )
    }

    private func dispatchScore(
        queryBuffer: MTLBuffer,
        chunksBuffer: MTLBuffer,
        recencyBuffer: MTLBuffer,
        outputBuffer: MTLBuffer,
        count: Int,
        dimension: Int,
        queryNorm: Float,
        relevanceWeight: Float,
        recencyWeight: Float
    ) async throws -> [Float] {
        var weights = SIMD2<Float>(relevanceWeight, recencyWeight)
        var dim32 = UInt32(dimension)
        var n32 = UInt32(count)
        var queryNorm = queryNorm

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate scoring buffers")
        }

        encoder.setComputePipelineState(relevancePipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(chunksBuffer, offset: 0, index: 1)
        encoder.setBuffer(recencyBuffer, offset: 0, index: 2)
        encoder.setBytes(&weights, length: MemoryLayout<SIMD2<Float>>.stride, index: 3)
        encoder.setBuffer(outputBuffer, offset: 0, index: 4)
        encoder.setBytes(&dim32, length: MemoryLayout<UInt32>.stride, index: 5)
        encoder.setBytes(&n32, length: MemoryLayout<UInt32>.stride, index: 6)
        encoder.setBytes(&queryNorm, length: MemoryLayout<Float>.stride, index: 7)

        let threads = scoringThreadsPerThreadgroup(for: count)
        let groups = MetalContext.threadgroups(threadsPerThreadgroup: threads, count: count)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()

        try await awaitCompletion(of: commandBuffer)

        let raw = outputBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: raw, count: count))
    }

    private func scoringThreadsPerThreadgroup(for count: Int) -> MTLSize {
        let executionWidth = max(1, relevancePipeline.threadExecutionWidth)
        let preferredWidth = min(relevancePipeline.maxTotalThreadsPerThreadgroup, executionWidth * 4)
        let width = max(1, min(preferredWidth, count))
        return MTLSize(width: width, height: 1, depth: 1)
    }

    private func reusableBuffer(
        current: inout MTLBuffer?,
        minimumLength: Int,
        failureMessage: String
    ) throws -> MTLBuffer {
        if let current, current.length >= minimumLength {
            return current
        }

        guard let replacement = device.makeBuffer(length: minimumLength, options: .storageModeShared) else {
            throw ContextCoreError.compressionFailed(failureMessage)
        }
        current = replacement
        return replacement
    }

    private func write(_ values: [Float], to buffer: MTLBuffer) {
        values.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            memcpy(buffer.contents(), baseAddress, rawBuffer.count)
        }
    }

    private func l2Norm(_ vector: [Float]) -> Float {
        guard !vector.isEmpty else {
            return 0
        }

        var sum: Float = 0
        for value in vector {
            sum += value * value
        }
        return sum.squareRoot()
    }

    private func awaitCompletion(of commandBuffer: MTLCommandBuffer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: ContextCoreError.compressionFailed("Metal command failed: \(error.localizedDescription)"))
                    return
                }
                continuation.resume(returning: ())
            }
            commandBuffer.commit()
        }
    }
}
