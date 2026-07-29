import ContextCoreTypes
import Foundation
import Metal

/// GPU-backed attention centrality and eviction scoring engine.
public actor AttentionEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let centralityPipeline: MTLComputePipelineState
    private let crossAttentionPipeline: MTLComputePipelineState

    /// Creates an attention engine and compiles required Metal pipelines.
    ///
    /// - Parameter device: Optional Metal device override.
    /// - Throws: ``ContextCoreError/metalDeviceUnavailable`` or pipeline creation failures.
    public init(device: MTLDevice? = nil) throws {
        self.device = try device ?? MetalContext.device()
        self.commandQueue = try MetalContext.commandQueue(device: self.device)

        let library = try MetalContext.library(device: self.device)

        guard let centralityFunction = library.makeFunction(name: "token_centrality") else {
            throw ContextCoreError.compressionFailed("Missing token_centrality function")
        }

        guard let crossAttentionFunction = library.makeFunction(name: "cross_attention_score") else {
            throw ContextCoreError.compressionFailed("Missing cross_attention_score function")
        }

        self.centralityPipeline = try self.device.makeComputePipelineState(function: centralityFunction)
        self.crossAttentionPipeline = try self.device.makeComputePipelineState(function: crossAttentionFunction)
    }

    /// Computes centrality for each embedding within a candidate set.
    ///
    /// - Parameter embeddings: Candidate embeddings.
    /// - Returns: Centrality score for each embedding.
    /// - Throws: ``ContextCoreError/dimensionMismatch(expected:got:)`` for inconsistent dimensions.
    public func computeCentrality(
        embeddings: [[Float]]
    ) async throws -> [Float] {
        guard !embeddings.isEmpty else {
            return []
        }

        let n = embeddings.count
        if n == 1 {
            return [0]
        }

        let dim = embeddings[0].count
        guard embeddings.allSatisfy({ $0.count == dim }) else {
            throw ContextCoreError.dimensionMismatch(expected: dim, got: embeddings.first(where: { $0.count != dim })?.count ?? 0)
        }

        let flattened = embeddings.flatMap { $0 }
        var output = [Float](repeating: 0, count: n)

        guard let embeddingsBuffer = device.makeBuffer(from: flattened),
              let outputBuffer = device.makeBuffer(from: output),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate centrality buffers")
        }

        var dim32 = UInt32(dim)
        var n32 = UInt32(n)

        guard let dimBuffer = device.makeBuffer(bytes: &dim32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let nBuffer = device.makeBuffer(bytes: &n32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to create centrality constants")
        }

        encoder.setComputePipelineState(centralityPipeline)
        encoder.setBuffer(embeddingsBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(dimBuffer, offset: 0, index: 2)
        encoder.setBuffer(nBuffer, offset: 0, index: 3)

        let threadWidth = max(1, min(16, min(centralityPipeline.maxTotalThreadsPerThreadgroup, n)))
        let threads = MTLSize(width: threadWidth, height: 1, depth: 1)
        let groups = MetalContext.threadgroups(threadsPerThreadgroup: threads, count: n)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()

        try await MetalContext.awaitCompletion(of: commandBuffer)

        let raw = outputBuffer.contents().bindMemory(to: Float.self, capacity: n)
        output = Array(UnsafeBufferPointer(start: raw, count: n))
        return output
    }

    /// Produces eviction scores by combining relevance and centrality.
    ///
    /// - Parameters:
    ///   - taskQuery: Query embedding.
    ///   - windowChunks: Candidate chunks already in the window.
    ///   - relevanceWeight: Relevance contribution.
    ///   - centralityWeight: Centrality contribution.
    /// - Returns: Chunks sorted by ascending eviction score (lowest first).
    /// - Throws: ``ContextCoreError/dimensionMismatch(expected:got:)`` for inconsistent dimensions.
    public func scoreWindowForEviction(
        taskQuery: [Float],
        windowChunks: [MemoryChunk],
        relevanceWeight: Float = 0.6,
        centralityWeight: Float = 0.4
    ) async throws -> [(chunk: MemoryChunk, evictionScore: Float)] {
        guard !windowChunks.isEmpty else {
            return []
        }

        let embeddings = windowChunks.map(\.embedding)
        let dim = taskQuery.count
        guard embeddings.allSatisfy({ $0.count == dim }) else {
            throw ContextCoreError.dimensionMismatch(expected: dim, got: embeddings.first(where: { $0.count != dim })?.count ?? 0)
        }

        let centralityScores = try await computeCentrality(embeddings: embeddings)
        let eviction = try await crossAttentionScores(
            query: taskQuery,
            embeddings: embeddings,
            centrality: centralityScores,
            relevanceWeight: relevanceWeight,
            centralityWeight: centralityWeight
        )

        return zip(windowChunks, eviction)
            .map { (chunk: $0.0, evictionScore: $0.1) }
            .sorted(by: { $0.evictionScore < $1.evictionScore })
    }

    private func crossAttentionScores(
        query: [Float],
        embeddings: [[Float]],
        centrality: [Float],
        relevanceWeight: Float,
        centralityWeight: Float
    ) async throws -> [Float] {
        let n = embeddings.count
        let dim = query.count
        let flattened = embeddings.flatMap { $0 }
        var output = [Float](repeating: 0, count: n)
        var weights = SIMD2<Float>(relevanceWeight, centralityWeight)

        guard let queryBuffer = device.makeBuffer(from: query),
              let embeddingsBuffer = device.makeBuffer(from: flattened),
              let centralityBuffer = device.makeBuffer(from: centrality),
              let weightsBuffer = device.makeBuffer(bytes: &weights, length: MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
              let outputBuffer = device.makeBuffer(from: output),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw ContextCoreError.compressionFailed("Failed to allocate cross-attention buffers")
        }

        var dim32 = UInt32(dim)
        var n32 = UInt32(n)

        guard let dimBuffer = device.makeBuffer(bytes: &dim32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let nBuffer = device.makeBuffer(bytes: &n32, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else {
            throw ContextCoreError.compressionFailed("Failed to create cross-attention constants")
        }

        encoder.setComputePipelineState(crossAttentionPipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(embeddingsBuffer, offset: 0, index: 1)
        encoder.setBuffer(centralityBuffer, offset: 0, index: 2)
        encoder.setBuffer(weightsBuffer, offset: 0, index: 3)
        encoder.setBuffer(outputBuffer, offset: 0, index: 4)
        encoder.setBuffer(dimBuffer, offset: 0, index: 5)
        encoder.setBuffer(nBuffer, offset: 0, index: 6)

        let threads = MetalContext.threadsPerThreadgroup(pipeline: crossAttentionPipeline, count: n)
        let groups = MetalContext.threadgroups(threadsPerThreadgroup: threads, count: n)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()

        try await MetalContext.awaitCompletion(of: commandBuffer)

        let raw = outputBuffer.contents().bindMemory(to: Float.self, capacity: n)
        output = Array(UnsafeBufferPointer(start: raw, count: n))
        return output
    }
}
