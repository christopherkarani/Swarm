#if SWARM_INTEGRATIONS && canImport(ContextCoreTypes)
import ContextCoreTypes
import Foundation
import Testing

@Suite("Portable embedding providers")
struct PortableEmbeddingTests {
    @Test("deterministic provider is stable, sized, and normalized")
    func deterministicProviderBasics() async throws {
        let provider = DeterministicHashEmbeddingProvider(dimensions: 8)
        #expect(provider.modelIdentifier == "hash-fallback-v1")
        #expect(provider.modelID == .hashFallback)

        let first = await provider.embed("hello")
        let second = await provider.embed("hello")
        #expect(first == second)
        #expect(first.count == 8)
        let norm = first.reduce(Float.zero) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1.0) < 1e-5)

        let other = await provider.embed("goodbye")
        #expect(other != first)
        #expect(other.count == 8)

        let batch = await provider.embed(["hello", "goodbye"])
        #expect(batch == [first, other])
    }

    @Test("deterministic provider handles empty input")
    func deterministicProviderEmptyInput() async throws {
        let provider = DeterministicHashEmbeddingProvider(dimensions: 4)
        let vector = await provider.embed("")
        #expect(vector.count == 4)
        #expect(vector == (await provider.embed("")))
    }

    @Test("closure provider returns injected vectors")
    func closureProviderInjectsCompute() async throws {
        let provider = ClosureEmbeddingProvider(dimensions: 2, modelID: .remote("test")) { texts in
            texts.map { _ in [0.6, 0.8] }
        }
        #expect(provider.modelIdentifier == "remote:test")
        let vectors = try await provider.embed(["a", "b"])
        #expect(vectors == [[0.6, 0.8], [0.6, 0.8]])
        #expect(try await provider.embed([]) == [])
    }

    @Test("closure provider validates handler output")
    func closureProviderValidatesOutput() async throws {
        let badWidth = ClosureEmbeddingProvider(dimensions: 2) { _ in [[1, 2, 3]] }
        await #expect(throws: PortableEmbeddingError.invalidDimensions(expected: 2, got: 3)) {
            try await badWidth.embed("a")
        }

        let badCount = ClosureEmbeddingProvider(dimensions: 2) { _ in [[1, 2]] }
        await #expect(throws: PortableEmbeddingError.batchCountMismatch(expected: 2, got: 1)) {
            try await badCount.embed(["a", "b"])
        }

        struct Boom: Error {}
        let failing = ClosureEmbeddingProvider(dimensions: 2, handler: { _ in throw Boom() })
        await #expect(throws: PortableEmbeddingError.self) {
            try await failing.embed("a")
        }
    }

    @Test("composite provider prefers primary and falls back on failure")
    func compositePrimaryAndFallback() async throws {
        struct Boom: Error {}
        let primary = ClosureEmbeddingProvider(dimensions: 2, modelID: "primary") { texts in
            if texts == ["fail"] {
                throw Boom()
            }
            return texts.map { _ in [1, 0] }
        }
        let composite = CompositeEmbeddingProvider(primary: primary)
        #expect(composite.dimensions == 2)
        #expect(composite.modelIdentifier == "primary")

        #expect(try await composite.embed("ok") == [1, 0])

        let fallbackVector = try await composite.embed("fail")
        #expect(fallbackVector.count == 2)
        let expected = await DeterministicHashEmbeddingProvider(dimensions: 2).embed("fail")
        #expect(fallbackVector == expected)
    }

    @Test("caching provider serves repeats without calling base")
    func cachingProviderCaches() async throws {
        let counter = CallCounter()
        let base = ClosureEmbeddingProvider(dimensions: 2, modelID: "counted") { texts in
            await counter.increment(by: texts.count)
            return texts.map { _ in [1, 0] }
        }
        let caching = PortableCachingEmbeddingProvider(base: base)
        #expect(caching.dimensions == 2)
        #expect(caching.modelIdentifier == "counted")

        _ = try await caching.embed("a")
        _ = try await caching.embed("a")
        _ = try await caching.embed(["a", "b"])
        #expect(await counter.count == 2)
        #expect(await caching.count == 2)
    }

    @Test("caching provider snapshot restores onto a fresh instance")
    func cachingSnapshotRestoreRoundTrip() async throws {
        let base = DeterministicHashEmbeddingProvider(dimensions: 4, modelID: "snap")
        let caching = PortableCachingEmbeddingProvider(base: base)
        let vector = try await caching.embed("hello")

        let snapshot = await caching.snapshot()
        #expect(snapshot.modelID == "snap")
        #expect(snapshot.dimensions == 4)
        #expect(snapshot.entries.map(\.key) == ["hello"])

        let decoded = try JSONDecoder().decode(EmbeddingCacheSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)

        let counter = CallCounter()
        let countingBase = ClosureEmbeddingProvider(dimensions: 4, modelID: "snap") { texts in
            await counter.increment(by: texts.count)
            return texts.map { _ in [Float](repeating: 0, count: 4) }
        }
        let revived = PortableCachingEmbeddingProvider(base: countingBase)
        try await revived.restore(snapshot)
        #expect(await revived.count == 1)
        #expect(try await revived.embed("hello") == vector)
        #expect(await counter.count == 0)
    }

    @Test("caching restore rejects foreign snapshots")
    func cachingRestoreRejectsMismatch() async throws {
        let caching = PortableCachingEmbeddingProvider(
            base: DeterministicHashEmbeddingProvider(dimensions: 2, modelID: "a")
        )
        let wrongModel = EmbeddingCacheSnapshot(modelID: "b", dimensions: 2, entries: [])
        await #expect(throws: PortableEmbeddingError.self) {
            try await caching.restore(wrongModel)
        }
        let wrongDims = EmbeddingCacheSnapshot(modelID: "a", dimensions: 3, entries: [])
        await #expect(throws: PortableEmbeddingError.self) {
            try await caching.restore(wrongDims)
        }
    }

    @Test("caching provider evicts oldest entries past capacity")
    func cachingEvictsFIFO() async throws {
        let counter = CallCounter()
        let base = ClosureEmbeddingProvider(dimensions: 1, modelID: "fifo") { texts in
            await counter.increment(by: texts.count)
            return texts.map { _ in [1] }
        }
        let caching = PortableCachingEmbeddingProvider(base: base, capacity: 1)
        _ = try await caching.embed("a")
        _ = try await caching.embed("b")
        #expect(await caching.count == 1)
        _ = try await caching.embed("a")
        #expect(await counter.count == 3)
    }
}

private actor CallCounter {
    private(set) var count = 0

    func increment(by amount: Int) {
        count += amount
    }
}
#endif
