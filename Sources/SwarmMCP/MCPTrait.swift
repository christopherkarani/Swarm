/// Build-time availability of Swarm's MCP SwiftPM trait.
///
/// The MCP Swift SDK types in this product (`SwarmMCPServerService` and
/// related adapters) compile only when the trait is enabled. Swarm's
/// built-in MCP *client* lives in the `Swarm` product and does not need
/// this trait.
public enum MCPTrait: Sendable {
    /// Whether this process was compiled with the `MCP` SwiftPM trait.
    public static var isEnabled: Bool {
        #if SWARM_MCP
        true
        #else
        false
        #endif
    }

    /// User-facing message naming the missing trait and the rebuild remedy.
    ///
    /// - Parameter feature: Short name of the gated capability.
    /// - Returns: A message that names the MCP trait and how to enable it.
    public static func requirementMessage(for feature: String = "SwarmMCP") -> String {
        "\(feature) requires the MCP trait. Rebuild with `--traits MCP`, or add `traits: [\"MCP\"]` to the Swarm package dependency."
    }
}
