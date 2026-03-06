// ToolBuilder.swift
// Swarm Framework
//
// Result builder for composing tool lists in Agent init.
// Named ToolBuilderV3 during transition.

/// Result builder for composing tool lists in the Agent init trailing closure.
///
/// ```swift
/// let agent = AgentV3("instructions") {
///     WeatherTool()
///     CalculatorTool()
///     if needsSearch {
///         SearchTool()
///     }
/// }
/// ```
@resultBuilder
public struct ToolBuilderV3 {
    public static func buildBlock(_ tools: [any ToolV3]...) -> [any ToolV3] {
        tools.flatMap { $0 }
    }

    public static func buildExpression(_ tool: any ToolV3) -> [any ToolV3] {
        [tool]
    }

    public static func buildExpression(_ tool: some ToolV3) -> [any ToolV3] {
        [tool]
    }

    public static func buildOptional(_ tools: [any ToolV3]?) -> [any ToolV3] {
        tools ?? []
    }

    public static func buildEither(first tools: [any ToolV3]) -> [any ToolV3] {
        tools
    }

    public static func buildEither(second tools: [any ToolV3]) -> [any ToolV3] {
        tools
    }

    public static func buildArray(_ groups: [[any ToolV3]]) -> [any ToolV3] {
        groups.flatMap { $0 }
    }

    // Support passing an array of tools directly
    public static func buildExpression(_ tools: [any ToolV3]) -> [any ToolV3] {
        tools
    }
}
