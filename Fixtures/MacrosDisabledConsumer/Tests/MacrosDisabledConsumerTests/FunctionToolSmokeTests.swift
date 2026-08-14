import Swarm
import Testing
@testable import MacrosDisabledConsumer

@Suite("Macros-disabled consumer")
struct FunctionToolSmokeTests {
    @Test("FunctionTool executes without @Tool macros")
    func functionToolEchoesMessage() async throws {
        let tool = MacrosDisabledConsumer.makeEchoTool()
        let result = try await tool.execute(arguments: ["message": .string("hi")])
        #expect(result.stringValue == "echo:hi")
    }
}
