// MockVoiceActivityDetector.swift
// SwarmTests
//
// Scripted barge-in detector.

import Foundation
@testable import Swarm

/// Waits until ``triggerSpeechStarted()`` or ``stop()``.
public actor MockVoiceActivityDetector: VoiceActivityDetector {
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private var triggered = false
    private var stopped = false

    /// Creates a detector that stays quiet until triggered.
    public init() {}

    /// Signals ``VoiceActivityEvent/speechStarted`` to the active ``start()`` stream.
    public func triggerSpeechStarted() {
        if waiters.isEmpty {
            triggered = true
        } else {
            triggered = false
            resumeWaiters(true)
        }
    }

    public nonisolated func start() -> AsyncThrowingStream<VoiceActivityEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let shouldYield = await self.waitForTrigger()
            if shouldYield {
                continuation.yield(.speechStarted)
            }
            continuation.finish()
        }
    }

    public func stop() async {
        stopped = true
        resumeWaiters(false)
    }

    private func waitForTrigger() async -> Bool {
        if triggered {
            triggered = false
            return true
        }
        if stopped {
            return false
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func resumeWaiters(_ value: Bool) {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: value)
        }
    }
}
