// ToolRegistry.swift
// Swarm Framework
//
// Thread-safe registry for tool registration, lookup, and execution.

import Foundation

// MARK: - ToolRegistry

/// Errors thrown by ``ToolRegistry`` operations.
public enum ToolRegistryError: Error, Sendable {
    /// Thrown when attempting to register a tool with a name that already exists.
    case duplicateToolName(name: String)
}

/// A registry for managing available tools.
///
/// `ToolRegistry` provides thread-safe tool registration and lookup using Swift's
/// actor isolation. Use it to manage the set of tools available to an agent.
///
/// ## Basic Usage
///
/// Create a registry with initial tools:
///
/// ```swift
/// let registry = try ToolRegistry(tools: [
///     DateTimeTool(),
///     StringTool()
/// ])
/// ```
///
/// Or build one incrementally:
///
/// ```swift
/// let registry = ToolRegistry()
/// try await registry.register(WeatherTool())
/// try await registry.register(CalculatorTool())
/// ```
///
/// ## Tool Execution
///
/// Execute tools by name with arguments:
///
/// ```swift
/// let result = try await registry.execute(
///     toolNamed: "datetime",
///     arguments: ["format": .string("iso8601")]
/// )
/// ```
///
/// ## Thread Safety
///
/// `ToolRegistry` is an actor, ensuring all operations are thread-safe.
/// All mutating methods (`register`, `unregister`) and even read-only
/// methods (`tool(named:)`, `allTools`) must be called with `await`.
///
/// - SeeAlso: ``AnyJSONTool``, ``Tool``
public actor ToolRegistry {
    /// Gets all registered tools.
    ///
    /// Includes both enabled and disabled tools. Use `schemas` for
    /// a filtered list of only enabled tools suitable for LLM prompts.
    public var allTools: [any AnyJSONTool] {
        Array(tools.values)
    }

    /// Gets all tool names.
    public var toolNames: [String] {
        Array(tools.keys)
    }

    /// Gets tool schemas for all enabled tools.
    ///
    /// This is typically used to generate tool definitions for LLM providers,
    /// as disabled tools should not be exposed to the model.
    public var schemas: [ToolSchema] {
        tools.values.filter(\.isEnabled).map(\.schema)
    }

    /// The number of registered tools.
    public var count: Int {
        tools.count
    }

    /// Creates an empty tool registry.
    public init() {}

    /// Creates a tool registry with the given tools.
    ///
    /// - Parameter tools: The initial tools to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if a tool with the same name already exists.
    public init(tools: [any AnyJSONTool]) throws {
        try Self.validateUniqueToolNames(tools.map(\.name), existingNames: [])
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    /// Creates a tool registry with the given typed tools.
    ///
    /// - Parameter tools: The initial typed tools to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if a tool with the same name already exists.
    public init(tools: [some Tool]) throws {
        try Self.validateUniqueToolNames(tools.map(\.name), existingNames: [])
        for tool in tools {
            let name = tool.name
            self.tools[name] = AnyJSONToolAdapter(tool)
        }
    }

    /// Registers a tool.
    ///
    /// - Parameter tool: The tool to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if a tool with the same name already exists.
    public func register(_ tool: any AnyJSONTool) throws {
        guard tools[tool.name] == nil else {
            throw ToolRegistryError.duplicateToolName(name: tool.name)
        }
        tools[tool.name] = tool
    }

    /// Registers a typed tool by bridging it to ``AnyJSONTool``.
    ///
    /// - Parameter tool: The typed tool to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if a tool with the same name already exists.
    public func register(_ tool: some Tool) throws {
        let name = tool.name
        guard tools[name] == nil else {
            throw ToolRegistryError.duplicateToolName(name: name)
        }
        tools[name] = AnyJSONToolAdapter(tool)
    }

    /// Registers multiple typed tools.
    ///
    /// - Parameter newTools: The typed tools to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if any tool name already exists.
    public func register(_ newTools: [some Tool]) throws {
        try Self.validateUniqueToolNames(newTools.map(\.name), existingNames: Set(tools.keys))
        for tool in newTools {
            let name = tool.name
            tools[name] = AnyJSONToolAdapter(tool)
        }
    }

    /// Registers multiple tools.
    ///
    /// - Parameter newTools: The tools to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if any tool name already exists.
    public func register(_ newTools: [any AnyJSONTool]) throws {
        try Self.validateUniqueToolNames(newTools.map(\.name), existingNames: Set(tools.keys))
        for tool in newTools {
            tools[tool.name] = tool
        }
    }

    /// Unregisters a tool by name.
    ///
    /// - Parameter name: The name of the tool to unregister.
    /// - Note: Silently succeeds if no tool with that name exists.
    public func unregister(named name: String) {
        tools.removeValue(forKey: name)
    }

    /// Gets a tool by name.
    ///
    /// - Parameter name: The tool name.
    /// - Returns: The tool, or `nil` if not found.
    public func tool(named name: String) -> (any AnyJSONTool)? {
        tools[name]
    }

    /// Returns true if a tool with the given name is registered.
    ///
    /// - Parameter name: The tool name.
    /// - Returns: `true` if the tool exists (regardless of enabled state).
    public func contains(named name: String) -> Bool {
        tools[name] != nil
    }

    /// Executes a tool by name with the given arguments.
    ///
    /// This method handles the complete tool execution lifecycle:
    /// 1. Looks up the tool by name
    /// 2. Checks if the tool is enabled
    /// 3. Normalizes arguments (applies defaults and type coercion)
    /// 4. Runs input guardrails
    /// 5. Executes the tool
    /// 6. Runs output guardrails
    ///
    /// - Parameters:
    ///   - name: The name of the tool to execute.
    ///   - arguments: The arguments to pass to the tool.
    ///   - agent: Optional agent executing the tool (for guardrail validation).
    ///   - context: Optional agent context for guardrail validation.
    ///   - observer: Optional observer for error reporting.
    /// - Returns: The result of the tool execution.
    /// - Throws: ``AgentError/toolNotFound`` if the tool doesn't exist or is disabled,
    ///           ``AgentError/toolFailure(toolName:message:cause:)`` if execution fails,
    ///           ``GuardrailError`` if guardrails are triggered,
    ///           or `CancellationError` if the task is cancelled.
    public func execute(
        toolNamed name: String,
        arguments: [String: SendableValue],
        agent: (any AgentRuntime)? = nil,
        context: AgentContext? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> SendableValue {
        // Check for cancellation before proceeding
        try Task.checkCancellation()

        guard let tool = tools[name] else {
            throw AgentError.toolNotFound(name: name)
        }

        guard tool.isEnabled else {
            throw AgentError.toolNotFound(name: name)
        }

        // Normalize arguments (defaults + coercion) before guardrails/execution.
        let normalizedArguments = try tool.normalizeArguments(arguments)

        // Create a single GuardrailRunner instance for both input and output guardrails
        let runner = GuardrailRunner()
        let data = ToolGuardrailData(tool: tool, arguments: normalizedArguments, agent: agent, context: context)

        do {
            // Run input guardrails
            if !tool.inputGuardrails.isEmpty {
                _ = try await runner.runToolInputGuardrails(tool.inputGuardrails, data: data)
            }

            let result = try await tool.execute(arguments: normalizedArguments)

            // Run output guardrails
            if !tool.outputGuardrails.isEmpty {
                _ = try await runner.runToolOutputGuardrails(tool.outputGuardrails, data: data, output: result)
            }

            return result
        } catch {
            // Notify observer for any error (guardrail, execution, or otherwise)
            if let agent, let observer {
                await observer.onError(context: context, agent: agent, error: error)
            }

            // Re-throw original error or wrap it
            if let agentError = error as? AgentError {
                throw agentError
            } else if error is CancellationError {
                throw error
            } else if let guardrailError = error as? GuardrailError {
                throw guardrailError
            } else {
                throw AgentError.toolFailure(
                    toolName: name,
                    message: error.localizedDescription,
                    cause: error
                )
            }
        }
    }

    /// Executes a registered typed tool with a compile-checked input value.
    ///
    /// This is a thin generic shell over
    /// ``execute(toolNamed:arguments:agent:context:observer:)``: the input is
    /// encoded to an argument dictionary, the existing untyped lifecycle
    /// (lookup, enabled check, normalization, guardrails, observer notification,
    /// error mapping) runs unchanged, and the result is decoded to `T.Output`.
    ///
    /// - Important: Registered-tool-wins: the passed `tool` supplies the registry
    ///   `name` and the static `Input`/`Output` types; guardrails, semantics, and
    ///   enabled state come from the tool instance stored in the registry, never
    ///   from the passed instance.
    ///
    /// - Parameters:
    ///   - tool: A typed tool whose `name` identifies the registered tool and whose
    ///     `Input`/`Output` types drive encoding and decoding.
    ///   - input: The typed input value. It must encode to a keyed object.
    ///   - agent: Optional agent executing the tool (for guardrail validation).
    ///   - context: Optional agent context for guardrail validation.
    ///   - observer: Optional observer for error reporting.
    /// - Returns: The decoded typed output.
    /// - Throws: ``AgentError/toolNotFound`` if the tool doesn't exist or is disabled,
    ///           ``AgentError/invalidToolArguments(toolName:reason:)`` if `input` fails
    ///           to encode or does not encode to a keyed object,
    ///           ``AgentError/toolFailure(toolName:message:cause:)`` if the result
    ///           cannot be decoded as `T.Output`,
    ///           ``GuardrailError`` if guardrails are triggered,
    ///           or `CancellationError` if the task is cancelled.
    public func execute<T: Tool>(
        tool: T,
        input: T.Input,
        agent: (any AgentRuntime)? = nil,
        context: AgentContext? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> T.Output where T.Output: Decodable {
        let arguments: [String: SendableValue]
        do {
            let encoded = try SendableValue(encoding: input)
            guard let dictionary = encoded.dictionaryValue else {
                throw AgentError.invalidToolArguments(
                    toolName: tool.name,
                    reason: "Input of type \(String(describing: T.Input.self)) must encode to a keyed object ([String: SendableValue])"
                )
            }
            arguments = dictionary
        } catch let agentError as AgentError {
            throw agentError
        } catch {
            throw AgentError.invalidToolArguments(
                toolName: tool.name,
                reason: "Failed to encode input of type \(String(describing: T.Input.self)) to a keyed object ([String: SendableValue]): \(error.localizedDescription)"
            )
        }

        let result = try await execute(
            toolNamed: tool.name,
            arguments: arguments,
            agent: agent,
            context: context,
            observer: observer
        )

        // `SendableValue.decode()` routes scalar and null results through
        // `JSONSerialization` without fragment support, which raises an
        // uncatchable `NSException` (process abort) when `T.Output` is not the
        // identical primitive. Divert those mismatches to `toolFailure` so the
        // typed mismatch path always throws per REQ-004 instead of crashing.
        guard result.canAttemptTypedDecode(as: T.Output.self) else {
            let cause = SendableValue.ConversionError.decodingFailed(
                "result is \(result.shapeDescription), which cannot decode as \(String(describing: T.Output.self))"
            )
            throw AgentError.toolFailure(
                toolName: tool.name,
                message: "Failed to decode result of \"\(tool.name)\" as \(String(describing: T.Output.self)): \(cause.localizedDescription)",
                cause: cause
            )
        }

        do {
            let output: T.Output = try result.decode()
            return output
        } catch {
            throw AgentError.toolFailure(
                toolName: tool.name,
                message: "Failed to decode result of \"\(tool.name)\" as \(String(describing: T.Output.self)): \(error.localizedDescription)",
                cause: error
            )
        }
    }

    // MARK: Private

    private var tools: [String: any AnyJSONTool] = [:]

    private static func validateUniqueToolNames(_ names: [String], existingNames: Set<String>) throws {
        var seen = existingNames
        for name in names {
            guard seen.insert(name).inserted else {
                throw ToolRegistryError.duplicateToolName(name: name)
            }
        }
    }
}

// MARK: - Typed Decode Safety

fileprivate extension SendableValue {
    /// Whether `decode()` can be attempted for `type` without aborting the process.
    ///
    /// Mirrors `decode()`'s dispatch: the four JSON primitives are handled only
    /// when `T` is the identical type (with `Double` also accepting `.int` via
    /// `doubleValue`), and everything else goes through `JSONSerialization`,
    /// whose top-level value must be an array or dictionary. Any other pairing
    /// would raise an uncatchable `NSException` instead of throwing.
    func canAttemptTypedDecode<T: Decodable>(as type: T.Type) -> Bool {
        if dictionaryValue != nil || arrayValue != nil {
            return true
        }
        if T.self == Bool.self {
            return boolValue != nil
        }
        if T.self == Int.self {
            return intValue != nil
        }
        if T.self == Double.self {
            return doubleValue != nil
        }
        if T.self == String.self {
            return stringValue != nil
        }
        return false
    }

    /// Short human-readable shape name for decode-failure messages.
    var shapeDescription: String {
        switch self {
        case .null:
            "null"
        case .bool:
            "a boolean"
        case .int:
            "an integer"
        case .double:
            "a double"
        case .string:
            "a string"
        case .array:
            "an array"
        case .dictionary:
            "a dictionary"
        }
    }
}
