// InlineTool.swift
// Swarm Framework
//
// Closure-based inline tool for one-off tool definitions.

import Foundation

/// A closure-based tool for quick, inline tool definitions.
///
/// Use `InlineToolV3` when a full struct is overkill:
/// ```swift
/// AgentV3("helper") {
///     InlineToolV3("greet", "Greets someone") { args in
///         let name = args["name"]?.stringValue ?? "World"
///         return "Hello, \(name)!"
///     }
/// }
/// ```
public struct InlineToolV3: ToolV3 {
    public let name: String
    public let description: String
    private let handler: @Sendable ([String: SendableValue]) async throws -> String

    /// Creates an inline tool with raw argument access.
    ///
    /// - Parameters:
    ///   - name: Tool name (snake_case).
    ///   - description: Description for the LLM.
    ///   - handler: Closure receiving arguments as `[String: SendableValue]`.
    public init(
        _ name: String,
        _ description: String,
        handler: @escaping @Sendable ([String: SendableValue]) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.handler = handler
    }

    /// Creates a simple inline tool with a single string input.
    ///
    /// ```swift
    /// InlineToolV3("echo", "Echoes input") { input in
    ///     "You said: \(input)"
    /// }
    /// ```
    public init(
        _ name: String,
        _ description: String,
        _ handler: @escaping @Sendable (String) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.handler = { args in
            guard let input = args.values.first?.stringValue else {
                throw AgentError.invalidToolArguments(
                    toolName: name,
                    reason: "Expected a string argument"
                )
            }
            return try await handler(input)
        }
    }

    /// Creates a no-argument inline tool.
    ///
    /// ```swift
    /// InlineToolV3("timestamp", "Returns current time") {
    ///     Date().description
    /// }
    /// ```
    public init(
        _ name: String,
        _ description: String,
        _ handler: @escaping @Sendable () async throws -> String
    ) {
        self.name = name
        self.description = description
        self.handler = { _ in try await handler() }
    }

    public func call() async throws -> String {
        try await handler([:])
    }
}
