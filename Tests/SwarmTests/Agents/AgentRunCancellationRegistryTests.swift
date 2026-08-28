// AgentRunCancellationRegistryTests.swift
// Swarm Framework
//
// Deterministic tests for per-run cancellation ownership: the keyed
// ``Agent/ActiveRunRegistry`` replaces the single-slot state so concurrent
// runs are individually tracked, `cancel()` reaches all of them, and a
// reserve-before-spawn gap cannot miss cancelAll.

import Foundation
import Testing
@_spi(ColonyInternal) @testable import Swarm

private final class CancelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var fires = 0

    var count: Int {
        lock.withLock { fires }
    }

    func fire() {
        lock.withLock { fires += 1 }
    }
}

private actor SignalingHangingProvider: InferenceProvider, MessagesFromPromptInference {
    let delay: Duration
    let entered: AsyncStream<Void>.Continuation

    init(delay: Duration, entered: AsyncStream<Void>.Continuation) {
        self.delay = delay
        self.entered = entered
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        entered.yield()
        try await Task.sleep(for: delay)
        return "Final Answer: delayed"
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let token = try await self.generate(prompt: prompt, options: options)
            continuation.yield(token)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools _: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        let content = try await generate(prompt: prompt, options: options)
        return InferenceResponse(content: content, finishReason: .completed)
    }
}

private final class ParkableGateOperation: @unchecked Sendable {
    private let entered: AsyncStream<Void>.Continuation?
    private let lock = NSLock()
    private var parked: CheckedContinuation<String, Error>?
    private var pendingRelease: Result<String, Error>?

    init(entered: AsyncStream<Void>.Continuation? = nil) {
        self.entered = entered
    }

    func release(_ result: Result<String, Error>) {
        lock.lock()
        if let continuation = parked {
            parked = nil
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        pendingRelease = result
        lock.unlock()
    }

    func run() async throws -> String {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let armed = pendingRelease {
                pendingRelease = nil
                lock.unlock()
                continuation.resume(with: armed)
                return
            }
            parked = continuation
            let signal = entered
            lock.unlock()
            signal?.yield()
        }
    }
}

private final class SettableClockForGateTests: SwarmClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [CheckedContinuation<Void, Error>] = []

    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func sleep(nanoseconds _: UInt64) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            sleepers.append(continuation)
            lock.unlock()
        }
    }

    func releaseAll() {
        lock.lock()
        let parked = sleepers
        sleepers.removeAll()
        lock.unlock()
        for continuation in parked {
            continuation.resume()
        }
    }
}

@Suite("ActiveRunRegistry Tests")
private struct ActiveRunRegistryTests {
    @Test("cancel(runID) fires only that run's canceller")
    func cancelTargetsSingleRun() async {
        let registry = Agent.ActiveRunRegistry()
        let first = CancelProbe()
        let second = CancelProbe()
        let firstID = UUID()
        let secondID = UUID()

        await registry.begin(firstID, onCancel: { first.fire() })
        await registry.begin(secondID, onCancel: { second.fire() })

        await registry.cancel(firstID)

        #expect(first.count == 1)
        #expect(second.count == 0)
    }

    @Test("finish removes exactly its own run; finished runs never shadow live ones")
    func finishRemovesOnlyItsOwnRun() async {
        let registry = Agent.ActiveRunRegistry()
        let first = CancelProbe()
        let second = CancelProbe()
        let firstID = UUID()
        let secondID = UUID()

        await registry.begin(firstID, onCancel: { first.fire() })
        await registry.begin(secondID, onCancel: { second.fire() })
        await registry.finish(firstID)

        #expect(await registry.trackedCount == 1)

        await registry.cancelAll()

        #expect(first.count == 0)
        #expect(second.count == 1)
    }

    @Test("cancelAll cancels every concurrently in-flight run")
    func cancelAllReachesEveryRun() async {
        let registry = Agent.ActiveRunRegistry()
        let probes = (CancelProbe(), CancelProbe(), CancelProbe())

        await registry.begin(UUID(), onCancel: { probes.0.fire() })
        await registry.begin(UUID(), onCancel: { probes.1.fire() })
        await registry.begin(UUID(), onCancel: { probes.2.fire() })

        await registry.cancelAll()

        #expect(probes.0.count == 1)
        #expect(probes.1.count == 1)
        #expect(probes.2.count == 1)
    }

    @Test("reserve then cancelAll fires attach immediately")
    func reserveThenCancelAllFiresAttach() async {
        let registry = Agent.ActiveRunRegistry()
        let probe = CancelProbe()
        let id = UUID()

        await registry.reserve(id)
        await registry.cancelAll()
        await registry.attach(id, onCancel: { probe.fire() })

        #expect(probe.count == 1)
        #expect(await registry.trackedCount == 0)
    }

    @Test("trackedCount reflects begin and finish transitions")
    func trackedCountTransitions() async {
        let registry = Agent.ActiveRunRegistry()

        let a = UUID()
        let b = UUID()
        await registry.begin(a, onCancel: {})
        await registry.begin(b, onCancel: {})
        #expect(await registry.trackedCount == 2)

        await registry.finish(a)
        #expect(await registry.trackedCount == 1)

        await registry.finish(b)
        #expect(await registry.trackedCount == 0)
    }
}

@Suite("Agent Cancel All Runs")
private struct AgentCancelAllRunsTests {
    @Test("agent.cancel() cancels two concurrently in-flight runs")
    func cancelReachesAllConcurrentRuns() async throws {
        let (enteredStream, entered) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
        let provider = SignalingHangingProvider(delay: .seconds(60), entered: entered)
        let agent = try Agent(
            tools: [],
            instructions: "Cancel-all test agent",
            inferenceProvider: provider
        )

        let first = Task {
            try await agent.run("first")
        }
        let second = Task {
            try await agent.run("second")
        }

        var entries = 0
        for await _ in enteredStream {
            entries += 1
            if entries == 2 { break }
        }
        #expect(entries == 2)

        await agent.cancel()

        let firstOutcome = await first.result
        let secondOutcome = await second.result

        for (label, outcome) in [("first", firstOutcome), ("second", secondOutcome)] {
            guard case let .failure(error as AgentError) = outcome else {
                Issue.record("\(label) run should fail after cancel(), got \(outcome)")
                continue
            }
            #expect(error == .cancelled, "\(label) run expected .cancelled, got \(error)")
        }
    }
}

@Suite("Owned Loop Gate Deactivation Parity")
private struct OwnedLoopGateDeactivationTests {
    @Test("gate deactivates when the timeout wins")
    func gateDeactivatesOnTimeout() async throws {
        let agent = try Agent(instructions: "Gate timeout agent", inferenceProvider: nil)
        let gate = ProviderOwnedLoopGate()
        let clock = VirtualClock(startingAtNanoseconds: 0)
        let operation = ParkableGateOperation()

        do {
            _ = try await agent.executeWithinRemainingTimeout(
                startTime: ContinuousClock.now,
                executionGate: gate,
                clock: clock
            ) {
                try await operation.run()
            }
            Issue.record("Timeout did not settle the race")
        } catch let error as AgentError {
            guard case .timeout = error else {
                Issue.record("Expected AgentError.timeout, got \(error)")
                return
            }
        }

        #expect(!gate.isActive)
        #expect(clock.sleepCount == 1)
        operation.release(.success("drain"))
    }

    @Test("gate stays armed when the operation succeeds")
    func gateStaysArmedOnSuccess() async throws {
        let agent = try Agent(instructions: "Gate success agent", inferenceProvider: nil)
        let gate = ProviderOwnedLoopGate()
        let clock = SettableClockForGateTests()
        defer { clock.releaseAll() }

        let value = try await agent.executeWithinRemainingTimeout(
            startTime: ContinuousClock.now,
            executionGate: gate,
            clock: clock
        ) {
            "done"
        }

        #expect(value == "done")
        #expect(gate.isActive)
    }

    @Test("gate stays armed on ordinary operation failure")
    func gateStaysArmedOnOperationFailure() async throws {
        let agent = try Agent(instructions: "Gate failure agent", inferenceProvider: nil)
        let gate = ProviderOwnedLoopGate()
        let clock = SettableClockForGateTests()
        defer { clock.releaseAll() }

        struct ToolExplosion: Error {}
        do {
            _ = try await agent.executeWithinRemainingTimeout(
                startTime: ContinuousClock.now,
                executionGate: gate,
                clock: clock
            ) {
                throw ToolExplosion()
            }
            Issue.record("Expected ToolExplosion to propagate")
        } catch is ToolExplosion {
        }

        #expect(gate.isActive)
    }

    @Test("already-expired remaining budget deactivates the gate")
    func expiredBudgetDeactivatesGate() async throws {
        let agent = try Agent(
            instructions: "Gate expired agent",
            configuration: AgentConfiguration.default.timeout(.milliseconds(1)),
            inferenceProvider: nil
        )
        let gate = ProviderOwnedLoopGate()
        let start = ContinuousClock.now - .seconds(1)

        do {
            _ = try await agent.executeWithinRemainingTimeout(
                startTime: start,
                executionGate: gate
            ) {
                "never"
            }
            Issue.record("Expected timeout")
        } catch let error as AgentError {
            guard case .timeout = error else {
                Issue.record("Expected timeout, got \(error)")
                return
            }
        }

        #expect(!gate.isActive)
    }
}
