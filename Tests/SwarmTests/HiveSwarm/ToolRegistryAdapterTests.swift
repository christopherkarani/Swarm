#if SWARM_INTEGRATIONS
import Foundation
import HiveCore
@_spi(ColonyInternal) @testable import Swarm
import Testing

@Suite("ToolRegistryAdapter Tests")
struct SwarmToolRegistryTests {
    @Test("listTools returns sorted definitions")
    func listToolsReturnsSortedDefinitions() throws {
        let toolB = MockTool(name: "beta")
        let toolA = MockTool(name: "alpha")
        let registry = try ToolRegistryAdapter(tools: [toolB, toolA])

        let names = registry.listTools().map(\.name)
        #expect(names == ["alpha", "beta"])
    }

    @Test("invoke executes tool and encodes result")
    func invokeExecutesTool() async throws {
        let tool = MockTool(
            name: "echo",
            parameters: [
                ToolParameter(name: "text", description: "Text to echo", type: .string)
            ],
            result: .string("hi")
        )
        let registry = try ToolRegistryAdapter(tools: [tool])

        let call = HiveToolCall(id: "call_1", name: "echo", argumentsJSON: #"{"text":"hi"}"#)
        let result = try await registry.invoke(call)

        #expect(result.toolCallID == "call_1")
        #expect(result.content == "hi")
    }

    @Test("invoke rejects non-object arguments")
    func invokeRejectsNonObjectArguments() async throws {
        let tool = MockTool(name: "echo")
        let registry = try ToolRegistryAdapter(tools: [tool])

        let call = HiveToolCall(id: "call_2", name: "echo", argumentsJSON: "[]")
        await #expect(throws: ToolRegistryAdapterError.self) {
            _ = try await registry.invoke(call)
        }
    }

    @Test("fromRegistry snapshots sorted definitions and invokes registry tools")
    func fromRegistrySnapshotsAndInvokes() async throws {
        let toolRegistry = try ToolRegistry(tools: [
            MockTool(name: "zeta", result: .string("z")),
            MockTool(name: "alpha", result: .string("a"))
        ])
        let adapter = try await ToolRegistryAdapter.fromRegistry(toolRegistry)

        #expect(adapter.listTools().map(\.name) == ["alpha", "zeta"])

        let result = try await adapter.invoke(HiveToolCall(id: "call_3", name: "zeta", argumentsJSON: "{}"))
        #expect(result.toolCallID == "call_3")
        #expect(result.content == "z")
    }

    @Test("invoke reports unknown tools and malformed JSON with typed errors")
    func invokeTypedErrors() async throws {
        let adapter = try ToolRegistryAdapter(tools: [MockTool(name: "echo")])

        await #expect(throws: ToolRegistryAdapterError.toolNotFound(name: "missing")) {
            _ = try await adapter.invoke(HiveToolCall(id: "call_4", name: "missing", argumentsJSON: "{}"))
        }
        await #expect(throws: ToolRegistryAdapterError.invalidArgumentsJSON) {
            _ = try await adapter.invoke(HiveToolCall(id: "call_5", name: "echo", argumentsJSON: "{not json"))
        }
    }

    @Test("duplicate tool names are rejected at construction")
    func duplicateToolNames() {
        #expect(throws: ToolRegistryAdapterError.duplicateToolName("echo")) {
            _ = try ToolRegistryAdapter(tools: [MockTool(name: "echo"), MockTool(name: "echo")])
        }
    }
}
#endif
