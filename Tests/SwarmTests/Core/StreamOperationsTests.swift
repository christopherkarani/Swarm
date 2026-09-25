import Testing
@testable import Swarm

@Suite("StreamOperations")
struct StreamOperationsTests {
    @Test("retry stops immediately on cancellation")
    func retryStopsImmediatelyOnCancellation() async throws {
        let factory = RetryFactory()
        let stream = AsyncThrowingStream<AgentEvent, Error>.retry(maxAttempts: 3) {
            await factory.makeCancellableStream()
        }

        let task = Task {
            for try await _ in stream {}
        }

        await factory.waitUntilFactoryCalled()
        task.cancel()

        _ = await task.result
        try await Task.sleep(for: .milliseconds(50))
        #expect(await factory.callCount == 1)
    }

    @Test("retry does not swallow sleep cancellation")
    func retryDoesNotSwallowSleepCancellation() async throws {
        let factory = RetryFactory()
        let stream = AsyncThrowingStream<AgentEvent, Error>.retry(
            maxAttempts: 3,
            delay: .seconds(5)
        ) {
            await factory.makeFailingStream()
        }

        let task = Task {
            for try await _ in stream {}
        }

        await factory.waitUntilFactoryCalled()
        task.cancel()

        _ = await task.result
        try await Task.sleep(for: .milliseconds(50))
        #expect(await factory.callCount == 1)
    }

    @Test("retry rejects maxAttempts below 1 without invoking the factory")
    func retryRejectsInvalidMaxAttempts() async throws {
        for invalid in [0, -1, -5] {
            let factory = RetryFactory()
            let stream = AsyncThrowingStream<AgentEvent, Error>.retry(maxAttempts: invalid) {
                await factory.makeFailingStream()
            }
            await #expect(throws: ResilienceError.invalidMaxAttempts(invalid)) {
                for try await _ in stream {}
            }
            #expect(await factory.callCount == 0)
        }
    }

    @Test("retry counts total attempts including the initial attempt")
    func retryCountsTotalAttempts() async throws {
        let factory = RetryFactory()
        let stream = AsyncThrowingStream<AgentEvent, Error>.retry(maxAttempts: 2) {
            await factory.makeFailingStream()
        }
        await #expect(throws: TestStreamError.failure) {
            for try await _ in stream {}
        }
        #expect(await factory.callCount == 2)
    }

    @Test("retry with maxAttempts 1 runs the factory once")
    func retryWithSingleAttemptRunsOnce() async throws {
        let factory = RetryFactory()
        let stream = AsyncThrowingStream<AgentEvent, Error>.retry(maxAttempts: 1) {
            await factory.makeFailingStream()
        }
        await #expect(throws: TestStreamError.failure) {
            for try await _ in stream {}
        }
        #expect(await factory.callCount == 1)
    }

    @Test("timeout cancels upstream consumption when it fires")
    func timeoutCancelsUpstream() async throws {
        // Regression for the bug where `.timeout(after:)` finished the consumer-facing
        // continuation but left the upstream `processingTask` running. The fix
        // cancels `processingTask` from the timeout task, which drops the upstream
        // iterator and fires the upstream's `onTermination` — the signal observed
        // here. Without the fix, `onTermination` only fires once the upstream
        // *naturally* completes, which can be much later than the timeout.
        let observer = TerminationObserver()
        let upstream = AsyncThrowingStream<AgentEvent, Error> { continuation in
            continuation.onTermination = { @Sendable _ in
                Task { await observer.markTerminated() }
            }
            // A long-running producer that yields one token every 10ms forever.
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(.output(.token("t")))
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await observer.markTerminated() }
            }
        }

        let timeoutDuration = Duration.milliseconds(50)
        var thrown: Error?
        do {
            for try await _ in upstream.timeout(after: timeoutDuration) {}
        } catch {
            thrown = error
        }

        // 1. The consumer observes a timeout error.
        if let agentError = thrown as? AgentError, case .timeout = agentError {
            // expected
        } else {
            Issue.record("Expected AgentError.timeout, got \(String(describing: thrown))")
        }

        // 2. The upstream's onTermination fires within a bounded window after the
        //    timeout — proving the fix cancels the upstream rather than letting it
        //    run until natural completion.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while ContinuousClock.now < deadline {
            if await observer.terminated { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await observer.terminated, "upstream onTermination should fire after timeout")
    }
}

private actor TerminationObserver {
    private(set) var terminated = false
    func markTerminated() { terminated = true }
}

private actor RetryFactory {
    private(set) var callCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func makeCancellableStream() -> AsyncThrowingStream<AgentEvent, Error> {
        callCount += 1
        resumeWaiters()
        return AsyncThrowingStream { _ in }
    }

    func makeFailingStream() -> AsyncThrowingStream<AgentEvent, Error> {
        callCount += 1
        resumeWaiters()
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: TestStreamError.failure)
        }
    }

    func waitUntilFactoryCalled() async {
        if callCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private enum TestStreamError: Error, Equatable {
    case failure
}
