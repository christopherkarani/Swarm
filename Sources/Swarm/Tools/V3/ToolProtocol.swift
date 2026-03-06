// ToolProtocol.swift
// Swarm Framework
//
// V3 tool protocol — the new developer-facing tool API.
// Named ToolV3 during the transition to avoid collision with the existing
// typed Tool protocol in TypedToolProtocol.swift. Renamed to Tool in Phase 10.

// MARK: - ToolV3

/// A tool that an agent can invoke.
///
/// Conform to `ToolV3` by declaring `@Parameter` properties and a `call()` method.
/// The framework populates properties from LLM arguments before calling `call()`.
///
/// ```swift
/// struct WeatherTool: ToolV3 {
///     let name = "weather"
///     let description = "Gets current weather"
///     @ParameterV3("City name") var city: String
///     func call() async throws -> String { "72°F in \(city)" }
/// }
/// ```
///
/// - Note: All conforming types must be `Sendable` — agents execute tools
///   concurrently across task contexts.
public protocol ToolV3: Sendable {
    /// Unique name for this tool (used in LLM tool-calling). Use snake_case.
    var name: String { get }

    /// Human-readable description shown to the LLM.
    var description: String { get }

    /// Execute the tool. Properties are pre-populated by the framework.
    ///
    /// - Returns: A plain-text result fed back to the model as tool output.
    /// - Throws: Any error that prevents the tool from producing a result.
    func call() async throws -> String
}
