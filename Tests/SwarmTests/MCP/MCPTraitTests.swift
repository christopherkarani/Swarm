import SwarmMCP
import Testing

@Suite("MCPTrait")
struct MCPTraitTests {
    @Test("MCPTrait.isEnabled matches the SWARM_MCP compilation flag")
    func isEnabledMatchesCompilationFlag() {
        #if SWARM_MCP
        #expect(MCPTrait.isEnabled)
        #else
        #expect(!MCPTrait.isEnabled)
        #endif
    }
}
