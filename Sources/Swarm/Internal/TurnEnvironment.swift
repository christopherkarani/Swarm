// TurnEnvironment.swift
// Swarm
//
// Injectable clock & identity seam for domain value construction.
// Spec: spec-architecture-deterministic-turn-kernel.md (ticket T1).

import Foundation

/// Internal seam supplying wall-clock time and unique identifiers used when
/// constructing domain values (`AgentEvent`, transcript entries, tool results,
/// rate-limit windows).
///
/// Production code uses ``live``, which delegates to `Date()` and `UUID()`.
/// Tests inject deterministic fakes so two identical runs produce
/// byte-identical `id`/`timestamp` fields (spec AC-001).
///
/// The type is a struct of `@Sendable` closures, so it is `Sendable` without
/// any unchecked conformances (spec CON-002).
@usableFromInline
internal struct TurnEnvironment: Sendable {
    /// Returns the current instant.
    @usableFromInline
    let now: @Sendable () -> Date

    /// Returns a fresh unique identifier.
    @usableFromInline
    let newUUID: @Sendable () -> UUID

    /// The production environment: wall clock and random UUIDs.
    @usableFromInline
    static let live = TurnEnvironment(
        now: { Date() },
        newUUID: { UUID() }
    )

    /// Returns a fresh unique identifier as a string (UUID-shaped).
    @usableFromInline
    func newID() -> String {
        newUUID().uuidString
    }
}
