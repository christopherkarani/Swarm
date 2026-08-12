// MacroDeclarations.swift
// Swarm Framework
//
// Public macro declarations for Swarm.
// These macros significantly reduce boilerplate when creating tools and agents.

// MARK: - @Tool Macro

/// A macro that generates Tool protocol conformance for a struct.
///
/// The `@Tool` macro eliminates boilerplate when creating tools by:
/// - Generating `name` property from the type name
/// - Using the macro argument as `description`
/// - Collecting `@Parameter` properties into the `parameters` array
/// - Generating `execute(arguments:)` wrapper that extracts typed values
///
/// ## Basic Usage
///
/// ```swift
/// @Tool("Calculates mathematical expressions")
/// struct CalculatorTool {
///     @Parameter("The mathematical expression to evaluate")
///     var expression: String
///
///     func execute() async throws -> Double {
///         // expression is automatically available as a typed property
///         // Parse and evaluate the expression...
///         return 42.0
///     }
/// }
/// ```
///
/// ## With Optional Parameters
///
/// ```swift
/// @Tool("Gets weather information for a location")
/// struct WeatherTool {
///     @Parameter("City name to get weather for")
///     var location: String
///
///     @Parameter("Temperature units", default: "celsius")
///     var units: String = "celsius"
///
///     @Parameter("Include forecast", default: false)
///     var includeForecast: Bool = false
///
///     func execute() async throws -> String {
///         // All parameters are available as typed properties
///         return "72°F in \(location)"
///     }
/// }
/// ```
///
/// ## With Enum Choices
///
/// ```swift
/// @Tool("Formats text output")
/// struct FormatTool {
///     @Parameter("Text to format")
///     var text: String
///
///     @Parameter("Output format", oneOf: ["json", "xml", "plain"])
///     var format: String
///
///     func execute() async throws -> String {
///         switch format {
///         case "json": return formatAsJSON(text)
///         case "xml": return formatAsXML(text)
///         default: return text
///         }
///     }
/// }
/// ```
///
/// ## Generated Code
///
/// The macro generates:
/// - `let name: String` - Derived from type name (lowercased, "Tool" suffix removed)
/// - `let description: String` - From the macro argument
/// - `let parameters: [ToolParameter]` - From `@Parameter` annotated properties
/// - `init()` - If not already present
/// - `execute(arguments:)` - Wrapper that extracts parameters and calls your execute()
/// - `Input` - Codable input struct with all @Parameter properties
/// - `Output` - Typealias for your execute() return type
/// - `execute(_:)` - Typed execute conforming to the Tool protocol
/// - `Tool`, `AnyJSONTool`, and `Sendable` conformance
///
/// ## Requirements
///
/// - Must be applied to a struct
/// - Must have an `execute()` method (can be async throws)
/// - Parameters should be annotated with `@Parameter`
@attached(
    member,
    names: named(name), named(description), named(parameters), named(init), named(execute), named(_userExecute),
    named(Input), named(Output)
)
@attached(extension, conformances: Tool, Sendable)
public macro Tool(_ description: String) = #externalMacro(module: "SwarmMacros", type: "ToolMacro")

// MARK: - @Parameter Macro

/// A macro that marks a property as a tool parameter.
///
/// Use `@Parameter` to declare parameters for tools created with `@Tool`.
/// The macro captures the parameter's description, type, default value, and constraints.
///
/// ## Basic Usage
///
/// ```swift
/// @Parameter("Description of the parameter")
/// var paramName: String
/// ```
///
/// ## With Default Value
///
/// ```swift
/// @Parameter("Temperature units to use", default: "celsius")
/// var units: String = "celsius"
/// ```
///
/// ## With Enum Choices
///
/// ```swift
/// @Parameter("Output format", oneOf: ["json", "xml", "text"])
/// var format: String
/// ```
///
/// ## Type Mapping
///
/// | Swift Type | Tool Parameter Type |
/// |------------|---------------------|
/// | `String` | `.string` |
/// | `Int` | `.int` |
/// | `Double` | `.double` |
/// | `Bool` | `.bool` |
/// | `[T]` | `.array(elementType: ...)` |
/// | `Optional<T>` | Same as T, marked optional |
///
/// ## Parameters
///
/// - `_`: The parameter description (first unlabeled argument)
/// - `default`: Optional default value
/// - `oneOf`: Optional array of allowed string values
@attached(peer)
public macro Parameter(
    _ description: String,
    default defaultValue: Any? = nil,
    oneOf options: [String]? = nil
) = #externalMacro(module: "SwarmMacros", type: "ParameterMacro")

// MARK: - @AgentActor Macro

/// Generates a complete LegacyAgent implementation from an actor with a process() method.
///
/// ## Parameters
/// - `instructions`: The system instructions for the agent (required).
/// - `generateBuilder`: Whether to generate a Builder class (default: true).
///
/// ## Example
///
/// ```swift
/// @AgentActor(instructions: "You are a helpful assistant", generateBuilder: true)
/// actor MyAgent {
///     // Provide tools as AnyJSONTool (dynamic ABI tools), e.g. tools made with `@Tool`.
///     // For typed tools (`Tool`), use the generated Builder which bridges automatically.
///     let tools: [any AnyJSONTool] = [CalculatorTool()]
///
///     func process(_ input: String) async throws -> String {
///         return "Response to: \(input)"
///     }
/// }
///
/// // With builder:
/// let agent = MyAgent.Builder()
///     .addTool(CalculatorTool())
///     .configuration(.default)
///     .build()
/// ```
@attached(
    member,
    names: named(tools), named(instructions), named(configuration), named(memory), named(inferenceProvider),
    named(tracer), named(_memory), named(_defaultMemory), named(resolvedMemory), named(makeDefaultMemory),
    named(_inferenceProvider), named(_tracer), named(isCancelled), named(lastTokenUsage), named(init), named(run), named(stream),
    named(cancel), named(Builder)
)
@attached(extension, conformances: AgentRuntime)
public macro AgentActor(
    instructions: String,
    generateBuilder: Bool = true
) = #externalMacro(module: "SwarmMacros", type: "AgentMacro")

/// A macro that generates LegacyAgent protocol conformance for an actor.
///
/// The `@AgentActor` macro reduces boilerplate when creating agents by:
/// - Generating all LegacyAgent protocol property requirements
/// - Creating a standard initializer
/// - Implementing `run()`, `stream()`, and `cancel()` methods
///
/// ## Basic Usage
///
/// ```swift
/// @AgentActor("You are a helpful assistant that answers questions.")
/// actor AssistantAgent {
///     func process(_ input: String) async throws -> String {
///         // Your custom processing logic
///         return "Response to: \(input)"
///     }
/// }
/// ```
///
/// ## With Custom Tools
///
/// ```swift
/// @AgentActor("You are a math assistant.")
/// actor MathAgent {
///     func process(_ input: String) async throws -> String {
///         // Process with tools available
///         return "Calculated result"
///     }
/// }
///
/// let agent = MathAgent.Builder()
///     .addTool(CalculatorTool())
///     .addTool(DateTimeTool())
///     .build()
/// ```
///
/// ## Generated Code
///
/// The macro generates:
/// - `let tools: [any AnyJSONTool]` - Default empty array (override if needed)
/// - `let instructions: String` - From macro argument
/// - `let configuration: AgentConfiguration` - Default configuration
/// - `var memory: (any Memory)?` - Optional memory
/// - `var inferenceProvider: (any InferenceProvider)?` - Optional provider
/// - `var tracer: (any Tracer)?` - Optional tracer
/// - `var lastTokenUsage: TokenUsage?` - Set from `process` to forward usage
/// - `init(...)` - Standard initializer with all parameters
/// - `run(_ input:session:observer:)` - Calls your `process()` method
/// - `stream(_ input:session:observer:)` - Wraps run() in tracked async stream
/// - `cancel()` - Cancellation support
/// - `LegacyAgent` conformance
///
/// ## Requirements
///
/// - Must be applied to an actor
/// - Should have a `process(_ input: String) async throws -> String` method
@attached(
    member,
    names: named(tools), named(instructions), named(configuration), named(memory), named(inferenceProvider),
    named(tracer), named(_memory), named(_defaultMemory), named(resolvedMemory), named(makeDefaultMemory),
    named(_inferenceProvider), named(_tracer), named(isCancelled), named(lastTokenUsage), named(init), named(run), named(stream),
    named(cancel), named(Builder)
)
@attached(extension, conformances: AgentRuntime)
public macro AgentActor(_ instructions: String) = #externalMacro(module: "SwarmMacros", type: "AgentMacro")

// MARK: - @Traceable Macro

/// A macro that adds automatic tracing/observability to tools.
///
/// When applied to a Tool struct, `@Traceable` generates a `executeWithTracing`
/// method that wraps execution with trace events for observability.
///
/// ## Usage
///
/// ```swift
/// @Traceable
/// struct WeatherTool: Tool {
///     // ... normal Tool implementation
/// }
///
/// // Then use with a tracer:
/// let result = try await tool.executeWithTracing(
///     arguments: args,
///     tracer: myTracer
/// )
/// ```
///
/// ## Generated Code
///
/// Generates `executeWithTracing(arguments:tracer:)` that:
/// - Records TraceEvent at start (type: .toolCall)
/// - Records duration and result on success (type: .toolResult)
/// - Records error information on failure (type: .error)
@attached(peer, names: named(executeWithTracing))
public macro Traceable() = #externalMacro(module: "SwarmMacros", type: "TraceableMacro")

// MARK: - #Prompt Macro

/// A freestanding macro for type-safe prompt string building.
///
/// The `#Prompt` macro validates string interpolations at compile time
/// and provides a type-safe way to build prompts.
///
/// ## Usage
///
/// ```swift
/// let prompt = #Prompt("You are \(role). Please help with: \(task)")
///
/// // Multi-line prompts
/// let systemPrompt = #Prompt("""
///     You are \(agentRole).
///     Available tools: \(toolNames).
///     User query: \(userInput)
///     """)
/// ```
///
/// ## Features
///
/// - Compile-time validation of interpolations
/// - Type checking for interpolated values
/// - Clear error messages for invalid syntax
@freestanding(expression)
public macro Prompt(_ content: String) -> PromptString = #externalMacro(
    module: "SwarmMacros",
    type: "PromptMacro"
)

// MARK: - PromptString

/// A validated prompt string created by the #Prompt macro.
///
/// This type wraps a prompt string that has been validated at compile time,
/// providing type safety for prompt construction.
public struct PromptString: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
    CustomStringConvertible {
    /// The prompt content.
    public let content: String

    /// Names of interpolated values (for debugging/logging).
    public let interpolations: [String]

    /// String description.
    public var description: String { content }

    /// Creates a prompt string with content and interpolation info.
    public init(content: String, interpolations: [String] = []) {
        self.content = content
        self.interpolations = interpolations
    }

    /// Creates a prompt string from a string literal.
    public init(stringLiteral value: String) {
        content = value
        interpolations = []
    }

    /// Creates from a simple string.
    public init(_ string: String) {
        content = string
        interpolations = []
    }
}

// MARK: - #Tool Macro (Inline Tool)

/// Creates an inline tool from a closure with labeled parameters.
///
/// The `#Tool` macro generates a complete `Tool`-conforming struct from a closure,
/// eliminating the need to define a named struct for simple, one-off tools.
///
/// ## Usage
///
/// ```swift
/// let greetTool = #Tool("greet", "Says hello to a person") { (name: String, age: Int) in
///     "Hello, \(name)! You are \(age) years old."
/// }
/// ```
///
/// ## Generated Code
///
/// The macro generates:
/// - A `Codable & Sendable` input struct with one stored property per closure parameter
/// - A `Tool`-conforming struct with `name`, `description`, `parameters`, and `execute(_:)`
/// - An IIFE (immediately invoked closure) that returns the tool instance
///
/// ## Type Mapping
///
/// | Closure parameter type | ToolParameter type |
/// |------------------------|--------------------|
/// | `String` | `.string` |
/// | `Int` | `.int` |
/// | `Double` / `Float` | `.double` |
/// | `Bool` | `.bool` |
/// | `T?` | Same as T, `isRequired: false` |
///
/// ## Relationship to @Tool
///
/// `@Tool` is the attached macro for named, reusable tool structs.
/// `#Tool` is the freestanding expression macro for inline, anonymous tools.
/// They share the name `Tool` but are distinguished by sigil (`@` vs `#`) and
/// parameter count (one string vs two strings), so Swift resolves them unambiguously.
@freestanding(expression)
public macro Tool(
    _ name: String,
    _ description: String
) = #externalMacro(module: "SwarmMacros", type: "InlineToolMacro")

// MARK: - @Builder Macro

/// A macro that generates fluent setter methods for all stored var properties of a struct.
///
/// The `@Builder` macro eliminates boilerplate when creating fluent builder APIs by:
/// - Generating fluent setter methods for each stored var property
/// - Preserving access levels (public/internal)
/// - Following the copy-modify-return pattern for value semantics
///
/// ## Basic Usage
///
/// ```swift
/// @Builder
/// public struct Configuration {
///     public var timeout: Duration
///     public var maxRetries: Int
///     public var enableLogging: Bool
///
///     public init(timeout: Duration = .seconds(30), maxRetries: Int = 3, enableLogging: Bool = true) {
///         self.timeout = timeout
///         self.maxRetries = maxRetries
///         self.enableLogging = enableLogging
///     }
/// }
///
/// // Use it with fluent API:
/// let config = Configuration()
///     .timeout(.seconds(60))
///     .maxRetries(5)
///     .enableLogging(false)
/// ```
///
/// ## Generated Code
///
/// For each stored var property, the macro generates:
/// ```swift
/// @discardableResult
/// public func propertyName(_ value: PropertyType) -> Self {
///     var copy = self
///     copy.propertyName = value
///     return copy
/// }
/// ```
///
/// ## Requirements
///
/// - Must be applied to a struct
/// - Only generates setters for stored `var` properties
/// - Computed properties are ignored
/// - `let` constants are ignored
/// - Preserves the access level of each property
///
/// ## Example with Mixed Properties
///
/// ```swift
/// @Builder
/// public struct AgentConfig {
///     public var temperature: Double  // Generates public setter
///     var maxTokens: Int?              // Generates internal setter
///     public let modelName: String     // Ignored (constant)
///
///     public var isVerbose: Bool {     // Ignored (computed)
///         temperature > 0.5
///     }
/// }
/// ```
@attached(member, names: arbitrary)
public macro Builder() = #externalMacro(module: "SwarmMacros", type: "BuilderMacro")


// MARK: - PromptString String Interpolation

public extension PromptString {
    struct StringInterpolation: StringInterpolationProtocol {
        // MARK: Public

        public init(literalCapacity: Int, interpolationCount: Int) {
            content.reserveCapacity(literalCapacity)
            interpolations.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            content += literal
        }

        public mutating func appendInterpolation(_ value: some Any) {
            content += String(describing: value)
            interpolations.append(String(describing: type(of: value)))
        }

        public mutating func appendInterpolation(_ value: String) {
            content += value
            interpolations.append("String")
        }

        public mutating func appendInterpolation(_ value: Int) {
            content += String(value)
            interpolations.append("Int")
        }

        public mutating func appendInterpolation(_ value: [String]) {
            content += value.joined(separator: ", ")
            interpolations.append("[String]")
        }

        // MARK: Internal

        var content: String = ""
        var interpolations: [String] = []
    }

    init(stringInterpolation: StringInterpolation) {
        content = stringInterpolation.content
        interpolations = stringInterpolation.interpolations
    }
}
