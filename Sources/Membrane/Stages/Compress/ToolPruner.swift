import MembraneCore

public struct ToolPruner: Sendable {
    public let pruneAfterTurn: Int
    public let keepTopK: Int

    public init(pruneAfterTurn: Int = 8, keepTopK: Int = 12) {
        self.pruneAfterTurn = pruneAfterTurn
        self.keepTopK = keepTopK
    }

    public func prune(
        availableTools: [ToolManifest],
        existingPlan: ToolPlan,
        usageCountByToolName: [String: Int],
        currentTurn: Int
    ) -> ToolPlan {
        if case .jit = existingPlan {
            return existingPlan
        }

        guard currentTurn >= pruneAfterTurn else {
            return existingPlan
        }

        let kept = availableTools
            .map { tool in
                (name: tool.name, usage: usageCountByToolName[tool.name] ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.usage != rhs.usage {
                    return lhs.usage > rhs.usage
                }
                return lhs.name < rhs.name
            }
            .prefix(max(0, keepTopK))
            .map(\.name)

        return ToolPlan.allowList(normalized: Array(kept))
    }
}
