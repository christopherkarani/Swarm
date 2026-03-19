// ToolBridging.swift
// Swarm Framework
//
// Bridges typed `Tool` implementations to the dynamic `AnyJSONTool` ABI.

import Foundation

// MARK: - AnyJSONToolAdapter

/// Adapts a typed `Tool` into the dynamic `AnyJSONTool` ABI.
public struct AnyJSONToolAdapter<T: Tool>: AnyJSONTool, Sendable {
    // MARK: Public

    /// The wrapped typed tool instance.
    public let tool: T

    /// The tool name, forwarded from the wrapped tool.
    public var name: String { tool.name }

    /// The tool description, forwarded from the wrapped tool.
    public var description: String { tool.description }

    /// The tool parameters, forwarded from the wrapped tool.
    public var parameters: [ToolParameter] { tool.parameters }

    /// Input guardrails from the wrapped tool.
    public var inputGuardrails: [any ToolInputGuardrail] { tool.inputGuardrails }

    /// Output guardrails from the wrapped tool.
    public var outputGuardrails: [any ToolOutputGuardrail] { tool.outputGuardrails }

    /// Creates an adapter that wraps the given typed tool.
    ///
    /// - Parameter tool: The typed `Tool` to adapt to the `AnyJSONTool` protocol.
    public init(_ tool: T) {
        self.tool = tool
    }

    /// Executes the wrapped tool with the provided arguments.
    ///
    /// This method bridges between the dynamic `AnyJSONTool` ABI and the typed `Tool` protocol
    /// by decoding arguments into the tool's `Input` type, executing, and encoding the output.
    ///
    /// - Parameter arguments: The raw arguments dictionary from the LLM tool call.
    /// - Returns: The tool output encoded as a `SendableValue`.
    /// - Throws: `AgentError.invalidToolArguments` if argument decoding fails.
    /// - Throws: `AgentError.toolExecutionFailed` if output encoding fails.
    /// - Throws: Any error thrown by the wrapped tool's `execute` method.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let input: T.Input
        do {
            input = try SendableValue.dictionary(arguments).decode()
        } catch {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Failed to decode arguments into \(String(describing: T.Input.self)): \(error.localizedDescription)"
            )
        }

        let output = try await tool.execute(input)

        do {
            return try SendableValue(encoding: output)
        } catch {
            throw AgentError.toolExecutionFailed(
                toolName: name,
                underlyingError: "Failed to encode \(String(describing: T.Output.self)) into JSONValue: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Tool Convenience

public extension Tool {
    /// Wraps this typed tool as an `AnyJSONTool` for agent/tool-registry use.
    func asAnyJSONTool() -> AnyJSONToolAdapter<Self> {
        AnyJSONToolAdapter(self)
    }
}

