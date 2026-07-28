#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

@Suite("WebSearchTool Behavior")
struct WebSearchToolBehaviorTests {
    @Test("Disabled configuration reports unavailable and no-key search stays local")
    func execute_withDisabledNoKeyConfiguration_returnsDeterministicEmptySearch() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tool = WebSearchTool(configuration: WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root,
            enabled: false
        ))

        #expect(tool.isEnabled == false)

        let result = try await tool.execute(arguments: [
            "query": .string("deterministic offline search"),
            "maxResults": .int(3),
            "domains": .array([.string("example.com")]),
            "recencyDays": .int(7),
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("No web results found."))
    }

    @Test("Recall mode accepts goal as query alias without live network")
    func execute_withRecallModeAndGoalAlias_returnsEmptyCachedRecall() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tool = WebSearchTool(configuration: WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root
        ))

        let result = try await tool.execute(arguments: [
            "mode": .string("RECALL"),
            "goal": .string("cached swarm docs"),
            "detail": .string("STANDARD"),
            "includeRawContent": .bool(true),
            "maxResults": .int(0),
        ])

        let output = try #require(result.stringValue)
        #expect(output.contains("Recalled 0 cached sections for 'cached swarm docs'."))
    }

    @Test("Fetch mode requires URL argument")
    func execute_withFetchModeMissingURL_throwsInvalidToolArguments() async throws {
        let root = temporaryWebStoreURL()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tool = WebSearchTool(configuration: WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: false,
            storeURL: root
        ))

        await #expect(throws: AgentError.self) {
            _ = try await tool.execute(arguments: [
                "mode": .string("fetch"),
            ])
        }
    }

    private func temporaryWebStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-websearch-tool-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
#endif
