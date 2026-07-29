public struct ModelArchitectureInfo: Sendable, Codable, Equatable {
    public let numLayers: Int
    public let numQueryHeads: Int
    public let numKVHeads: Int
    public let headDim: Int

    public init(
        numLayers: Int,
        numQueryHeads: Int,
        numKVHeads: Int,
        headDim: Int
    ) {
        self.numLayers = numLayers
        self.numQueryHeads = numQueryHeads
        self.numKVHeads = numKVHeads
        self.headDim = headDim
    }

    public var gqaRatio: Int {
        guard numKVHeads > 0 else {
            return 0
        }
        return numQueryHeads / numKVHeads
    }

    /// Approximate KV cache bytes per token for fp16 K/V:
    /// 2 (K+V) * layers * KV heads * head dimension * 2 bytes/fp16 scalar.
    public var kvBytesPerToken: Int {
        guard numLayers > 0, numKVHeads > 0, headDim > 0 else {
            return 0
        }
        return 2 * numLayers * numKVHeads * headDim * 2
    }
}
