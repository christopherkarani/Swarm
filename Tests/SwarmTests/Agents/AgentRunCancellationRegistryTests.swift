// AgentRunCancellationRegistryTests.swift
// Swarm Framework
//
// Deterministic tests for W3-T1 cancellation ownership: the per-run
// ``Agent/ActiveRunRegistry`` replaces the single-slot state so concurrent
// runs are individually tracked, `cancel()` reaches all of them (AC-103),
// finishing one run never shadows another, and owned-loop gates deactivate
// on exactly the same outcomes as before the settlement-primitive
// consolidation (REQ-003).

import Foundation
import Testing
@_spi(ColonyInternal) @testable import Swarm

// MARK: - Test Helpers

/// Counts cancellation firings behind a lock.
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

/// Inference provider that signals each `generate` entry into an async
/// stream and then hangs for `delay`, so tests synchronize on actual run
/// progress instead of sleeping.
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

/// Operation body that parks on a manually released continuation. A body
/// whose task was already cancelled refuses to park, so draining a losing
/// operation after settlement can never strand a late-arriving parker; if
/// ``release(_:)`` runs before the body parks, the release is armed instead.
private final class ParkableGateOperation: @unchecked Sendable {
    private let entered: AsyncStream<Void>.Continuation?
    private let lock = NSLock()
    private var parked: CheckedContinuation<String, Error>?
    private var pendingRelease: Result<String, Error>?

    init(entered: AsyncStream<Void>.Continuation? = nil) {
        self.entered = entered
    }

    /// Resumes the parked body (or arms the release if not yet parked).
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
            // Yield only after the continuation is installed so an observer of
            // the event can rely on the body being parked.
            signal?.yield()
        }
    }
}

/// Clock whose sleep parks until explicitly released. A worker already
/// cancelled before sleeping refuses to park (it throws), so cleanup cannot
/// strand a late-arriving sleeper.
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

    /// Wakes every parked sleep, returning normally from each.
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

/// Awaits a task result with a watchdog bound so regressions surface as fast
/// failures instead of hangs; the bound never decides a passing outcome.
private func boundedResult<T: Sendable>(
    of task: Task<T, Error>,
    timeout: Duration
) async -> Result<T, Error>? {
    await withTaskGroup(of: Result<T, Error>?.self) { group in
        group.addTask {
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: - Registry Unit Tests

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

        // The finished run's canceller must never fire again...
        #expect(first.count == 0)
        // ...while the live run is still reachable.
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

    @Test("re-registering an ID replaces its canceller without firing it")
    func reBeginReplacesSilently() async {
        let registry = Agent.ActiveRunRegistry()
        let original = CancelProbe()
        let replacement = CancelProbe()
        let id = UUID()

        await registry.begin(id, onCancel: { original.fire() })
        await registry.begin(id, onCancel: { replacement.fire() })

        await registry.cancelAll()

        #expect(original.count == 0)
        #expect(replacement.count == 1)
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

// MARK: - Agent-Level Cancel All (AC-103)

@Suite("Agent Cancel All Runs")
private struct AgentCancelAllRunsTests {
    @Test("agent.cancel() cancels two concurrently in-flight runs (AC-103)")
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

        // Event-driven readiness: once both runs entered inference they are
        // both registered in the per-run registry.
        var entries = 0
        for await _ in enteredStream {
            entries += 1
            if entries == 2 { break }
        }
        #expect(entries == 2)

        await agent.cancel()

        guard let firstOutcome = await boundedResult(of: first, timeout: .seconds(2)) else {
            first.cancel()
            second.cancel()
            Issue.record("First run did not settle promptly after agent.cancel()")
            return
        }
        guard let secondOutcome = await boundedResult(of: second, timeout: .seconds(2)) else {
            second.cancel()
            Issue.record("Second run did not settle promptly after agent.cancel()")
            return
        }

        for (label, outcome) in [("first", firstOutcome), ("second", secondOutcome)] {
            guard case let .failure(error as AgentError) = outcome else {
                Issue.record("\(label) run should fail after cancel(), got \(outcome)")
                continue
            }
            #expect(error == .cancelled, "\(label) run expected .cancelled, got \(error)")
        }
    }
}

// MARK: - Owned Loop Gate Deactivation Parity (REQ-003)

@Suite("Owned Loop Gate Deactivation Parity")
private struct OwnedLoopGateDeactivationTests {
    @Test("gate deactivates when the timeout wins")
    func gateDeactivatesOnTimeout() async throws {
        let agent = try Agent(instructions: "Gate timeout agent", inferenceProvider: nil)
        let gate = ProviderOwnedLoopGate()
        // Instant-return fake clock: only the timer side can settle this
        // race because the operation parks on an unreleased continuation.
        let clock = VirtualClock(startingAtNanoseconds: 0)
        let operation = ParkableGateOperation()

        let work = Task<String, Error> {
            try await agent.executeWithinRemainingTimeout(
                startTime: ContinuousClock.now,
                executionGate: gate,
                clock: clock
            ) {
                try await operation.run()
            }
        }

        guard case let .failure(error)? = await boundedResult(of: work, timeout: .seconds(2)) else {
            work.cancel()
            operation.release(.success("drain"))
            Issue.record("Timeout did not settle the race promptly")
            return
        }
        guard case .timeout = error as? AgentError else {
            operation.release(.success("drain"))
            work.cancel()
            Issue.record("Expected AgentError.timeout, got \(error)")
            return
        }
        #expect(!gate.isActive)
        // REQ-006 pin at the agent seam: the timer suspension went through
        // the injected SwarmClock, not a raw Task.sleep.
        #expect(clock.sleepCount == 1)

        operation.release(.success("drain"))
        work.cancel()
    }

    @Test("gate stays armed when the operation succeeds")
    func gateStaysArmedOnSuccess() async throws {
        let agent = try Agent(instructions: "Gate success agent", inferenceProvider: nil)
        let gate = ProviderOwnedLoopGate()
        let clock = SettableClockForGateTests()
        // Timer stays parked until cleanup: the operation wins the race.
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
            // Expected winner.
        }

        #expect(gate.isActive)
    }

    @Test("gate deactivates when the parent task is cancelled")
    func gateDeactivatesOnParentCancellation() async throws {
        let agent = try Agent(instructions: "Gate cancel agent", inferenceProvider: nil)
        let gate = ProviderOwnedLoopGate()
        let clock = SettableClockForGateTests()
        let (enteredStream, entered) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
        let operation = ParkableGateOperation(entered: entered)

        let work = Task<String, Error> {
            try await agent.executeWithinRemainingTimeout(
                startTime: ContinuousClock.now,
                executionGate: gate,
                clock: clock
            ) {
                try await operation.run()
            }
        }

        // Wait until the race is fully installed and the operation parked, so
        // cancellation settles through the race's cancellation handler exactly
        // like an in-flight run (pre-install cancellation exits at
        // Task.checkCancellation before any gate exists — same as before the
        // consolidation).
        _ = await enteredStream.first(where: { _ in true })
        work.cancel()

        guard case let .failure(error)? = await boundedResult(of: work, timeout: .seconds(2)) else {
            work.cancel()
            operation.release(.success("drain"))
            clock.releaseAll()
            Issue.record("Parent cancellation did not settle the race promptly")
            return
        }
        guard error is CancellationError else {
            operation.release(.success("drain"))
            clock.releaseAll()
            Issue.record("Expected raw CancellationError, got \(error)")
            return
        }
        #expect(!gate.isActive)

        operation.release(.success("drain"))
        clock.releaseAll()
    }
}
