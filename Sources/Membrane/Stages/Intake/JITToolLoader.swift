import MembraneCore

public struct JITToolLoader: Sendable {
    public let jitMinToolCount: Int

    public init(jitMinToolCount: Int = 10) {
        self.jitMinToolCount = jitMinToolCount
    }

    public func plan(tools: [ToolManifest], existingPlan: ToolPlan) -> ToolPlan {
        let loadedToolNames: [String]
        switch existingPlan {
        case let .jit(_, loaded):
            loadedToolNames = loaded
        default:
            loadedToolNames = []
        }

        // Sticky JIT: once tools are actively loaded, keep JIT mode for deterministic continuity.
        let shouldUseJIT = tools.count >= jitMinToolCount || !loadedToolNames.isEmpty
        guard shouldUseJIT else {
            return .allowAll
        }

        let index = tools.map { tool in
            ToolIndexEntry(name: tool.name, description: tool.description)
        }

        return ToolPlan.jit(normalized: index, loaded: loadedToolNames)
    }
}
