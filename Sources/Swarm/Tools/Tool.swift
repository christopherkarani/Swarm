// Tool.swift
// Swarm Framework
//
// Dynamic (JSON) tool protocol and supporting types for tool execution.

import Foundation

// MARK: - AnyJSONTool

/// The type-erased wire protocol for tool execution.
///
/// `AnyJSONTool` is the internal protocol used by `Agent` and `ToolRegistry` to execute
/// tools without knowing their concrete types. Most users should not conform to this
/// protocol directly — use the ``Tool`` protocol with the `@Tool` macro instead.
///
/// The `@Tool` macro automatically generates conformance to `AnyJSONTool` through an
/// adapter, including:
/// - JSON schema generation from `@Parameter` properties
/// - Type-safe input parsing using `SendableValue`
/// - Output encoding to `SendableValue`
///
/// ## When to Use `AnyJSONTool` Directly
///
/// Only conform to this protocol directly if you need custom tool behavior
/// that cannot be expressed with the macro:
///
/// ```swift
/// struct CustomTool: AnyJSONTool {
///     var name: String { "custom" }
///     var description: String { "Does something custom" }
///     var parameters: [ToolParameter] { [] }
///     var inputGuardrails: [any ToolInputGuardrail] { [] }
///     var outputGuardrails: [any ToolOutputGuardrail] { [] }
///
///     func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
///         // Custom implementation
///         return .string("result")
///     }
/// }
/// ```
///
/// ## Protocol Requirements
///
/// All requirements must be implemented to conform to `AnyJSONTool`:
/// - ``name`` - Unique identifier for the tool
/// - ``description`` - Human-readable description for the LLM
/// - ``parameters`` - Schema for tool arguments
/// - ``execute(arguments:)`` - The actual tool implementation
///
/// - SeeAlso: ``Tool``, ``ToolSchema``, ``ToolParameter``
public protocol AnyJSONTool: Sendable {
    /// The unique name of the tool.
    ///
    /// This name is used:
    /// - In tool schemas sent to LLMs
    /// - As the key in `ToolRegistry`
    /// - In error messages and logging
    ///
    /// Names should be unique within a registry and use `snake_case` for consistency
    /// with LLM training data.
    var name: String { get }

    /// A description of what the tool does.
    ///
    /// This description is included in prompts to help the model understand
    /// when and how to use the tool. Be clear and specific about:
    /// - What the tool does
    /// - When it should be used
    /// - What it returns
    ///
    /// Example: `"Gets the current weather for a given city. Returns temperature
    /// in Fahrenheit and conditions like 'sunny' or 'rainy'."`
    var description: String { get }

    /// The parameters this tool accepts.
    ///
    /// Defines the schema for arguments passed to ``execute(arguments:)``.
    /// Each parameter specifies a name, description, type, and whether it's required.
    ///
    /// - SeeAlso: ``ToolParameter``
    var parameters: [ToolParameter] { get }

    /// Input guardrails for this tool.
    ///
    /// Guardrails validate and potentially transform tool inputs before execution.
    /// They can block malicious inputs, sanitize data, or add safety checks.
    ///
    /// Default: Empty array (no input guardrails)
    ///
    /// - SeeAlso: ``ToolInputGuardrail``
    var inputGuardrails: [any ToolInputGuardrail] { get }

    /// Output guardrails for this tool.
    ///
    /// Guardrails validate and potentially transform tool outputs after execution.
    /// They can filter sensitive data, validate results, or enforce policies.
    ///
    /// Default: Empty array (no output guardrails)
    ///
    /// - SeeAlso: ``ToolOutputGuardrail``
    var outputGuardrails: [any ToolOutputGuardrail] { get }

    /// Execution semantics for this tool.
    ///
    /// Controls how the tool is executed within the Swarm runtime, including
    /// determinism requirements, side effect classification, and caching behavior.
    ///
    /// Default: ``ToolExecutionSemantics/automatic``
    ///
    /// - SeeAlso: ``ToolExecutionSemantics``
    var executionSemantics: ToolExecutionSemantics { get }

    /// Whether this tool is currently enabled.
    ///
    /// When `false`, the tool's schema is excluded from LLM tool-calling prompts
    /// and calls to this tool are rejected with ``AgentError/toolNotFound``.
    /// Use this for:
    /// - Runtime feature flags
    /// - Context-dependent tools
    /// - Debug-only tools
    /// - Gradual rollout of new tools
    ///
    /// Default: `true`
    var isEnabled: Bool { get }

    /// Executes the tool with the given arguments.
    ///
    /// This is the core method that implements the tool's logic. Arguments are
    /// passed as a dictionary of `SendableValue` to allow JSON-compatible dynamic typing.
    ///
    /// - Parameter arguments: The arguments passed to the tool, keyed by parameter name.
    ///                        These are validated against ``parameters`` before this method is called.
    /// - Returns: The result of the tool execution as a `SendableValue`.
    /// - Throws: ``AgentError/toolExecutionFailed`` for execution failures,
    ///          ``AgentError/invalidToolArguments`` for validation failures,
    ///          or any custom error from the tool implementation.
    ///
    /// ## Example Implementation
    ///
    /// ```swift
    /// func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
    ///     let city = requiredString("city", from: arguments)
    ///     let units = optionalString("units", from: arguments) ?? "fahrenheit"
    ///
    ///     let weather = try await fetchWeather(for: city, units: units)
    ///     return .dictionary([
    ///         "temperature": .int(weather.temp),
    ///         "conditions": .string(weather.conditions)
    ///     ])
    /// }
    /// ```
    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}

// MARK: - AnyJSONTool Protocol Extensions

public extension AnyJSONTool {
    /// Creates a ``ToolSchema`` from this tool.
    ///
    /// The schema represents the tool's interface in a format suitable for
    /// LLM providers and can be serialized to JSON.
    ///
    /// - Returns: A ``ToolSchema`` containing the tool's metadata.
    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            parameters: parameters,
            executionSemantics: executionSemantics
        )
    }

    /// Default input guardrails (none).
    var inputGuardrails: [any ToolInputGuardrail] { [] }

    /// Default output guardrails (none).
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    /// Default: tool is always enabled.
    var isEnabled: Bool { true }

    /// Default semantics preserve existing runtime behavior and let higher layers
    /// fall back to their own policies when a tool does not opt into explicit metadata.
    var executionSemantics: ToolExecutionSemantics { .automatic }

    /// Validates that the given arguments match this tool's parameters.
    ///
    /// Checks that all required parameters are present and that values
    /// match the expected types.
    ///
    /// - Parameter arguments: The arguments to validate.
    /// - Throws: ``AgentError/invalidToolArguments`` if validation fails.
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
    /// Normalization includes:
    /// - Applying default values for missing optional parameters
    /// - Coercing string representations of numbers/booleans
    /// - Validating the final result
    ///
    /// - Parameter arguments: The raw arguments passed to the tool.
    /// - Returns: A normalized arguments dictionary suitable for execution.
    /// - Throws: ``AgentError/invalidToolArguments`` if normalization fails.
    func normalizeArguments(_ arguments: [String: SendableValue]) throws -> [String: SendableValue] {
        try ToolArgumentProcessor.normalize(
            toolName: name,
            parameters: parameters,
            arguments: arguments
        )
    }

    /// Gets a required string argument or throws.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - arguments: The arguments dictionary.
    /// - Returns: The string value.
    /// - Throws: ``AgentError/invalidToolArguments`` if missing or wrong type.
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
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - arguments: The arguments dictionary.
    ///   - defaultValue: The default value if not present.
    /// - Returns: The string value or default.
    func optionalString(_ key: String, from arguments: [String: SendableValue], default defaultValue: String? = nil) -> String? {
        arguments[key]?.stringValue ?? defaultValue
    }
}

// MARK: - Tool (Typed Protocol)

/// The user-facing protocol for creating type-safe tools.
///
/// `Tool` is the primary developer-facing API for defining tools in Swarm.
/// Unlike ``AnyJSONTool``, which uses dynamic `SendableValue` dictionaries,
/// `Tool` uses strongly-typed `Codable` structs for input and output.
///
/// ## Using the `@Tool` Macro
///
/// The recommended way to create a tool is with the `@Tool` macro, which
/// automatically generates:
/// - ``name`` and ``description`` from the struct name and doc comments
/// - ``parameters`` schema from `@Parameter` property wrappers
/// - Conformance to ``AnyJSONTool`` through a synthesized adapter
///
/// ```swift
/// @Tool
/// struct GetWeather {
///     @Parameter(description: "City name, e.g. 'San Francisco'")
///     let city: String
///
///     @Parameter(description: "Temperature units")
///     let units: TemperatureUnit = .fahrenheit
///
///     func execute() async throws -> WeatherResult {
///         // Implementation
///     }
/// }
/// ```
///
/// ## Manual Conformance
///
/// For cases where the macro is insufficient, conform manually:
///
/// ```swift
/// struct CalculateMortgage: Tool {
///     struct Input: Codable, Sendable {
///         let principal: Double
///         let rate: Double
///         let years: Int
///     }
///
///     struct Output: Codable, Sendable {
///         let monthlyPayment: Double
///         let totalInterest: Double
///     }
///
///     let name = "calculate_mortgage"
///     let description = "Calculate monthly mortgage payments"
///
///     var parameters: [ToolParameter] {
///         [
///             ToolParameter(name: "principal", description: "Loan amount", type: .double),
///             ToolParameter(name: "rate", description: "Annual interest rate", type: .double),
///             ToolParameter(name: "years", description: "Loan term in years", type: .int)
///         ]
///     }
///
///     func execute(_ input: Input) async throws -> Output {
///         let r = input.rate / 12 / 100
///         let n = Double(input.years * 12)
///         let payment = input.principal * (r * pow(1 + r, n)) / (pow(1 + r, n) - 1)
///         return Output(monthlyPayment: payment, totalInterest: payment * n - input.principal)
///     }
/// }
/// ```
///
/// ## Type Bridging
///
/// The framework automatically bridges `Tool` to ``AnyJSONTool`` using
/// `AnyJSONToolAdapter`. This allows typed tools to be used interchangeably
/// with dynamic tools in `ToolRegistry` and `Agent`.
///
/// - SeeAlso: ``AnyJSONTool``, ``ToolParameter``, ``@Tool``
public protocol Tool: Sendable {
    /// The input type for this tool.
    ///
    /// Must conform to `Codable` for JSON deserialization and `Sendable`
    /// for concurrency safety. The `@Tool` macro synthesizes this from
    /// the struct's properties.
    associatedtype Input: Codable & Sendable

    /// The output type for this tool.
    ///
    /// Must conform to `Encodable` for JSON serialization and `Sendable`
    /// for concurrency safety. Return values are encoded to `SendableValue`
    /// for transport across the runtime boundary.
    associatedtype Output: Encodable & Sendable

    /// The unique name of the tool.
    ///
    /// Used in tool schemas and as the identifier in `ToolRegistry`.
    /// Should be unique and use `snake_case`.
    var name: String { get }

    /// A description of what the tool does.
    ///
    /// Used in prompts to help the model understand tool usage.
    /// Be specific about what the tool does and returns.
    var description: String { get }

    /// The parameters this tool accepts (provider-facing schema).
    ///
    /// Defines the JSON schema for the tool's input. The `@Tool` macro
    /// generates this from `@Parameter` property wrappers.
    var parameters: [ToolParameter] { get }

    /// Input guardrails for this tool.
    ///
    /// Validate and transform inputs before execution.
    ///
    /// Default: Empty array
    var inputGuardrails: [any ToolInputGuardrail] { get }

    /// Output guardrails for this tool.
    ///
    /// Validate and transform outputs after execution.
    ///
    /// Default: Empty array
    var outputGuardrails: [any ToolOutputGuardrail] { get }

    /// Execution semantics for this tool.
    ///
    /// Controls runtime behavior including determinism and caching.
    ///
    /// Default: ``ToolExecutionSemantics/automatic``
    var executionSemantics: ToolExecutionSemantics { get }

    /// Executes the tool with a strongly-typed input.
    ///
    /// - Parameter input: The decoded input value containing all arguments.
    /// - Returns: The tool's output, which will be encoded to `SendableValue`.
    /// - Throws: Any error from the tool implementation.
    func execute(_ input: Input) async throws -> Output
}

public extension Tool {
    /// Default input guardrails (none).
    var inputGuardrails: [any ToolInputGuardrail] { [] }

    /// Default output guardrails (none).
    var outputGuardrails: [any ToolOutputGuardrail] { [] }

    /// Default execution semantics.
    var executionSemantics: ToolExecutionSemantics { .automatic }

    /// Creates a ``ToolSchema`` from this tool.
    ///
    /// The schema represents the tool's interface for LLM providers.
    var schema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            parameters: parameters,
            executionSemantics: executionSemantics
        )
    }
}

// MARK: - ToolArgumentProcessor

/// Shared argument validation + normalization logic for `AnyJSONTool`.
private enum ToolArgumentProcessor {
    // MARK: Internal

    /// Maximum recursion depth for nested object/array parameters to prevent stack overflow.
    static let maxDepth = 50

    static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws {
        try validate(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil, depth: 0)
    }

    static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws -> [String: SendableValue] {
        try normalize(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil, depth: 0)
    }

    // MARK: Private

    private static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?,
        depth: Int
    ) throws {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(pathPrefix ?? "root")"
            )
        }

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
            try validateValue(toolName: toolName, value: value, expected: param.type, path: fullPath, depth: depth)
        }
    }

    private static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?,
        depth: Int
    ) throws -> [String: SendableValue] {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(pathPrefix ?? "root")"
            )
        }

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
            normalized[param.name] = try coerceValue(toolName: toolName, value: value, expected: param.type, path: fullPath, depth: depth)
        }

        // Validate after applying defaults + coercion
        try validate(toolName: toolName, parameters: parameters, arguments: normalized, pathPrefix: pathPrefix, depth: depth)
        return normalized
    }

    private static func validateValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String,
        depth: Int = 0
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
            case .double,
                 .int:
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
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            try validate(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path, depth: depth + 1)

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
        path: String,
        depth: Int = 0
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
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }
            return .array(coerced)

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try normalize(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path, depth: depth + 1)
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

/// Describes a single parameter that a tool accepts.
///
/// `ToolParameter` defines the schema for one argument in a tool's input.
/// It specifies the parameter's name, description, type, and whether it's required.
///
/// ## Basic Usage
///
/// Create parameters for simple types like strings, integers, and booleans:
///
/// ```swift
/// let cityParam = ToolParameter(
///     name: "city",
///     description: "The city name, e.g. 'San Francisco'",
///     type: .string
/// )
///
/// let limitParam = ToolParameter(
///     name: "limit",
///     description: "Maximum number of results",
///     type: .int,
///     isRequired: false,
///     defaultValue: .int(10)
/// )
/// ```
///
/// ## Complex Types
///
/// Define arrays and nested objects:
///
/// ```swift
/// // Array of strings
/// let tagsParam = ToolParameter(
///     name: "tags",
///     description: "Filter tags",
///     type: .array(elementType: .string)
/// )
///
/// // Nested object
/// let addressParam = ToolParameter(
///     name: "address",
///     description: "Mailing address",
///     type: .object(properties: [
///         ToolParameter(name: "street", description: "Street address", type: .string),
///         ToolParameter(name: "city", description: "City", type: .string),
///         ToolParameter(name: "zipCode", description: "ZIP code", type: .string)
///     ])
/// )
/// ```
///
/// ## Enumerations
///
/// Use `oneOf` for parameters that accept specific values:
///
/// ```swift
/// let unitsParam = ToolParameter(
///     name: "units",
///     description: "Temperature units",
///     type: .oneOf(["celsius", "fahrenheit"]),
///     isRequired: false,
///     defaultValue: .string("fahrenheit")
/// )
/// ```
///
/// - SeeAlso: ``ToolSchema``, ``AnyJSONTool``
public struct ToolParameter: Sendable, Equatable {
    /// The type of a tool parameter.
    ///
    /// `ParameterType` defines what kind of value a parameter accepts,
    /// from simple scalars to complex nested structures.
    ///
    /// ## Simple Types
    /// - ``string`` - Text values
    /// - ``int`` - Whole numbers
    /// - ``double`` - Floating point numbers
    /// - ``bool`` - Boolean values
    /// - ``any`` - Any JSON-compatible value
    ///
    /// ## Complex Types
    /// - ``array(elementType:)`` - Ordered list of values
    /// - ``object(properties:)`` - Nested object with defined properties
    /// - ``oneOf([String])`` - String enum with specific allowed values
    indirect public enum ParameterType: Sendable, Equatable, CustomStringConvertible {
        /// A text string value.
        case string

        /// An integer value.
        case int

        /// A floating-point number.
        case double

        /// A boolean value (`true` or `false`).
        case bool

        /// An ordered array of values.
        ///
        /// - Parameter elementType: The type of each element in the array.
        case array(elementType: ParameterType)

        /// A nested object with defined properties.
        ///
        /// - Parameter properties: The parameters that define the object's structure.
        case object(properties: [ToolParameter])

        /// A string that must be one of the specified values.
        ///
        /// - Parameter options: The allowed string values (case-insensitive matching).
        case oneOf([String])

        /// Any JSON-compatible value (minimal type checking).
        case any

        /// A human-readable description of this type.
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
    }

    /// The name of the parameter.
    ///
    /// Used as the key in the arguments dictionary passed to tool execution.
    /// Should be descriptive and use `snake_case` for consistency.
    public let name: String

    /// A description of the parameter.
    ///
    /// Explains what this parameter represents and how it should be used.
    /// This description is included in tool schemas sent to LLMs.
    public let description: String

    /// The type of the parameter.
    ///
    /// Defines what kind of value this parameter accepts and how it should be validated.
    ///
    /// - SeeAlso: ``ParameterType``
    public let type: ParameterType

    /// Whether this parameter is required.
    ///
    /// When `true`, the parameter must be provided in tool calls.
    /// When `false`, the parameter is optional and may be omitted.
    ///
    /// Default: `true`
    public let isRequired: Bool

    /// The default value for this parameter, if any.
    ///
    /// Used when a parameter is optional (`isRequired = false`) and not provided.
    /// The value must be compatible with the parameter's `type`.
    public let defaultValue: SendableValue?

    /// Creates a new tool parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name (used as dictionary key in arguments).
    ///   - description: A human-readable description for LLM tool schemas.
    ///   - type: The expected type of the parameter value.
    ///   - isRequired: Whether the parameter must be provided. Default: `true`.
    ///   - defaultValue: The value to use when the parameter is omitted. Default: `nil`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let queryParam = ToolParameter(
    ///     name: "query",
    ///     description: "Search query string",
    ///     type: .string
    /// )
    ///
    /// let countParam = ToolParameter(
    ///     name: "count",
    ///     description: "Number of results to return",
    ///     type: .int,
    ///     isRequired: false,
    ///     defaultValue: .int(10)
    /// )
    /// ```
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

// MARK: - ToolSchema

/// Describes a tool interface in a provider-friendly, schema-first format.
///
/// `ToolSchema` represents the complete interface of a tool — its name, description,
/// and parameter definitions — in a format suitable for serialization and transmission
/// to LLM providers.
///
/// ## Usage
///
/// Tool schemas are typically created from ``AnyJSONTool`` or ``Tool`` conforming types:
///
/// ```swift
/// let tool = GetWeatherTool()
/// let schema = tool.schema
/// ```
///
/// Or created manually for dynamic tool generation:
///
/// ```swift
/// let schema = ToolSchema(
///     name: "dynamic_search",
///     description: "Search across multiple sources",
///     parameters: [
///         ToolParameter(name: "query", description: "Search terms", type: .string),
///         ToolParameter(
///             name: "source",
///             description: "Where to search",
///             type: .oneOf(["web", "news", "images"]),
///             isRequired: false,
///             defaultValue: .string("web")
///         )
///     ],
///     executionSemantics: .deterministic
/// )
/// ```
///
/// ## Serialization
///
/// `ToolSchema` conforms to `Sendable` and `Equatable` for safe concurrent use.
/// The structure can be converted to JSON for provider APIs using appropriate
/// encoding strategies.
///
/// - SeeAlso: ``ToolParameter``, ``AnyJSONTool``, ``Tool``
public struct ToolSchema: Sendable, Equatable {
    /// The unique name of the tool.
    ///
    /// Used to identify the tool in tool registries and LLM tool calls.
    public let name: String

    /// A description of what the tool does.
    ///
    /// Helps LLMs understand when and how to use the tool.
    public let description: String

    /// The parameters this tool accepts.
    ///
    /// Defines the structure and types of arguments expected by the tool.
    /// An empty array indicates the tool takes no arguments.
    ///
    /// - SeeAlso: ``ToolParameter``
    public let parameters: [ToolParameter]

    /// Execution semantics for this tool.
    ///
    /// Controls how the Swarm runtime handles tool execution,
    /// including caching, determinism, and side effect classification.
    ///
    /// Default: ``ToolExecutionSemantics/automatic``
    ///
    /// - SeeAlso: ``ToolExecutionSemantics``
    public let executionSemantics: ToolExecutionSemantics

    /// Creates a new tool schema.
    ///
    /// - Parameters:
    ///   - name: The unique tool identifier.
    ///   - description: Human-readable description for LLM prompts.
    ///   - parameters: Schema definitions for tool arguments.
    ///   - executionSemantics: Runtime behavior configuration.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let weatherSchema = ToolSchema(
    ///     name: "get_weather",
    ///     description: "Get current weather conditions for a location",
    ///     parameters: [
    ///         ToolParameter(name: "city", description: "City name", type: .string),
    ///         ToolParameter(
    ///             name: "units",
    ///             description: "Temperature units",
    ///             type: .oneOf(["celsius", "fahrenheit"]),
    ///             isRequired: false,
    ///             defaultValue: .string("fahrenheit")
    ///         )
    ///     ],
    ///     executionSemantics: .deterministic
    /// )
    /// ```
    public init(
        name: String,
        description: String,
        parameters: [ToolParameter],
        executionSemantics: ToolExecutionSemantics = .automatic
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.executionSemantics = executionSemantics
    }
}

// MARK: - FunctionTool

/// A closure-based tool for inline tool creation without dedicated structs.
///
/// `FunctionTool` enables quick tool definition using closures, ideal for
/// simple one-off tools that don't warrant a dedicated struct conforming to
/// ``AnyJSONTool`` or ``Tool``.
///
/// ## Basic Usage
///
/// Create a tool with a simple closure:
///
/// ```swift
/// let getWeather = FunctionTool(
///     name: "get_weather",
///     description: "Gets weather for a city"
/// ) { args in
///     let city = try args.require("city", as: String.self)
///     return .string("72°F in \(city)")
/// }
/// ```
///
/// ## With Explicit Parameters
///
/// Define a schema for better LLM integration:
///
/// ```swift
/// let search = FunctionTool(
///     name: "search",
///     description: "Search the web",
///     parameters: [
///         ToolParameter(name: "query", description: "Search query", type: .string),
///         ToolParameter(
///             name: "limit",
///             description: "Max results",
///             type: .int,
///             isRequired: false,
///             defaultValue: .int(10)
///         )
///     ]
/// ) { args in
///     let query = try args.require("query", as: String.self)
///     let limit = args.int("limit", default: 10)
///     // Perform search...
///     return .array([.string("Result 1"), .string("Result 2")])
/// }
/// ```
///
/// ## Registration
///
/// Function tools can be registered like any other tool:
///
/// ```swift
/// let registry = try ToolRegistry(tools: [getWeather, search])
/// let result = try await registry.execute(
///     toolNamed: "get_weather",
///     arguments: ["city": .string("Paris")]
/// )
/// ```
///
/// - SeeAlso: ``ToolArguments``, ``AnyJSONTool``, ``ToolRegistry``
public struct FunctionTool: AnyJSONTool, Sendable {
    /// The unique name of the tool.
    public let name: String

    /// A description of what the tool does.
    public let description: String

    /// The parameters this tool accepts.
    public let parameters: [ToolParameter]

    /// Execution semantics for this tool.
    public let executionSemantics: ToolExecutionSemantics

    /// Creates a function tool with a closure handler.
    ///
    /// - Parameters:
    ///   - name: The unique name of the tool (used in tool calls).
    ///   - description: A description of what the tool does (used in LLM prompts).
    ///   - parameters: The parameters this tool accepts. Default: empty array.
    ///   - executionSemantics: Runtime behavior configuration. Default: `.automatic`.
    ///   - handler: The closure that implements the tool logic.
    ///
    /// ## Handler Closure
    ///
    /// The handler receives a ``ToolArguments`` wrapper providing convenient
    /// access to the tool's arguments. It should return a `SendableValue`
    /// representing the tool's output.
    ///
    /// ```swift
    /// FunctionTool(name: "echo", description: "Echoes input") { args in
    ///     let message = try args.require("message", as: String.self)
    ///     return .string("Echo: \(message)")
    /// }
    /// ```
    ///
    /// - SeeAlso: ``ToolArguments``
    public init(
        name: String,
        description: String,
        parameters: [ToolParameter] = [],
        executionSemantics: ToolExecutionSemantics = .automatic,
        handler: @escaping @Sendable (ToolArguments) async throws -> SendableValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.executionSemantics = executionSemantics
        self.handler = handler
    }

    /// Executes the tool with the given arguments.
    ///
    /// This method wraps the arguments in a ``ToolArguments`` struct and
    /// invokes the handler closure.
    ///
    /// - Parameter arguments: The arguments dictionary from the tool call.
    /// - Returns: The result from the handler closure.
    /// - Throws: Any error thrown by the handler.
    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        try await handler(ToolArguments(arguments, toolName: name))
    }

    // MARK: Private

    private let handler: @Sendable (ToolArguments) async throws -> SendableValue
}

// MARK: - ToolArguments

/// A convenience wrapper for extracting typed values from tool arguments.
///
/// `ToolArguments` provides a type-safe interface for accessing the raw
/// `[String: SendableValue]` dictionary passed to tool execution.
///
/// ## Usage
///
/// Use within a ``FunctionTool`` handler or custom ``AnyJSONTool`` implementation:
///
/// ```swift
/// FunctionTool(name: "calculate", description: "Performs math") { args in
///     // Required arguments (throw if missing)
///     let operation = try args.require("operation", as: String.self)
///     let a = try args.require("a", as: Double.self)
///     let b = try args.require("b", as: Double.self)
///
///     // Optional arguments (return nil if missing)
///     let precision = args.optional("precision", as: Int.self)
///
    ///     // Arguments with defaults
///     let roundResult = args.string("round", default: "up")
///
    ///     // Perform calculation...
///     return .double(result)
/// }
/// ```
///
/// ## Type Support
///
/// The following types are supported for extraction:
/// - `String` - Extracts from `.string` values
/// - `Int` - Extracts from `.int` values
/// - `Double` - Extracts from `.double` values
/// - `Bool` - Extracts from `.bool` values
///
/// - SeeAlso: ``FunctionTool``
public struct ToolArguments: Sendable {
    /// The raw arguments dictionary.
    public let raw: [String: SendableValue]

    /// The name of the tool (used in error messages).
    public let toolName: String

    /// Creates a new tool arguments wrapper.
    ///
    /// - Parameters:
    ///   - arguments: The raw arguments dictionary.
    ///   - toolName: The tool name for error reporting.
    public init(_ arguments: [String: SendableValue], toolName: String = "tool") {
        raw = arguments
        self.toolName = toolName
    }

    /// Gets a required argument of the specified type.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - type: The expected type (inferred by default).
    /// - Returns: The typed value.
    /// - Throws: ``AgentError/invalidToolArguments`` if missing or wrong type.
    public func require<T>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = raw[key] else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Missing required argument: \(key)"
            )
        }

        let extracted: Any? = switch value {
        case let .string(s) where type == String.self: s
        case let .int(i) where type == Int.self: i
        case let .double(d) where type == Double.self: d
        case let .bool(b) where type == Bool.self: b
        default: nil
        }

        guard let result = extracted as? T else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Argument '\(key)' is not of type \(T.self)"
            )
        }
        return result
    }

    /// Gets an optional argument of the specified type.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - type: The expected type (inferred by default).
    /// - Returns: The typed value, or `nil` if missing or wrong type.
    public func optional<T>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let value = raw[key] else { return nil }
        return switch value {
        case let .string(s) where type == String.self: s as? T
        case let .int(i) where type == Int.self: i as? T
        case let .double(d) where type == Double.self: d as? T
        case let .bool(b) where type == Bool.self: b as? T
        default: nil
        }
    }

    /// Gets a string argument or returns the default.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - defaultValue: The default if missing or not a string.
    /// - Returns: The string value or default.
    public func string(_ key: String, default defaultValue: String = "") -> String {
        raw[key]?.stringValue ?? defaultValue
    }

    /// Gets an int argument or returns the default.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - defaultValue: The default if missing or not an int.
    /// - Returns: The integer value or default.
    public func int(_ key: String, default defaultValue: Int = 0) -> Int {
        raw[key]?.intValue ?? defaultValue
    }
}

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
        for tool in tools {
            guard self.tools[tool.name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: tool.name)
            }
            self.tools[tool.name] = tool
        }
    }

    /// Creates a tool registry with the given typed tools.
    ///
    /// - Parameter tools: The initial typed tools to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if a tool with the same name already exists.
    public init(tools: [some Tool]) throws {
        for tool in tools {
            let name = tool.name
            guard self.tools[name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: name)
            }
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
        for tool in newTools {
            let name = tool.name
            guard tools[name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: name)
            }
            tools[name] = AnyJSONToolAdapter(tool)
        }
    }

    /// Registers multiple tools.
    ///
    /// - Parameter newTools: The tools to register.
    /// - Throws: ``ToolRegistryError/duplicateToolName`` if any tool name already exists.
    public func register(_ newTools: [any AnyJSONTool]) throws {
        for tool in newTools {
            guard tools[tool.name] == nil else {
                throw ToolRegistryError.duplicateToolName(name: tool.name)
            }
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
    ///           ``AgentError/toolExecutionFailed`` if execution fails,
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
