// SwarmDefaultStoreLocation.swift
// Swarm Framework
//
// Explicit resolution of auto-created durable memory store locations,
// replacing the retired ambient test-runner sniffing.

import Foundation

#if SWARM_INTEGRATIONS
/// Explicit source for auto-created default memory store locations.
///
/// Production always resolves the durable Application-Support location,
/// byte-identical to the previous non-test behavior. Processes that need
/// throwaway stores (test runners) opt in once via ``installEphemeralRoot(_:)``
/// instead of being detected from their environment; individual call sites can
/// also pass fully explicit URLs.
enum SwarmDefaultStoreLocation {
    private static let lock = NSLock()

    // All accesses are synchronized through `lock`.
    private nonisolated(unsafe) static var ephemeralRootOverride: URL?

    /// Directs every auto-created default memory store under `root`, using
    /// uniquely named files so concurrent stores never collide.
    ///
    /// Intended for test bundles: call once at start-up and remove via
    /// ``removeEphemeralRoot()``.
    static func installEphemeralRoot(_ root: URL) {
        lock.lock()
        defer { lock.unlock() }
        ephemeralRootOverride = root
    }

    /// Removes a previously installed ephemeral root. Intended for testing only.
    static func removeEphemeralRoot() {
        lock.lock()
        defer { lock.unlock() }
        ephemeralRootOverride = nil
    }

    /// The installed ephemeral root, if any.
    static var installedEphemeralRoot: URL? {
        lock.lock()
        defer { lock.unlock() }
        return ephemeralRootOverride
    }
}
#endif
