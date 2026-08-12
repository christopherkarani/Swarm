import Foundation
import Swarm
import Testing
@testable import WaxChatCore

@Suite("ChatAgentFactory")
struct ChatAgentFactoryTests {
    @Test("Factory registers websearch and wires Wax-backed memory")
    func factoryRegistersWebSearchAndWaxMemory() async throws {
        let configuration = ChatAgentConfiguration.temporary(demoMode: true)
        defer { try? FileManager.default.removeItem(at: configuration.waxStoreURL.deletingLastPathComponent()) }

        let bundle = try await ChatAgentFactory.makeAgent(configuration: configuration)

        #expect(bundle.usesWebSearch)
        #expect(bundle.toolNames.map { $0.lowercased() }.contains("websearch"))
        #expect(bundle.usesWaxMemory)
        #expect(bundle.waxStoreURL.path == configuration.waxStoreURL.path)
        #expect(bundle.webSearchStoreURL.path == configuration.webSearchStoreURL.path)
        #expect(bundle.isDemoMode)
        #expect(bundle.modeLabel.contains("demo"))

        // Memory on the agent is the explicit Wax override (not only .conversation).
        let memory = try #require(bundle.agent.memory)
        #expect(memory is WaxMemory)
        // Bundle exposes the same concrete Wax handle used for session→Wax sync.
        #expect(await bundle.waxMemory.count == 0)
    }

    @Test("makeWebSearchTool is named websearch and enabled")
    func makeWebSearchToolIsNamedAndEnabled() {
        let configuration = ChatAgentConfiguration.temporary(demoMode: true)
        defer { try? FileManager.default.removeItem(at: configuration.waxStoreURL.deletingLastPathComponent()) }

        let tool = ChatAgentFactory.makeWebSearchTool(configuration: configuration)
        #expect(tool.name == "websearch")
        #expect(tool.isEnabled)
    }

    @Test("Demo provider resolves without Foundation Models")
    func demoProviderResolves() throws {
        let (provider, label) = try ChatAgentFactory.makeProvider(demoMode: true)
        #expect(label.contains("demo"))
        #expect(provider is DemoScriptedProvider)
    }
}
