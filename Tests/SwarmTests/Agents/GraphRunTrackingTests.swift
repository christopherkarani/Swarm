// GraphRunTrackingTests.swift
// Swarm Framework
//
// Deterministic tests for graph-run cancellation ownership: the keyed
// ``TrackedRunRegistry`` registers concurrent Hive runs without disturbing
// earlier ones. Keys are `HiveRunAttemptID` at the GraphAgent seam; tests
// use plain identifiers for the shared registry.

#if SWARM_INTEGRATIONS
import Foundation
import Testing
@testable import Swarm

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
    @Test("registering a new run leaves previously tracked runs untouched")
    func beginDoesNotCancelPreviousRun() async {
        let registry = TrackedRunRegistry<String>()
        let first = CancelProbe()
        let second = CancelProbe()

        await registry.begin("run-1", onCancel: { first.fire() })
        #expect(first.count == 0)

        await registry.begin("run-2", onCancel: { second.fire() })

        #expect(first.count == 0)
        #expect(second.count == 0)
        #expect(await registry.trackedCount == 2)

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
