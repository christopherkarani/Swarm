// Tool.swift
// Swarm Framework
//
// Dynamic (JSON) tool protocol and supporting types for tool execution.

import Foundation

// MARK: - AnyJSONTool

/// The type-erased wire protocol for tool execution.
///
/// `AnyJSONTool` is the public type-erased capability used by `Agent`, `ToolRegistry`,
/// and MCP bridges to execute tools without knowing their concrete types. Most users
/// should author tools with the ``Tool`` protocol and `@Tool` macro; use this protocol
/// directly for custom dynamic tools or interoperability adapters.
///
/// The `@Tool` macro automatically generates conformance to `AnyJSONTool` through an
/// adapter, including:
/// - JSON schema generation from `@Parameter` properties
/// - Type-safe input parsing using `SendableValue`
/// - Output encoding to `SendableValue`
///
/// ## When to Use `AnyJSONTool` Directly
///
/// Conform directly when a tool is dynamic at runtime, comes from an interoperability
/// layer such as MCP, or needs behavior that cannot be expressed with the macro.
/// This is an advanced seam; the type-erased value is also what ``Agent/tools`` and
/// public MCP discovery APIs exchange.
///
/// Example:
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
/// A direct conformance supplies the tool name, description, parameter schema, and
/// ``execute(arguments:)`` implementation. ``inputGuardrails``, ``outputGuardrails``,
/// ``executionSemantics``, and ``isEnabled`` have safe defaults in the protocol
/// extension and can be overridden when an advanced integration needs them.
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
    /// - Throws: ``AgentError/toolFailure(toolName:message:cause:)`` for execution failures,
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
/// - Important: Apple's FoundationModels framework also declares a public
///   `Tool` protocol. When both modules are imported in the same file, qualify
///   the type (`Swarm.Tool` vs `FoundationModels.Tool`) or prefer Swarm's
///   `@Tool` macro / ``AnyJSONTool`` surface. Swarm bridges to Apple's
///   protocol internally via ``FoundationModelsInferenceProvider``.
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

// MARK: - ToolArguments

/// Types that ``ToolArguments/require(_:as:)`` and ``ToolArguments/optional(_:as:)``
/// can extract from a tool-call argument dictionary.
///
/// The built-in lattice is `String`, `Int`, `Double`, and `Bool`. The lattice is
/// open: any `Sendable` type (such as `URL`) can conform by implementing
/// ``extract(from:)``, and a conformance that omits the requirement fails at
/// compile time. Decoding arbitrary `Decodable` payloads still uses
/// unconstrained ``SendableValue/decode()``.
///
/// ## Strict Extraction
///
/// Extraction is exact-case with no coercion: `.int(1)` extracts as `Int` only,
/// never as `Double`, and `.string("1")` never extracts as a number. Apply
/// schema-driven coercion first with ``AnyJSONTool/normalizeArguments(_:)``
/// (backed by `ToolArgumentProcessor`), then extract with ``ToolArguments``.
/// That normalize-then-extract composition keeps LLM-input tolerance in the
/// normalization layer and exactness in the handler layer.
public protocol ToolArgumentValue: Sendable {
    /// Extracts `Self` from a wire value, or returns `nil` when the case does not match.
    ///
    /// Implementations must be exact-case (no numeric or string coercion); the
    /// built-in conformances share the internal strict policy below.
    static func extract(from value: SendableValue) -> Self?
}

/// Strict exact-case extraction shared by the built-in ``ToolArgumentValue`` conformances.
///
/// One policy serves all four lattice types: a value extracts only when its
/// `SendableValue` case matches the requested type exactly.
enum ToolArgumentExtraction {
    static func extract<T>(_: T.Type, from value: SendableValue) -> T? {
        let extracted: Any? = switch value {
        case let .string(s) where T.self == String.self: s
        case let .int(i) where T.self == Int.self: i
        case let .double(d) where T.self == Double.self: d
        case let .bool(b) where T.self == Bool.self: b
        default: nil
        }
        return extracted as? T
    }
}

extension String: ToolArgumentValue {
    public static func extract(from value: SendableValue) -> String? {
        ToolArgumentExtraction.extract(String.self, from: value)
    }
}

extension Int: ToolArgumentValue {
    public static func extract(from value: SendableValue) -> Int? {
        ToolArgumentExtraction.extract(Int.self, from: value)
    }
}

extension Double: ToolArgumentValue {
    public static func extract(from value: SendableValue) -> Double? {
        ToolArgumentExtraction.extract(Double.self, from: value)
    }
}

extension Bool: ToolArgumentValue {
    public static func extract(from value: SendableValue) -> Bool? {
        ToolArgumentExtraction.extract(Bool.self, from: value)
    }
}

/// A convenience wrapper for extracting typed values from tool arguments.
///
/// `ToolArguments` provides a type-safe interface for accessing the raw
/// `[String: SendableValue]` dictionary passed to tool execution.
/// ``require(_:as:)`` and ``optional(_:as:)`` are generic over
/// ``ToolArgumentValue`` only (`String`, `Int`, `Double`, `Bool`).
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
/// Extraction is constrained to ``ToolArgumentValue``:
/// - `String` - Extracts from `.string` values
/// - `Int` - Extracts from `.int` values
/// - `Double` - Extracts from `.double` values
/// - `Bool` - Extracts from `.bool` values
///
/// Custom `Sendable` types can join the lattice by implementing
/// ``ToolArgumentValue/extract(from:)``. Each accessor dispatches to that
/// requirement: ``require(_:as:)`` throws when the key is missing or mistyped,
/// ``optional(_:as:)`` returns `nil` in both cases, and
/// ``optionalValue(_:as:)`` returns `nil` only when the key is missing.
///
/// - SeeAlso: ``FunctionTool``, ``ToolArgumentValue``
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

    /// Gets a required argument of the specified ``ToolArgumentValue`` type.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - type: The expected lattice type (inferred by default).
    /// - Returns: The typed value.
    /// - Throws: ``AgentError/invalidToolArguments`` if missing or wrong type.
    public func require<T: ToolArgumentValue>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = raw[key] else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Missing required argument: \(key)"
            )
        }

        guard let result = T.extract(from: value) else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Argument '\(key)' is not of type \(T.self)"
            )
        }
        return result
    }

    /// Gets an optional argument of the specified ``ToolArgumentValue`` type.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - type: The expected lattice type (inferred by default).
    /// - Returns: The typed value, or `nil` if missing or wrong type.
    public func optional<T: ToolArgumentValue>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let value = raw[key] else { return nil }
        return T.extract(from: value)
    }

    /// Gets an optional argument, throwing when a present value has the wrong type.
    ///
    /// Unlike ``optional(_:as:)``, which conflates "missing" and "mistyped" as
    /// `nil`, this strict optional returns `nil` only when the key is absent.
    ///
    /// - Parameters:
    ///   - key: The argument key.
    ///   - type: The expected lattice type (inferred by default).
    /// - Returns: The typed value, or `nil` if the key is missing.
    /// - Throws: ``AgentError/invalidToolArguments`` if a present value has the wrong type.
    public func optionalValue<T: ToolArgumentValue>(_ key: String, as type: T.Type = T.self) throws -> T? {
        guard let value = raw[key] else { return nil }
        guard let result = T.extract(from: value) else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Argument '\(key)' is not of type \(T.self)"
            )
        }
        return result
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
