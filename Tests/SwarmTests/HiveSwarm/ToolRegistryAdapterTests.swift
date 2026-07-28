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
}
#endif
