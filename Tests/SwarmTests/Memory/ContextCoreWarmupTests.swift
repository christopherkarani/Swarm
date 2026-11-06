#if SWARM_INTEGRATIONS && canImport(ContextCore)
// ContextCoreWarmupTests.swift
// SwarmTests
//
// The ContextCore engine's warmup embed is owned by the engine and cancelled
// when the engine is released.

import ContextCore
import Foundation
import Testing

@Suite("ContextCore warmup ownership")
struct ContextCoreWarmupTests {
    @Test("Releasing the engine cancels its in-flight warmup embed")
    func releasingEngineCancelsWarmup() async throws {
        let provider = WarmupProbeEmbeddingProvider()
        var configuration = ContextConfiguration.default
        configuration.embeddingProvider = provider

        var engine: ContextWindowEngine? = try ContextWindowEngine(configuration: configuration)
        await provider.waitUntilWarmupStarts()
        #expect(engine != nil)
        engine = nil

        #expect(await provider.warmupOutcome() == .cancelled)
    }
}

/// Embedding provider whose first embed parks for up to five seconds and
/// records whether it finished or was cancelled.
private actor WarmupProbeEmbeddingProvider: EmbeddingProvider {
    enum Outcome: Equatable {
        case finished
        case cancelled
    }

    nonisolated var dimensions: Int { 4 }

    private var started = false
    private var outcome: Outcome?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var outcomeWaiters: [CheckedContinuation<Outcome, Never>] = []

    func embed(_ text: String) async throws -> [Float] {
        if !started {
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            do {
                try await Task.sleep(for: .seconds(5))
                record(.finished)
            } catch {
                record(.cancelled)
                throw error
            }
        }
        return [0, 0, 0, 1]
    }

    func waitUntilWarmupStarts() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func warmupOutcome() async -> Outcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { outcomeWaiters.append($0) }
    }

    private func record(_ value: Outcome) {
        outcome = value
        outcomeWaiters.forEach { $0.resume(returning: value) }
        outcomeWaiters.removeAll()
    }
}
#endif
