// ToolParameterBuilder.swift
// Swarm Framework
//
// Result builder DSL for constructing tool parameters declaratively.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - ToolParameterBuilder

/// A result builder for constructing tool parameter arrays with DSL syntax.
///
/// `ToolParameterBuilder` enables a declarative syntax for defining tool parameters,
/// similar to SwiftUI's view builders. It supports conditionals, loops, and optional
/// parameters.
///
/// Example:
/// ```swift
/// struct WeatherTool: Tool {
///     let name = "weather"
///     let description = "Gets weather for a location"
///
///     @ToolParameterBuilder
///     var parameters: [ToolParameter] {
///         Parameter("location", description: "City name", type: .string)
///         Parameter("units", description: "Temperature units", type: .oneOf(["C", "F"]), required: false)
///         if includeTimezone {
///             Parameter("timezone", description: "Timezone offset", type: .int)
///         }
///     }
///
///     func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
///         // Implementation
///     }
/// }
/// ```
@resultBuilder
public struct ToolParameterBuilder {
    /// Builds a parameter array from multiple parameters.
    public static func buildBlock(_ components: ToolParameter...) -> [ToolParameter] {
        components
    }

    /// Builds an empty parameter array for empty builder bodies.
    public static func buildBlock() -> [ToolParameter] {
        []
    }

    /// Builds a parameter array from an array of parameters.
    public static func buildBlock(_ components: [ToolParameter]...) -> [ToolParameter] {
        components.flatMap(\.self)
    }

    /// Builds a parameter array from an optional parameter.
    public static func buildOptional(_ component: [ToolParameter]?) -> [ToolParameter] {
        component ?? []
    }

    /// Builds a parameter array from the first branch of an if-else.
    public static func buildEither(first component: [ToolParameter]) -> [ToolParameter] {
        component
    }

    /// Builds a parameter array from the second branch of an if-else.
    public static func buildEither(second component: [ToolParameter]) -> [ToolParameter] {
        component
    }

    /// Builds a parameter array from a for-in loop.
    public static func buildArray(_ components: [[ToolParameter]]) -> [ToolParameter] {
        components.flatMap(\.self)
    }

    /// Converts a single parameter to an array.
    public static func buildExpression(_ expression: ToolParameter) -> [ToolParameter] {
        [expression]
    }

    /// Passes through an array of parameters.
    public static func buildExpression(_ expression: [ToolParameter]) -> [ToolParameter] {
        expression
    }

    /// Builds from a limited availability check.
    public static func buildLimitedAvailability(_ component: [ToolParameter]) -> [ToolParameter] {
        component
    }

    /// Builds the final result.
    public static func buildFinalResult(_ component: [ToolParameter]) -> [ToolParameter] {
        component
    }
}

// MARK: - Parameter Factory Functions

// swiftlint:disable identifier_name

/// Creates a tool parameter with the specified configuration.
///
/// This is a convenience function for use with `ToolParameterBuilder` that provides
/// a cleaner syntax than the full `ToolParameter` initializer.
///
/// - Parameters:
///   - name: The parameter name.
///   - description: A description of the parameter.
///   - type: The parameter type.
///   - required: Whether the parameter is required. Default: `true`
///   - defaultValue: The default value. Default: `nil`
/// - Returns: A configured `ToolParameter`.
///
/// Example:
/// ```swift
/// @ToolParameterBuilder
/// var parameters: [ToolParameter] {
///     Parameter("query", description: "Search query", type: .string)
///     Parameter("limit", description: "Max results", type: .int, required: false, default: 10)
/// }
/// ```
public func Parameter(
    _ name: String,
    description: String,
    type: ToolParameter.ParameterType,
    required: Bool = true,
    default defaultValue: SendableValue? = nil
) -> ToolParameter {
    ToolParameter(
        name: name,
        description: description,
        type: type,
        isRequired: required,
        defaultValue: defaultValue
    )
}

/// Creates a tool parameter with an integer default value.
///
/// - Parameters:
///   - name: The parameter name.
///   - description: A description of the parameter.
///   - type: The parameter type.
///   - required: Whether the parameter is required. Default: `true`
///   - defaultValue: The default integer value.
/// - Returns: A configured `ToolParameter`.
public func Parameter(
    _ name: String,
    description: String,
    type: ToolParameter.ParameterType,
    required: Bool = true,
    default defaultValue: Int
) -> ToolParameter {
    ToolParameter(
        name: name,
        description: description,
        type: type,
        isRequired: required,
        defaultValue: .int(defaultValue)
    )
}

/// Creates a tool parameter with a string default value.
///
/// - Parameters:
///   - name: The parameter name.
///   - description: A description of the parameter.
///   - type: The parameter type.
///   - required: Whether the parameter is required. Default: `true`
///   - defaultValue: The default string value.
/// - Returns: A configured `ToolParameter`.
public func Parameter(
    _ name: String,
    description: String,
    type: ToolParameter.ParameterType,
    required: Bool = true,
    default defaultValue: String
) -> ToolParameter {
    ToolParameter(
        name: name,
        description: description,
        type: type,
        isRequired: required,
        defaultValue: .string(defaultValue)
    )
}

/// Creates a tool parameter with a boolean default value.
///
/// - Parameters:
///   - name: The parameter name.
///   - description: A description of the parameter.
///   - type: The parameter type.
///   - required: Whether the parameter is required. Default: `true`
///   - defaultValue: The default boolean value.
/// - Returns: A configured `ToolParameter`.
public func Parameter(
    _ name: String,
    description: String,
    type: ToolParameter.ParameterType,
    required: Bool = true,
    default defaultValue: Bool
) -> ToolParameter {
    ToolParameter(
        name: name,
        description: description,
        type: type,
        isRequired: required,
        defaultValue: .bool(defaultValue)
    )
}

/// Creates a tool parameter with a double default value.
///
/// - Parameters:
///   - name: The parameter name.
///   - description: A description of the parameter.
///   - type: The parameter type.
///   - required: Whether the parameter is required. Default: `true`
///   - defaultValue: The default double value.
/// - Returns: A configured `ToolParameter`.
public func Parameter(
    _ name: String,
    description: String,
    type: ToolParameter.ParameterType,
    required: Bool = true,
    default defaultValue: Double
) -> ToolParameter {
    ToolParameter(
        name: name,
        description: description,
        type: type,
        isRequired: required,
        defaultValue: .double(defaultValue)
    )
}

// swiftlint:enable identifier_name

// MARK: - ToolBuilder

/// A result builder for constructing a `ToolCollection` using declarative DSL syntax.
///
/// `ToolBuilder` is the V3 canonical way to supply tools to an `Agent`. The
/// `AnyJSONTool` internal protocol is never exposed — callers work with concrete
/// `Tool` conformers or `any Tool` existentials and receive an opaque
/// `ToolCollection` in return.
///
/// Example:
/// ```swift
/// let agent = try Agent("Be helpful.") {
///     CalculatorTool()
///     WeatherTool()
///     if includeDebug {
///         DebugTool()
///     }
/// }
/// ```
@resultBuilder
public struct ToolBuilder {

    // MARK: - Empty builder body

    /// Returns an empty `ToolCollection` for an empty builder body.
    public static func buildBlock() -> ToolCollection {
        .empty
    }

    // MARK: - Variadic block

    /// Combines multiple `ToolCollection` components into one.
    public static func buildBlock(_ components: ToolCollection...) -> ToolCollection {
        ToolCollection(storage: components.flatMap(\.storage))
    }

    // MARK: - buildExpression overloads

    /// Wraps a concrete `Tool` conformer into a `ToolCollection`.
    ///
    /// The generic parameter preserves the concrete type so the compiler
    /// can produce a properly-typed `AnyJSONToolAdapter<T>` without a cast.
    public static func buildExpression<T: Tool>(_ expression: T) -> ToolCollection {
        ToolCollection(storage: [AnyJSONToolAdapter(expression)])
    }

    /// Wraps an `any Tool` existential into a `ToolCollection`.
    ///
    /// Swift 5.7+ existential opening means the compiler infers the concrete
    /// type `T` when the existential is passed to `bridgeToolToAnyJSON<T: Tool>`.
    public static func buildExpression(_ expression: any Tool) -> ToolCollection {
        ToolCollection(storage: [bridgeToolToAnyJSON(expression)])
    }

    /// Wraps a closure-based ``FunctionTool`` into a `ToolCollection`.
    public static func buildExpression(_ expression: FunctionTool) -> ToolCollection {
        ToolCollection(storage: [expression])
    }

    #if canImport(FoundationModels)
        /// Wraps a ``FoundationModelsNativeTool`` into a `ToolCollection`.
        @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public static func buildExpression(_ expression: FoundationModelsNativeTool) -> ToolCollection {
            ToolCollection(storage: [expression])
        }

        /// Wraps a user-authored `FoundationModels.Tool` into a `ToolCollection`.
        ///
        /// Prefer this when constructing ``InferenceProvider/foundationModelsOwningToolLoop()``.
        @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        public static func buildExpression<T: FoundationModels.Tool>(_ expression: T) -> ToolCollection {
            ToolCollection(storage: [FoundationModelsNativeTool(expression)])
        }
    #endif

    #if canImport(Darwin)
        /// Wraps the built-in calculator tool into a `ToolCollection`.
        public static func buildExpression(_ expression: CalculatorTool) -> ToolCollection {
            ToolCollection(storage: [expression])
        }
    #endif

    /// Wraps the built-in date/time tool into a `ToolCollection`.
    public static func buildExpression(_ expression: DateTimeTool) -> ToolCollection {
        ToolCollection(storage: [expression])
    }

    /// Wraps the built-in string utility tool into a `ToolCollection`.
    public static func buildExpression(_ expression: StringTool) -> ToolCollection {
        ToolCollection(storage: [expression])
    }

    /// Wraps an internal `AnyJSONTool` value into a `ToolCollection`.
    ///
    /// Used by framework-internal code that already holds `any AnyJSONTool`
    /// (e.g. built-in tool registries). Not part of the public V3 API surface.
    internal static func buildExpression(_ expression: any AnyJSONTool) -> ToolCollection {
        ToolCollection(storage: [expression])
    }

    /// Wraps an internal `[any AnyJSONTool]` array into a `ToolCollection`.
    ///
    /// Used by framework-internal code that already holds a typed tool array.
    /// Not part of the public V3 API surface.
    internal static func buildExpression(_ expression: [any AnyJSONTool]) -> ToolCollection {
        ToolCollection(storage: expression)
    }

    /// Wraps an array of `any Tool` existentials into a `ToolCollection`.
    public static func buildExpression(_ expression: [any Tool]) -> ToolCollection {
        ToolCollection(storage: expression.map { bridgeToolToAnyJSON($0) })
    }

    // MARK: - Control-flow support

    /// Returns the component when the `if` condition is true, or `.empty` when absent.
    public static func buildOptional(_ component: ToolCollection?) -> ToolCollection {
        component ?? .empty
    }

    /// Returns the first branch of an `if`/`else` expression.
    public static func buildEither(first component: ToolCollection) -> ToolCollection {
        component
    }

    /// Returns the second branch of an `if`/`else` expression.
    public static func buildEither(second component: ToolCollection) -> ToolCollection {
        component
    }

    /// Flattens a `for`-`in` loop of `ToolCollection` values into one collection.
    public static func buildArray(_ components: [ToolCollection]) -> ToolCollection {
        ToolCollection(storage: components.flatMap(\.storage))
    }

    /// Passes through a component produced inside a `#available` / `@available` check.
    public static func buildLimitedAvailability(_ component: ToolCollection) -> ToolCollection {
        component
    }
}
