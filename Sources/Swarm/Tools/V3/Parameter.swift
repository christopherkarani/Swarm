// Parameter.swift
// Swarm Framework
//
// Property wrapper for declaring tool parameters with descriptions.
// Named ParameterV3 during transition to avoid collision with existing types.

import Foundation

/// Declares a tool parameter with a description for the LLM.
///
/// Use `@ParameterV3` on tool struct properties to describe each parameter:
/// ```swift
/// struct SearchTool: ToolV3 {
///     let name = "search"
///     let description = "Search the web"
///     @ParameterV3("Search query") var query: String
///     @ParameterV3("Max results to return") var limit: Int
///     func call() async throws -> String { "Results for \(query)" }
/// }
/// ```
@propertyWrapper
public struct ParameterV3<Value: Sendable & Codable>: Sendable {
    /// The wrapped value of this parameter.
    public var wrappedValue: Value

    /// Description shown to the LLM.
    public let description: String

    /// Whether this parameter is required.
    public let isRequired: Bool

    /// Access the property wrapper itself for metadata.
    public var projectedValue: ParameterV3<Value> { self }
}

// MARK: - Required parameter initializers (non-optional types)

extension ParameterV3 where Value == String {
    public init(_ description: String) {
        self.description = description
        self.wrappedValue = ""
        self.isRequired = true
    }
}

extension ParameterV3 where Value == Int {
    public init(_ description: String) {
        self.description = description
        self.wrappedValue = 0
        self.isRequired = true
    }
}

extension ParameterV3 where Value == Double {
    public init(_ description: String) {
        self.description = description
        self.wrappedValue = 0.0
        self.isRequired = true
    }
}

extension ParameterV3 where Value == Bool {
    public init(_ description: String) {
        self.description = description
        self.wrappedValue = false
        self.isRequired = true
    }
}

// MARK: - Optional parameter initializer

extension ParameterV3 where Value: ExpressibleByNilLiteral {
    public init(_ description: String) {
        self.description = description
        self.wrappedValue = nil
        self.isRequired = false
    }
}

// MARK: - Default value initializer

extension ParameterV3 {
    public init(_ description: String, default defaultValue: Value) {
        self.description = description
        self.wrappedValue = defaultValue
        self.isRequired = false
    }
}

// MARK: - Metadata extraction protocol

/// Internal protocol for extracting parameter metadata via reflection.
protocol ParameterMetadata {
    var parameterDescription: String { get }
    var parameterSwiftType: Any.Type { get }
    var isRequired: Bool { get }
}

extension ParameterV3: ParameterMetadata {
    var parameterDescription: String { description }
    var parameterSwiftType: Any.Type { Value.self }
}
