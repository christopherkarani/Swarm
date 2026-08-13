// SwiftDataMemoryMigrationTests.swift
// SwarmTests
//
// v1 store → current migration-plan reopen, asserting messages survive.

#if canImport(SwiftData)
    import Foundation
    @testable import Swarm
    import SwiftData
    import Testing

    private enum SwiftDataTestGate {
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
    }

    @Suite("SwiftData memory schema migration")
    struct SwiftDataMemoryMigrationTests {
        @Test("v1 store reopened with MemoryMigrationPlan preserves messages")
        func v1StoreSurvivesCurrentMigrationPlan() async throws {
            if !SwiftDataTestGate.canRun { return }

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "swarm-swiftdata-migration-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let storeURL = directory.appendingPathComponent("memory.store")
            let conversationId = "migrate-v1"
            let seed = [
                MemoryMessage(
                    role: .user,
                    content: "alpha",
                    timestamp: Date(timeIntervalSince1970: 1)
                ),
                MemoryMessage(
                    role: .assistant,
                    content: "beta",
                    timestamp: Date(timeIntervalSince1970: 2)
                ),
            ]

            try seedV1Store(url: storeURL, conversationId: conversationId, messages: seed)

            let migrated = try PersistedMessage.makeMigratedContainer(url: storeURL)
            let memory = SwiftDataMemory(
                modelContainer: migrated,
                conversationId: conversationId
            )
            let recalled = await memory.allMessages()
            #expect(recalled.map(\.content) == ["alpha", "beta"])
            #expect(recalled.map(\.role) == [.user, .assistant])
        }

        @Test("pre-versioning Schema([PersistedMessage]) store reopens through the migration plan")
        func unversionedStoreSurvivesCurrentMigrationPlan() async throws {
            if !SwiftDataTestGate.canRun { return }

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "swarm-swiftdata-unversioned-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let storeURL = directory.appendingPathComponent("memory.store")
            let conversationId = "migrate-unversioned"
            let seed = [
                MemoryMessage(
                    role: .user,
                    content: "gamma",
                    timestamp: Date(timeIntervalSince1970: 1)
                ),
                MemoryMessage(
                    role: .assistant,
                    content: "delta",
                    timestamp: Date(timeIntervalSince1970: 2)
                ),
            ]

            try seedUnversionedStore(url: storeURL, conversationId: conversationId, messages: seed)

            let migrated = try PersistedMessage.makeMigratedContainer(url: storeURL)
            let memory = SwiftDataMemory(
                modelContainer: migrated,
                conversationId: conversationId
            )
            let recalled = await memory.allMessages()
            #expect(recalled.map(\.content) == ["gamma", "delta"])
        }

        @Test("MemorySchemaV1 is the current schema")
        func currentSchemaIsV1() {
            if !SwiftDataTestGate.canRun { return }
            #expect(MemorySchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
            #expect(MemoryMigrationPlan.schemas.count == 1)
            #expect(MemoryMigrationPlan.stages.isEmpty)
        }

        private func seedV1Store(
            url: URL,
            conversationId: String,
            messages: [MemoryMessage]
        ) throws {
            let container = try PersistedMessage.makeV1Container(url: url)
            let context = ModelContext(container)
            for message in messages {
                context.insert(PersistedMessage(from: message, conversationId: conversationId))
            }
            try context.save()
        }

        private func seedUnversionedStore(
            url: URL,
            conversationId: String,
            messages: [MemoryMessage]
        ) throws {
            let schema = Schema([PersistedMessage.self])
            let configuration = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            for message in messages {
                context.insert(PersistedMessage(from: message, conversationId: conversationId))
            }
            try context.save()
        }
    }
#endif
