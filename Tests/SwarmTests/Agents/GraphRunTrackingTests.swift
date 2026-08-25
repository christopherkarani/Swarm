// GraphRunTrackingTests.swift
// Swarm Framework
//
// Deterministic tests for W3-T1 graph-run cancellation ownership: the keyed
// ``TrackedRunRegistry`` behind GraphAgent.CancellationController registers
// concurrent Hive runs without disturbing earlier ones and cancellation
// targets explicit runs instead of the most recent registration (AC-104).
// The registry is generic over its key precisely so unit tests can exercise
// the exact semantics used by the Hive bridge with plain identifiers.

// The registry lives in GraphAgent.swift, which only compiles when
// integration targets are enabled; gate identically so lean builds skip it.
#if SWARM_INTEGRATIONS
import Foundation
import Testing
@testable import Swarm

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

@Suite("TrackedRunRegistry Tests")
private struct TrackedRunRegistryTests {
    @Test("registering a new run leaves previously tracked runs untouched (AC-104)")
    func beginDoesNotCancelPreviousRun() async {
        let registry = TrackedRunRegistry<String>()
        let first = CancelProbe()
        let second = CancelProbe()

        await registry.begin("run-1", onCancel: { first.fire() })
        #expect(first.count == 0)

        // Regression guard: the single-slot controller this registry replaces
        // cancelled the previous handle right here.
        await registry.begin("run-2", onCancel: { second.fire() })

        #expect(first.count == 0)
        #expect(second.count == 0)
        #expect(await registry.trackedCount == 2)

        // Both runs remain individually cancellable.
        await registry.cancelAll()
        #expect(first.count == 1)
        #expect(second.count == 1)
    }

    @Test("finish removes one settled run without cancelling anything")
    func finishRemovesWithoutCancelling() async {
        let registry = TrackedRunRegistry<String>()
        let first = CancelProbe()
        let second = CancelProbe()

        await registry.begin("run-1", onCancel: { first.fire() })
        await registry.begin("run-2", onCancel: { second.fire() })

        await registry.finish("run-1")

        #expect(first.count == 0)
        #expect(second.count == 0)
        #expect(await registry.trackedCount == 1)

        await registry.cancelAll()
        #expect(first.count == 0)
        #expect(second.count == 1)
    }

    @Test("cancelAll cancels every tracked run exactly once")
    func cancelAllFiresEveryCancellerOnce() async {
        let registry = TrackedRunRegistry<String>()
        let first = CancelProbe()
        let second = CancelProbe()
        let third = CancelProbe()

        await registry.begin("run-1", onCancel: { first.fire() })
        await registry.begin("run-2", onCancel: { second.fire() })
        await registry.begin("run-3", onCancel: { third.fire() })

        await registry.cancelAll()

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(third.count == 1)
        #expect(await registry.trackedCount == 0)

        // A second cancel is idempotent: entries were cleared.
        await registry.cancelAll()
        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(third.count == 1)
    }

    @Test("re-registering a finished run ID tracks the new canceller")
    func reBeginAfterFinishTracksReplacement() async {
        let registry = TrackedRunRegistry<String>()
        let original = CancelProbe()
        let replacement = CancelProbe()

        await registry.begin("run-1", onCancel: { original.fire() })
        await registry.finish("run-1")
        await registry.begin("run-1", onCancel: { replacement.fire() })

        await registry.cancelAll()

        #expect(original.count == 0)
        #expect(replacement.count == 1)
    }
}

#endif
