#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

@Suite("WebSearchTool mode/detail validation")
struct WebSearchToolModesTests {
    @Test("Unknown mode throws invalidToolArguments without reaching the runtime")
    func unknownModeThrowsBeforeRuntime() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        await #expect(throws: AgentError.invalidToolArguments(
            toolName: "websearch",
            reason: "unknown websearch mode 'serach'; expected one of: search, fetch, ground, recall, expand, refresh"
        )) {
            _ = try await tool.execute(arguments: [
                "mode": .string("serach"),
                "query": .string("offline query"),
            ])
        }

        // The runtime creates the store on first use; absence proves the
        // invalid mode threw before any store or network activity.
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Unknown detail throws invalidToolArguments without reaching the runtime")
    func unknownDetailThrowsBeforeRuntime() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        await #expect(throws: AgentError.invalidToolArguments(
            toolName: "websearch",
            reason: "unknown websearch detail 'verbose'; expected one of: compact, standard, deep, raw"
        )) {
            _ = try await tool.execute(arguments: [
                "mode": .string("recall"),
                "query": .string("offline query"),
                "detail": .string("verbose"),
            ])
        }

        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Non-string mode throws invalidToolArguments")
    func nonStringModeThrows() async throws {
        let tool = makeTool(storeURL: temporaryWebStoreURL())

        await #expect(throws: AgentError.invalidToolArguments(
            toolName: "websearch",
            reason: "websearch 'mode' must be a string"
        )) {
            _ = try await tool.execute(arguments: [
                "mode": .int(2),
                "query": .string("offline query"),
            ])
        }
    }

    @Test("Legacy properties with unknown mode/detail throw")
    func legacyPropertiesThrow() async throws {
        var modeTool = makeTool(storeURL: temporaryWebStoreURL())
        modeTool.mode = "serach"
        await #expect(throws: AgentError.self) {
            _ = try await modeTool.execute()
        }

        var detailTool = makeTool(storeURL: temporaryWebStoreURL())
        detailTool.detail = "verbose"
        await #expect(throws: AgentError.self) {
            _ = try await detailTool.execute()
        }
    }

    @Test("Absent mode defaults to search and stays offline without a key")
    func absentModeDefaultsToSearch() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        let result = try await tool.execute(arguments: [
            "query": .string("deterministic offline search"),
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("No web results found."))
    }

    @Test("Blank mode defaults to search")
    func blankModeDefaultsToSearch() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        let result = try await tool.execute(arguments: [
            "mode": .string("  "),
            "query": .string("deterministic offline search"),
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("No web results found."))
    }

    @Test("Null mode reads as absent and defaults to search")
    func nullModeDefaultsToSearch() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        let result = try await tool.execute(arguments: [
            "mode": .null,
            "query": .string("deterministic offline search"),
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("No web results found."))
    }

    @Test("Null detail reads as absent and defaults to compact")
    func nullDetailDefaultsToCompact() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        let result = try await tool.execute(arguments: [
            "query": .string("deterministic offline search"),
            "detail": .null,
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("No web results found."))
    }

    @Test("Mode matching stays case-insensitive")
    func modeMatchingStaysCaseInsensitive() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = makeTool(storeURL: root)

        let result = try await tool.execute(arguments: [
            "mode": .string("RECALL"),
            "goal": .string("cached swarm docs"),
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("Recalled 0 cached sections for 'cached swarm docs'."))
    }

    private func makeTool(storeURL: URL) -> WebSearchTool {
        WebSearchTool(configuration: WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: storeURL
        ))
    }

    private func temporaryWebStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-websearch-modes-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
#endif
