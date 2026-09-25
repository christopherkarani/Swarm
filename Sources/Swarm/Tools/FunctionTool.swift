// FunctionTool.swift
// Swarm Framework
//
// Closure-based tool for inline tool creation.

import Foundation

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
