import Swarm

/// Macro-free consumer surface used by the CI fixture.
///
/// This module depends on Swarm with `traits: []` (Macros disabled) and must
/// compile using ``FunctionTool`` instead of `@Tool` / `@Parameter`.
public enum MacrosDisabledConsumer {
    /// Builds a `FunctionTool` echo helper for the fixture smoke test.
    public static func makeEchoTool() -> FunctionTool {
        FunctionTool(
            name: "echo",
            description: "Echoes a message",
            parameters: [
                ToolParameter(
                    name: "message",
                    description: "Text to echo",
                    type: .string
                ),
            ]
        ) { args in
            let message = try args.require("message", as: String.self)
            return .string("echo:\(message)")
        }
    }
}
