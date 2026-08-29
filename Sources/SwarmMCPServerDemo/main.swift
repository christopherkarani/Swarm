import Foundation
import Swarm
import SwarmMCP

@main
struct SwarmMCPServerDemo {
    static func main() async throws {
        #if !SWARM_MCP
        fputs(MCPTrait.requirementMessage() + "\n", stderr)
        Foundation.exit(1)
        #else
        Log.bootstrap()

        let registry = try ToolRegistry(
            tools: [
                DateTimeTool(),
                StringTool(),
            ]
        )

        let adapter = SwarmMCPToolRegistryAdapter(registry: registry)
        let service = SwarmMCPServerService(
            name: "swarm-mcp-demo",
            version: Swarm.version,
            instructions: "Swarm MCP demo server exposing built-in tools.",
            toolCatalog: adapter,
            toolExecutor: adapter
        )

        try await service.startStdio()
        await service.waitUntilCompleted()
        #endif
    }
}
