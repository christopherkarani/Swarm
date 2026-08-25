// KeyedRunRegistry.swift
// Swarm Framework
//
// Shared keyed registry of in-flight runs. Consolidates the two W3-T1
// copies — ``Agent.ActiveRunRegistry`` and the graph runtime's
// `TrackedRunRegistry` — into one always-compiled implementation so their
// begin/finish/cancel semantics can no longer drift.

import Foundation

// MARK: - KeyedRunRegistry

/// Keyed registry of in-flight runs supporting concurrent registrations.
///
/// Ownership rules:
/// - ``begin(_:onCancel:)`` records a run without touching other entries;
///   registering a newer run must never cancel an older one.
/// - ``finish(_:)`` removes exactly one settled run, so finished runs never
///   shadow live ones.
/// - ``cancel(_:)`` fires exactly the named run's canceller.
/// - ``cancelAll()`` cancels every tracked run once and clears the registry.
///
/// Each entry stores the cancellation action for its run (typically the run
/// task's or outcome task's `cancel()`), so cancellation always targets
/// explicit handles rather than "the last registered" slot. Copies of the
/// owning value share one actor instance, keeping every concurrent run
/// reachable from a single cancel entry point.
///
/// Generic over the key: the agent facade keys by `UUID` run IDs while the
/// Hive bridge keys by `HiveRunID`; unit tests exercise identical semantics
/// with plain identifiers. Internal only — adds no public API surface.
actor KeyedRunRegistry<Key: Hashable & Sendable> {
    private var cancellers: [Key: @Sendable () -> Void] = [:]

    /// Records a run's cancellation action under `key` without disturbing
    /// other entries. Re-registering an existing key replaces its canceller
    /// without firing it.
    func begin(_ key: Key, onCancel: @escaping @Sendable () -> Void) {
        cancellers[key] = onCancel
    }

    /// Forgets one settled run without cancelling it.
    func finish(_ key: Key) {
        cancellers[key] = nil
    }

    /// Fires exactly the named run's canceller, leaving the entry registered.
    func cancel(_ key: Key) {
        cancellers[key]?()
    }

    /// Cancels every tracked run once and clears the registry.
    func cancelAll() {
        for cancel in cancellers.values {
            cancel()
        }
        cancellers.removeAll()
    }

    /// Number of runs currently tracked.
    var trackedCount: Int {
        cancellers.count
    }
}
