// ToolBridging.swift
// Swarm Framework
//
// Bridges typed `Tool` implementations to the dynamic `AnyJSONTool` ABI.

import Foundation

// MARK: - AnyJSONToolAdapter

/// Adapts a typed `Tool` into the dynamic `AnyJSONTool` ABI.
public struct AnyJSONToolAdapter<T: Tool>: AnyJSONTool, Sendable {
    // MARK: Public

    public let tool: T

    public var name: String { tool.name }
    public var description: String { tool.description }
    public var parameters: [ToolParameter] { tool.parameters }
    public var inputGuardrails: [any ToolInputGuardrail] { tool.inputGuardrails }
    public var outputGuardrails: [any ToolOutputGuardrail] { tool.outputGuardrails }
    public var executionSemantics: ToolExecutionSemantics { tool.executionSemantics }

    public init(_ tool: T) {
        self.tool = tool
    }

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
            throw AgentError.toolFailure(
                toolName: name,
                message: "Failed to encode \(String(describing: T.Output.self)) into JSONValue: \(error.localizedDescription)",
                cause: error
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
