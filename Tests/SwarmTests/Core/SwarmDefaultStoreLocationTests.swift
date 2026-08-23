#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

/// Serialized: the suite exercises the process-wide ephemeral-root override.
@Suite("Swarm Default Store Location", .serialized)
struct SwarmDefaultStoreLocationTests {
    private static func makeTestRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwarmDefaultStoreLocationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("durable default store URLs match the Application Support layout")
    func durableDefaultsMatchApplicationSupportLayout() {
        let waxURL = WaxMemory.makeDurableStoreURL()
        #expect(!waxURL.path.contains(FileManager.default.temporaryDirectory.path))
        #expect(waxURL.path.contains("Swarm/AgentMemory"))
        #expect(waxURL.lastPathComponent == "wax-memory.mv2s")

        let membraneURL = WaxMembraneStorage.makeDurableStoreURL()
        #expect(!membraneURL.path.contains(FileManager.default.temporaryDirectory.path))
        #expect(membraneURL.path.contains("Swarm/Membrane"))
        #expect(membraneURL.lastPathComponent == "membrane-store.mv2s")
    }

    @Test("ephemeral store URLs are unique and live under the given root")
    func ephemeralStoresAreUniqueAndRooted() {
        let root = Self.makeTestRoot()

        let firstWax = WaxMemory.makeEphemeralStoreURL(under: root)
        let secondWax = WaxMemory.makeEphemeralStoreURL(under: root)
        #expect(firstWax != secondWax)
        #expect(firstWax.deletingLastPathComponent().path.hasPrefix(root.path))

        let membrane = WaxMembraneStorage.makeEphemeralStoreURL(under: root)
        #expect(membrane.deletingLastPathComponent().path.hasPrefix(root.path))
    }

    @Test("installed ephemeral root redirects default stores under that root")
    func installedRootRedirectsDefaultStores() {
        let previousRoot = SwarmDefaultStoreLocation.installedEphemeralRoot
        let root = Self.makeTestRoot()
        SwarmDefaultStoreLocation.installEphemeralRoot(root)
        defer {
            if let previousRoot {
                SwarmDefaultStoreLocation.installEphemeralRoot(previousRoot)
            } else {
                SwarmDefaultStoreLocation.removeEphemeralRoot()
            }
        }

        #expect(WaxMemory.makeDefaultStoreURL().path.hasPrefix(root.path))
        #expect(WaxMembraneStorage.defaultStoreURL.path.hasPrefix(root.path))
    }

    @Test("makeDefaultMemory honors an explicit wax store URL")
    func makeDefaultMemoryHonorsExplicitStoreURL() throws {
        #if canImport(ContextCore)
        let memory = try Agent.makeDefaultMemory(waxStoreURL: Self.makeTestRoot().appendingPathComponent("explicit.mv2s"))
        #expect(memory is DefaultAgentMemory)
        #endif
    }
}
#endif
