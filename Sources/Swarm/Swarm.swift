// Swarm.swift
// Swarm Framework
//
// LangChain for Apple Platforms - A comprehensive Swift framework
// for building AI agents with Apple's Foundation Models.

/// Swarm Framework
///
/// Provides agent orchestration, memory systems, tool integration,
/// and multi-agent coordination for Apple platforms.
///
/// ## Overview
///
/// Swarm is the agent layer that sits on top of inference providers
/// like Foundation Models or SwiftAI SDK, enabling autonomous reasoning
/// and complex task execution.
///
/// ## Quick Start
///
/// ```swift
/// import Swarm
///
/// // Create an agent with instructions, a provider, and a trailing
/// // @ToolBuilder closure listing the agent's tools.
/// let agent = try Agent("You are a helpful assistant that can perform calculations.",
///     inferenceProvider: .anthropic(key: "sk-...")) {
///     CalculatorTool()
///     DateTimeTool()
/// }
///
/// // Run the agent
/// let result = try await agent.run("What is 25 * 4?")
/// print(result.output)
/// ```
///
/// ## Supported Platforms
///
/// - macOS 26.0+
/// - iOS 26.0+
/// - tvOS 26.0+
///
public enum Swarm {
    /// The current version of the Swarm framework.
    public static let version = "0.6.0"

    /// The minimum macOS platform version required by Swarm.
    public static let minimumMacOSVersion = "26.0"

    /// The minimum iOS platform version required by Swarm.
    public static let minimumiOSVersion = "26.0"
}
