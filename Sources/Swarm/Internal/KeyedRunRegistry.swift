// KeyedRunRegistry.swift
// Swarm Framework
//
// Shared keyed registry of in-flight runs. One always-compiled
// implementation so Agent and GraphAgent cannot drift on
// begin/finish/cancel semantics.

import Foundation

/// Keyed registry of in-flight runs supporting concurrent registrations.
///
/// Ownership rules:
/// - ``reserve(_:)`` then ``attach(_:onCancel:)`` records a run without
///   touching other entries. A concurrent ``cancelAll()`` between those
///   calls cannot miss the reserved key: attach fires immediately.
/// - ``begin(_:onCancel:)`` is reserve+attach for callers that already
///   hold the canceller.
/// - ``finish(_:)`` removes exactly one settled run, so finished runs never
///   shadow live ones.
/// - ``cancel(_:)`` fires exactly the named run's canceller.
/// - ``cancelAll()`` cancels every tracked run once and clears the registry.
///
/// Generic over the key: the agent facade keys by `UUID` run IDs while the
/// Hive bridge keys by `HiveRunAttemptID`. Internal only — no public API.
actor KeyedRunRegistry<Key: Hashable & Sendable> {
    private enum Slot {
        case reserved
        case attached(@Sendable () -> Void)
    }

    private var slots: [Key: Slot] = [:]
    /// Keys cancelled while reserved (or cancelled before attach), so a later
    /// attach fires immediately instead of registering a live run.
    private var pendingCancel: Set<Key> = []

    /// Occupies `key` so ``cancelAll()`` cannot race past an in-flight start.
    func reserve(_ key: Key) {
        guard !pendingCancel.contains(key) else { return }
        slots[key] = .reserved
    }

    /// Attaches the canceller, or fires it immediately if the key was
    /// cancelled while reserved.
    func attach(_ key: Key, onCancel: @escaping @Sendable () -> Void) {
        if pendingCancel.remove(key) != nil {
            slots[key] = nil
            onCancel()
            return
        }
        slots[key] = .attached(onCancel)
    }

    /// Records a run's cancellation action under `key` without disturbing
    /// other entries. Re-registering an existing key replaces its canceller
    /// without firing it.
    func begin(_ key: Key, onCancel: @escaping @Sendable () -> Void) {
        reserve(key)
        attach(key, onCancel: onCancel)
    }

    /// Forgets one settled run without cancelling it.
    func finish(_ key: Key) {
        slots[key] = nil
        pendingCancel.remove(key)
    }

    /// Fires exactly the named run's canceller, leaving an attached entry
    /// registered until ``finish(_:)``.
    func cancel(_ key: Key) {
        switch slots[key] {
        case let .attached(onCancel):
            onCancel()
        case .reserved, nil:
            pendingCancel.insert(key)
        }
    }

    /// Cancels every tracked run once and clears the registry.
    func cancelAll() {
        let snapshot = slots
        slots.removeAll()
        for (key, slot) in snapshot {
            switch slot {
            case let .attached(onCancel):
                onCancel()
            case .reserved:
                pendingCancel.insert(key)
            }
        }
    }

    /// Number of runs currently tracked.
    var trackedCount: Int {
        slots.count
    }
}
