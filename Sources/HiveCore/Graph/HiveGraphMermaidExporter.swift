import Foundation

public enum HiveGraphMermaidExporter {
    public static func export(_ description: HiveGraphDescription) -> String {
        var lines: [String] = []
        lines.append("flowchart LR")

        let nodeIDs = description.nodes
        var mermaidIDByNodeID: [HiveNodeID: String] = [:]
        mermaidIDByNodeID.reserveCapacity(nodeIDs.count)

        for (index, nodeID) in nodeIDs.enumerated() {
            let mermaidID = "node_\(index)"
            mermaidIDByNodeID[nodeID] = mermaidID
            lines.append("  \(mermaidID)[\"\(escapeMermaidLabel(nodeID.rawValue))\"]")
        }

        if !description.routers.isEmpty {
            lines.append("  classDef router fill:#fff7ed,stroke:#c2410c,stroke-width:1px;")
            for routerNodeID in description.routers {
                guard let mermaidID = mermaidIDByNodeID[routerNodeID] else { continue }
                lines.append("  class \(mermaidID) router")
            }
        }

        for edge in description.staticEdges {
            guard let from = mermaidIDByNodeID[edge.from],
                  let to = mermaidIDByNodeID[edge.to] else { continue }
            lines.append("  \(from) --> \(to)")
        }

        if !description.joinEdges.isEmpty {
            lines.append("  classDef join fill:#eff6ff,stroke:#1d4ed8,stroke-width:1px;")
        }

        for (index, join) in description.joinEdges.enumerated() {
            let joinID = "join_\(index + 1)"
            lines.append("  \(joinID){\"\(escapeMermaidLabel(join.id))\"}")
            lines.append("  class \(joinID) join")

            for parent in join.parents {
                guard let parentID = mermaidIDByNodeID[parent] else { continue }
                lines.append("  \(parentID) --> \(joinID)")
            }
            if let targetID = mermaidIDByNodeID[join.target] {
                lines.append("  \(joinID) --> \(targetID)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func escapeMermaidLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
