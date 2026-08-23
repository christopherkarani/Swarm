// SwarmEphemeralStoreBootstrap.swift
// SwarmTests
//
// Keeps auto-created default memories off the durable Application-Support
// store during integrations-lane test runs.

import Foundation
import Testing
@testable import Swarm

/// Installs a process-wide ephemeral store root once per test process.
///
/// After T7 retired ambient test-runner sniffing, auto-created default memories
/// resolve to the durable Application-Support location unless an ephemeral
/// root is installed or an explicit URL is passed.
enum SwarmEphemeralStoreBootstrap {
    /// Installs the ephemeral root on first touch; later touches are no-ops.
    static let installOnce: Void = {
        #if SWARM_INTEGRATIONS
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwarmDefaultMemoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        SwarmDefaultStoreLocation.installEphemeralRoot(root)
        #endif
    }()
}

/// Suite trait that touches ``SwarmEphemeralStoreBootstrap/installOnce``
/// before any of the suite's tests run.
struct EphemeralDefaultStoresTrait: SuiteTrait {
    func prepare(for test: Testing.Test) async throws {
        _ = SwarmEphemeralStoreBootstrap.installOnce
    }
}

extension SuiteTrait where Self == EphemeralDefaultStoresTrait {
    /// Opt-in marker routing auto-created default memories into uniquely named
    /// throwaway stores under the temporary directory instead of the durable
    /// Application-Support location.
    ///
    /// Add it to the suite attribute of any suite whose agents touch default
    /// memories: `@Suite("Name", .ephemeralDefaultStores)`.
    static var ephemeralDefaultStores: Self { Self() }
}
