// SwarmEphemeralStoreBootstrap.swift
// SwarmTests
//
// Keeps auto-created default memories off the durable Application-Support
// store during integrations-lane test runs.

import Foundation
@testable import Swarm

/// Installs a process-wide ephemeral store root once per test process.
///
/// After T7 retired ambient test-runner sniffing, auto-created default memories
/// resolve to the durable Application-Support location unless an ephemeral
/// root is installed or an explicit URL is passed. Suites that exercise
/// default-memory writes declare
/// `private let _ephemeralDefaultStores = SwarmEphemeralStoreBootstrap.installOnce`
/// so their agents keep writing uniquely named throwaway stores under the
/// temporary directory.
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
