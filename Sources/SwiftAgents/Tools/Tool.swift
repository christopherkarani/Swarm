// Tool.swift
// SwiftAgents Framework
//
// Dynamic (JSON) tool protocol and supporting types for tool execution.

import Foundation

// MARK: - AnyJSONTool

/// A dynamically-typed tool that operates on JSON-like values.
///
/// `AnyJSONTool` is the low-level ABI used at the model boundary, where tool
/// arguments and results are JSON-shaped and validated at runtime.
///
/// Example:
/// ```swift
/// struct WeatherTool: AnyJSONTool {
///     let name = "weather"
///     let description = "Gets the current weather for a location"
///     let parameters: [ToolParameter] = [
///         ToolParameter(name: "location", description: "City name", type: .string)
///     ]
///
///     func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
///         guard let location = arguments["location"]?.stringValue else {
///             throw AgentError.invalidToolArguments(toolName: name, reason: "Missing location")
///         }
///         return .string("72°F and sunny in \(location)")
///     }
/// }
/// ```
public protocol AnyJSONTool: Sendable {
    /// The unique name of the tool.
    var name: String { get }

    /// A description of what the tool does (used in prompts to help the model understand).
    var description: String { get }

    /// The parameters this tool accepts.
    var parameters: [ToolParameter] { get }

    /// Input guardrails for this tool.
    var inputGuardrails: [any ToolInputGuardrail] { get }

    /// Output guardrails for this tool.
    var outputGuardrails: [any ToolOutputGuardrail] { get }

    /// Executes the tool with the given arguments.
    /// - Parameter arguments: The arguments passed to the tool.
    /// - Returns: The result of the tool execution.
    /// - Throws: `AgentError.toolExecutionFailed` or `AgentError.invalidToolArguments` on failure.
    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}

// MARK: - AnyJSONTool Protocol Extensions

public extension AnyJSONTool {
    /// Creates a ToolDefinition from this tool.
    var definition: ToolDefinition {
        ToolDefinition(from: self)
    }

    /// Default input guardrails (none).
    var inputGuardrails: [any ToolInputGuardrail] { [] }

    /// Default output guardrails (none).
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    /// Validates that the given arguments match this tool's parameters.
    /// - Parameter arguments: The arguments to validate.
    /// - Throws: `AgentError.invalidToolArguments` if validation fails.
    func validateArguments(_ arguments: [String: SendableValue]) throws {
        try ToolArgumentProcessor.validate(
            toolName: name,
            parameters: parameters,
            arguments: arguments
        )
    }

    /// Applies default values and performs best-effort type coercion for tool arguments.
    ///
    /// This is primarily intended for LLM-generated tool calls where values may be quoted
    /// or loosely typed (e.g. `"42"` for an integer parameter).
    ///
    /// - Parameter arguments: The raw arguments passed to the tool.
    /// - Returns: A normalized arguments dictionary suitable for execution.
    /// - Throws: `AgentError.invalidToolArguments` if normalization fails.
    func normalizeArguments(_ arguments: [String: SendableValue]) throws -> [String: SendableValue] {
        try ToolArgumentProcessor.normalize(
            toolName: name,
            parameters: parameters,
            arguments: arguments
        )
    }

    /// Gets a required string argument or throws.
    /// - Parameters:
    ///   - key: The argument key.
    ///   - arguments: The arguments dictionary.
    /// - Returns: The string value.
    /// - Throws: `AgentError.invalidToolArguments` if missing or wrong type.
    func requiredString(_ key: String, from arguments: [String: SendableValue]) throws -> String {
        guard let value = arguments[key]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing or invalid string parameter: \(key)"
            )
        }
        return value
    }

    /// Gets an optional string argument.
    /// - Parameters:
    ///   - key: The argument key.
    ///   - arguments: The arguments dictionary.
    ///   - defaultValue: The default value if not present.
    /// - Returns: The string value or default.
    func optionalString(_ key: String, from arguments: [String: SendableValue], default defaultValue: String? = nil) -> String? {
        arguments[key]?.stringValue ?? defaultValue
    }
}

// MARK: - ToolArgumentProcessor

/// Shared argument validation + normalization logic for `AnyJSONTool`.
private enum ToolArgumentProcessor {
    // MARK: Internal

    static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws {
        try validate(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil)
    }

    static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws -> [String: SendableValue] {
        try normalize(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil)
    }

    // MARK: Private

    private static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?
    ) throws {
        for param in parameters where param.isRequired {
            guard arguments[param.name] != nil else {
                let fullPath = join(pathPrefix, param.name)
                throw AgentError.invalidToolArguments(
                    toolName: toolName,
                    reason: "Missing required parameter: \(fullPath)"
                )
            }
        }

        for param in parameters {
            guard let value = arguments[param.name] else { continue }
            let fullPath = join(pathPrefix, param.name)
            try validateValue(toolName: toolName, value: value, expected: param.type, path: fullPath)
        }
    }

    private static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?
    ) throws -> [String: SendableValue] {
        var normalized = arguments

        // Apply default values
        for param in parameters {
            if normalized[param.name] == nil, let defaultValue = param.defaultValue {
                normalized[param.name] = defaultValue
            }
        }

        // Coerce known parameters to expected types
        for param in parameters {
            guard let value = normalized[param.name] else { continue }
            let fullPath = join(pathPrefix, param.name)
            normalized[param.name] = try coerceValue(toolName: toolName, value: value, expected: param.type, path: fullPath)
        }

        // Validate after applying defaults + coercion
        try validate(toolName: toolName, parameters: parameters, arguments: normalized, pathPrefix: pathPrefix)
        return normalized
    }

    private static func validateValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String
    ) throws {
        switch expected {
        case .any:
            return

        case .string:
            guard case .string = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .int:
            switch value {
            case .int:
                return
            case let .double(d) where d.truncatingRemainder(dividingBy: 1) == 0
                && d >= Double(Int.min)
                && d <= Double(Int.max):
                return
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .double:
            switch value {
            case .double, .int:
                return
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .bool:
            guard case .bool = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case let .array(elementType):
            guard case let .array(elements) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            for (index, element) in elements.enumerated() {
                try validateValue(
                    toolName: toolName,
                    value: element,
                    expected: elementType,
                    path: "\(path)[\(index)]"
                )
            }

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            try validate(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path)

        case let .oneOf(options):
            guard case let .string(s) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            guard options.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) else {
                throw AgentError.invalidToolArguments(
                    toolName: toolName,
                    reason: "Invalid value for parameter: \(path). Expected oneOf(\(options.joined(separator: ", ")))"
                )
            }
        }
    }

    private static func coerceValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String
    ) throws -> SendableValue {
        switch expected {
        case .any:
            return value

        case .string:
            guard case .string = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            return value

        case .int:
            switch value {
            case .int:
                return value
            case let .double(d) where d.truncatingRemainder(dividingBy: 1) == 0
                && d >= Double(Int.min)
                && d <= Double(Int.max):
                return .int(Int(d))
            case let .string(s):
                if let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .int(i)
                }
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .double:
            switch value {
            case let .double(d):
                return .double(d)
            case let .int(i):
                return .double(Double(i))
            case let .string(s):
                if let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .double(d)
                }
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .bool:
            switch value {
            case .bool:
                return value
            case let .string(s):
                switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true":
                    return .bool(true)
                case "false":
                    return .bool(false)
                default:
                    throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
                }
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case let .array(elementType):
            guard case let .array(elements) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try elements.enumerated().map { index, element in
                try coerceValue(
                    toolName: toolName,
                    value: element,
                    expected: elementType,
                    path: "\(path)[\(index)]"
                )
            }
            return .array(coerced)

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try normalize(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path)
            return .dictionary(coerced)

        case let .oneOf(options):
            guard case let .string(s) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            if let matched = options.first(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
                return .string(matched)
            }
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Invalid value for parameter: \(path). Expected oneOf(\(options.joined(separator: ", ")))"
            )
        }
    }

    private static func invalidType(
        toolName: String,
        path: String,
        expected: ToolParameter.ParameterType,
        actual: SendableValue
    ) -> AgentError {
        AgentError.invalidToolArguments(
            toolName: toolName,
            reason: "Invalid type for parameter: \(path). Expected \(expected.description), got \(jsonTypeDescription(actual))"
        )
    }

    private static func join(_ prefix: String?, _ key: String) -> String {
        guard let prefix, !prefix.isEmpty else { return key }
        return "\(prefix).\(key)"
    }

    private static func jsonTypeDescription(_ value: SendableValue) -> String {
        switch value {
        case .null:
            "null"
        case .bool:
            "boolean"
        case .int:
            "integer"
        case .double:
            "number"
        case .string:
            "string"
        case .array:
            "array"
        case .dictionary:
            "object"
        }
    }
}

// MARK: - ToolParameter

/// Describes a parameter that a tool accepts.
public struct ToolParameter: Sendable, Equatable, Encodable {
    /// The type of a tool parameter.
    indirect public enum ParameterType: Sendable, Equatable, CustomStringConvertible, Encodable {
        // MARK: Public

        public var description: String {
            switch self {
            case .string: "string"
            case .int: "integer"
            case .double: "number"
            case .bool: "boolean"
            case let .array(elementType): "array<\(elementType)>"
            case .object: "object"
            case let .oneOf(options): "oneOf(\(options.joined(separator: "|")))"
            case .any: "any"
            }
        }

        public func encode(to encoder: Encoder) throws {
            let schema = ToolSchemaBuilder.schema(for: self)
            var container = encoder.singleValueContainer()
            try container.encode(schema)
        }

        case string
        case int
        case double
        case bool
        case array(elementType: ParameterType)
        case object(properties: [ToolParameter])
        case oneOf([String])
        case any
    }

    /// The name of the parameter.
    public let name: String

    /// A description of the parameter.
    public let description: String

    /// The type of the parameter.
    public let type: ParameterType

    /// Whether this parameter is required.
    public let isRequired: Bool

    /// The default value for this parameter, if any.
    public let defaultValue: SendableValue?

    /// Creates a new tool parameter.
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - description: A description of the parameter.
    ///   - type: The parameter type.
    ///   - isRequired: Whether the parameter is required. Default: true
    ///   - defaultValue: The default value. Default: nil
    public init(
        name: String,
        description: String,
        type: ParameterType,
        isRequired: Bool = true,
        defaultValue: SendableValue? = nil
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}

// MARK: - ToolDefinition

/// A definition of a tool that can be included in model prompts.
///
/// This is a serializable representation of a tool's interface without
/// the actual execution logic.
public struct ToolDefinition: Sendable, Equatable, Encodable {
    /// The name of the tool.
    public let name: String

    /// A description of what the tool does.
    public let description: String

    /// The parameters this tool accepts.
    public let parameters: [ToolParameter]

    /// Creates a new tool definition.
    /// - Parameters:
    ///   - name: The tool name.
    ///   - description: The tool description.
    ///   - parameters: The tool parameters.
    public init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    /// Creates a ToolDefinition from an `AnyJSONTool`.
    /// - Parameter tool: The tool to create a definition from.
    public init(from tool: any AnyJSONTool) {
        name = tool.name
        description = tool.description
        parameters = tool.parameters
    }
}

// MARK: - Tool JSON Schema

public extension ToolParameter {
    /// JSON Schema representation of this parameter.
    var jsonSchema: SendableValue {
        ToolSchemaBuilder.parameterSchema(self)
    }
}

public extension ToolDefinition {
    /// JSON Schema representation of this tool's parameters.
    var jsonSchema: SendableValue {
        ToolSchemaBuilder.definitionSchema(self)
    }
}

private enum ToolSchemaBuilder {
    static func parameterSchema(_ parameter: ToolParameter) -> SendableValue {
        var schema = typeSchema(parameter.type)
        if !parameter.description.isEmpty {
            schema["description"] = .string(parameter.description)
        }
        if let defaultValue = parameter.defaultValue {
            schema["default"] = defaultValue
        }
        return .dictionary(schema)
    }

    static func definitionSchema(_ definition: ToolDefinition) -> SendableValue {
        var properties: [String: SendableValue] = [:]
        var required: [SendableValue] = []

        for parameter in definition.parameters {
            properties[parameter.name] = parameterSchema(parameter)
            if parameter.isRequired {
                required.append(.string(parameter.name))
            }
        }

        var schema: [String: SendableValue] = [
            "type": .string("object"),
            "properties": .dictionary(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required)
        }
        return .dictionary(schema)
    }

    static func schema(for type: ToolParameter.ParameterType) -> [String: SendableValue] {
        typeSchema(type)
    }

    private static func typeSchema(_ type: ToolParameter.ParameterType) -> [String: SendableValue] {
        switch type {
        case .string:
            return ["type": .string("string")]
        case .int:
            return ["type": .string("integer")]
        case .double:
            return ["type": .string("number")]
        case .bool:
            return ["type": .string("boolean")]
        case let .array(elementType):
            return [
                "type": .string("array"),
                "items": .dictionary(typeSchema(elementType))
            ]
        case let .object(properties):
            var propsDict: [String: SendableValue] = [:]
            var required: [SendableValue] = []

            for parameter in properties {
                propsDict[parameter.name] = parameterSchema(parameter)
                if parameter.isRequired {
                    required.append(.string(parameter.name))
                }
            }

            var schema: [String: SendableValue] = [
                "type": .string("object"),
                "properties": .dictionary(propsDict)
            ]
            if !required.isEmpty {
                schema["required"] = .array(required)
            }
            return schema
        case let .oneOf(options):
            return [
                "type": .string("string"),
                "enum": .array(options.map { .string($0) })
            ]
        case .any:
            let types: [SendableValue] = [
                .string("string"),
                .string("number"),
                .string("integer"),
                .string("boolean"),
                .string("object"),
                .string("array"),
                .string("null")
            ]
            return ["type": .array(types)]
        }
    }
}

// MARK: - ToolRegistry

/// A registry for managing available tools.
///
/// ToolRegistry provides thread-safe tool registration and lookup.
/// Use it to manage the set of tools available to an agent.
///
/// Example:
/// ```swift
/// // Note: CalculatorTool is only available on Apple platforms
/// let registry = ToolRegistry(tools: [DateTimeTool(), StringTool()])
/// let result = try await registry.execute(toolNamed: "datetime", arguments: ["format": "iso8601"])
/// ```
public actor ToolRegistry {
    // MARK: Public

    /// Gets all registered tools.
    public var allTools: [any AnyJSONTool] {
        Array(tools.values)
    }

    /// Gets all tool names.
    public var toolNames: [String] {
        Array(tools.keys)
    }

    /// Gets all tool definitions.
    public var definitions: [ToolDefinition] {
        tools.values.map { ToolDefinition(from: $0) }
    }

    /// The number of registered tools.
    public var count: Int {
        tools.count
    }

    /// Creates an empty tool registry.
    public init() {}

    /// Creates a tool registry with the given tools.
    /// - Parameter tools: The initial tools to register.
    public init(tools: [any AnyJSONTool]) {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    /// Registers a tool.
    /// - Parameter tool: The tool to register.
    public func register(_ tool: any AnyJSONTool) {
        tools[tool.name] = tool
    }

    /// Registers a typed tool by bridging it to `AnyJSONTool`.
    public func register<T: Tool>(_ tool: T) {
        tools[tool.name] = AnyJSONToolAdapter(tool)
    }

    /// Registers multiple tools.
    /// - Parameter newTools: The tools to register.
    public func register(_ newTools: [any AnyJSONTool]) {
        for tool in newTools {
            tools[tool.name] = tool
        }
    }

    /// Unregisters a tool by name.
    /// - Parameter name: The name of the tool to unregister.
    public func unregister(named name: String) {
        tools.removeValue(forKey: name)
    }

    /// Gets a tool by name.
    /// - Parameter name: The tool name.
    /// - Returns: The tool, or nil if not found.
    public func tool(named name: String) -> (any AnyJSONTool)? {
        tools[name]
    }

    /// Returns true if a tool with the given name is registered.
    /// - Parameter name: The tool name.
    /// - Returns: True if the tool exists.
    public func contains(named name: String) -> Bool {
        tools[name] != nil
    }

    /// Executes a tool by name with the given arguments.
    /// - Parameters:
    ///   - name: The name of the tool to execute.
    ///   - arguments: The arguments to pass to the tool.
    ///   - agent: Optional agent executing the tool (for guardrail validation).
    ///   - context: Optional agent context for guardrail validation.
    /// - Returns: The result of the tool execution.
    /// - Throws: `AgentError.toolNotFound` if the tool doesn't exist,
    ///           `AgentError.toolExecutionFailed` if execution fails,
    ///           `GuardrailError` if guardrails are triggered,
    ///           or `CancellationError` if the task is cancelled.
    public func execute(
        toolNamed name: String,
        arguments: [String: SendableValue],
        agent: (any Agent)? = nil,
        context: AgentContext? = nil,
        hooks: (any RunHooks)? = nil
    ) async throws -> SendableValue {
        // Check for cancellation before proceeding
        try Task.checkCancellation()

        guard let tool = tools[name] else {
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
            // Notify hooks for any error (guardrail, execution, or otherwise)
            if let agent, let hooks {
                await hooks.onError(context: context, agent: agent, error: error)
            }

            // Re-throw original error or wrap it
            if let agentError = error as? AgentError {
                throw agentError
            } else if error is CancellationError {
                throw error
            } else if let guardrailError = error as? GuardrailError {
                throw guardrailError
            } else {
                throw AgentError.toolExecutionFailed(
                    toolName: name,
                    underlyingError: error.localizedDescription
                )
            }
        }
    }

    // MARK: Private

    private var tools: [String: any AnyJSONTool] = [:]
}
