// SwiftDataTestSupport.swift
// SwarmTests
//
// Shared sandbox gate and migration-test container factories.

#if canImport(SwiftData)
    import Foundation
    @testable import Swarm
    import SwiftData

    /// Whether SwiftData file-backed tests can run in this environment.
    ///
    /// CI sandboxes sometimes cannot write Application Support. Override with
    /// `SWARM_RUN_SWIFTDATA_TESTS=1` (force on) or `0` (force off).
    enum SwiftDataTestGate {
        static let canRun: Bool = {
            if let override = ProcessInfo.processInfo.environment["SWARM_RUN_SWIFTDATA_TESTS"] {
                return override == "1" || override.lowercased() == "true"
            }

            do {
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let probeDir = appSupport.appendingPathComponent("swarm_swiftdata_probe", isDirectory: true)
                try FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
                let probeFile = probeDir.appendingPathComponent("probe.tmp")
                try Data("probe".utf8).write(to: probeFile)
                try FileManager.default.removeItem(at: probeFile)
                return true
            } catch {
                return false
            }
        }()

        /// v1 schema, no migration plan — seeds a store that must reopen through
        /// ``MemoryMigrationPlan``.
        static func makeV1Container(url: URL) throws -> ModelContainer {
            let schema = Schema(versionedSchema: MemorySchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        /// Current schema with ``MemoryMigrationPlan``.
        static func makeMigratedContainer(url: URL) throws -> ModelContainer {
            let schema = Schema(versionedSchema: MemorySchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(
                for: schema,
                migrationPlan: MemoryMigrationPlan.self,
                configurations: [configuration]
            )
        }
    }
#endif
