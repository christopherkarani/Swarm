// ToolMacro.swift
// SwarmMacros
//
// Implementation of the @Tool macro for generating Tool protocol conformance.

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - ToolMacro

/// The `@Tool` macro generates Tool protocol conformance for a struct.
///
/// Usage:
/// ```swift
/// @Tool("Calculates mathematical expressions")
/// struct CalculatorTool {
///     @Parameter("The expression to evaluate")
///     var expression: String
///
///     func execute() async throws -> Double {
///         // Implementation
///     }
/// }
/// ```
///
/// Generates:
/// - `name` property (derived from type name)
/// - `description` property (from macro argument)
/// - `parameters` array (from @Parameter properties)
/// - `execute(arguments:)` wrapper method
/// - Tool and Sendable conformances
///
/// ## Return Type Encoding
///
/// The macro automatically converts your tool's return type to `SendableValue`:
///
/// - **Primitive types** (String, Int, Double, Bool) are encoded directly
/// - **SendableValue** returns are passed through unchanged
/// - **Void/()** returns become `.null`
/// - **Complex types** (custom structs, enums, etc.) are handled in two ways:
///   1. First, the macro attempts to encode them using `SendableValue(encoding:)`, which uses `Codable`
///   2. If encoding fails, the value is converted to a string using `String(describing:)` as a fallback
///
/// **Important**: The `String(describing:)` fallback means type information is lost. For complex return types:
/// - Ensure your type conforms to `Codable` for proper encoding
/// - Or manually return `SendableValue` from your `execute()` method
/// - Be aware that sensitive data may be exposed in string representations
///
/// Example with complex type:
/// ```swift
/// struct CustomResult: Codable, Sendable {
///     let value: Int
///     let metadata: String
/// }
///
/// @Tool("Returns custom data")
/// struct MyTool {
///     func execute() async throws -> CustomResult {
///         // Will be encoded via Codable automatically
///         return CustomResult(value: 42, metadata: "success")
///     }
/// }
/// ```
public struct ToolMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract the description from macro argument
        guard let description = extractDescription(from: node) else {
            throw MacroError.missingDescription
        }

        // Get the type name
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.onlyApplicableToStruct
        }
        let typeName = structDecl.name.text

        // Derive tool name from type name (snake_case, remove "Tool" suffix)
        let toolName = deriveToolName(from: typeName)

        // Find all @Parameter annotated properties
        let (parameters, diagnostics) = extractParameters(from: declaration)
        if !diagnostics.isEmpty {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        // Generate members
        var members: [DeclSyntax] = []

        // 1. Generate name property
        members.append("""
            public let name: String = "\(raw: toolName)"
            """)

        // 2. Generate description property
        members.append("""
            public let description: String = \(literal: description)
            """)

        // 3. Generate parameters array
        let parametersArray = generateParametersArray(parameters)
        members.append("""
            public let parameters: [ToolParameter] = \(raw: parametersArray)
            """)

        // 4. Generate init if not present
        if !hasInit(in: declaration) {
            members.append("""
                public init() {}
                """)
        }

        // 5. Generate Tool protocol members: Input struct, Output typealias, typed execute
        let userReturnType = extractUserExecuteReturnType(from: declaration)
        let inputStruct = generateInputStruct(parameters: parameters)
        members.append(inputStruct)
        members.append("""
            public typealias Output = \(raw: userReturnType)
            """)
        let typedExecute = generateTypedExecute(parameters: parameters, returnType: userReturnType)
        members.append(typedExecute)

        return members
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only add extension for valid Tool declarations
        // Must be a struct with a description argument and mappable parameters
        guard declaration.is(StructDeclSyntax.self),
              extractDescription(from: node) != nil else {
            return []
        }
        let (_, diagnostics) = extractParameters(from: declaration)
        guard diagnostics.isEmpty else {
            return []
        }
        // Add Tool and Sendable conformance (AnyJSONTool bridging is handled by AnyJSONToolAdapter)
        let toolExtension = try ExtensionDeclSyntax("extension \(type): Tool, Sendable {}")
        return [toolExtension]
    }

    // MARK: - Helper Methods

    /// Extracts the description string from the macro attribute.
    private static func extractDescription(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        return extractStaticStringLiteral(from: stringLiteral)
    }

    /// Derives the tool name from the type name.
    private static func deriveToolName(from typeName: String) -> String {
        var name = typeName
        // Remove "Tool" suffix if present
        if name.hasSuffix("Tool") {
            name = String(name.dropLast(4))
        }
        var output = ""
        for character in name {
            if character.isUppercase {
                if !output.isEmpty {
                    output.append("_")
                }
                output.append(character.lowercased())
            } else {
                output.append(character)
            }
        }
        return output
    }

    /// Extracts @Parameter annotated properties from the declaration.
    private static func extractParameters(
        from declaration: some DeclGroupSyntax
    ) -> (parameters: [ParameterInfo], diagnostics: [Diagnostic]) {
        var parameters: [ParameterInfo] = []
        var diagnostics: [Diagnostic] = []

        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Check for @Parameter attribute
            let parameterAttr = varDecl.attributes.first { attr in
                guard let attr = attr.as(AttributeSyntax.self),
                      let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else {
                    return false
                }
                return identifier.name.text == "Parameter"
            }

            guard let attr = parameterAttr?.as(AttributeSyntax.self) else { continue }

            // Extract parameter info
            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let propertyName = pattern.identifier.text

                let typeSyntax: TypeSyntax
                if let annotated = binding.typeAnnotation?.type {
                    typeSyntax = annotated
                } else {
                    typeSyntax = ParameterTypeMapping.parseTypeSyntax("String")
                }
                let swiftType = typeSyntax.description.trimmingCharacters(in: .whitespaces)

                let paramDescription = extractParameterDescription(from: attr)
                let paramDefault = extractParameterDefault(from: attr)
                let oneOfOptions = extractOneOfOptions(from: attr)
                let defaultExpression = paramDefault ?? binding.initializer?.value
                let defaultValue = defaultExpression?.description

                switch ParameterTypeMapping.map(typeSyntax, oneOf: oneOfOptions) {
                case let .mapped(mapped):
                    var sendableDefault: String?
                    if let defaultExpression {
                        switch ParameterTypeMapping.convertDefault(defaultExpression, type: typeSyntax) {
                        case let .mapped(encoded):
                            sendableDefault = encoded
                        case let .diagnostic(diagnostic):
                            diagnostics.append(diagnostic)
                            continue
                        }
                    }

                    parameters.append(ParameterInfo(
                        name: propertyName,
                        description: paramDescription ?? "Parameter \(propertyName)",
                        swiftType: swiftType,
                        isOptional: mapped.isTypeOptional || defaultValue != nil,
                        typeIsOptional: mapped.isTypeOptional,
                        defaultValue: defaultValue,
                        sendableDefaultLiteral: sendableDefault,
                        schemaLiteral: mapped.schemaLiteral
                    ))

                case let .diagnostic(diagnostic):
                    diagnostics.append(diagnostic)
                }
            }
        }

        return (parameters, diagnostics)
    }

    /// Extracts description from @Parameter attribute.
    private static func extractParameterDescription(from attr: AttributeSyntax) -> String? {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }

        // First unlabeled argument is the description
        for arg in arguments {
            if arg.label == nil,
               let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self) {
                return extractStaticStringLiteral(from: stringLiteral)
            }
        }
        return nil
    }

    /// Extracts default value from @Parameter attribute.
    private static func extractParameterDefault(from attr: AttributeSyntax) -> ExprSyntax? {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }

        for arg in arguments where arg.label?.text == "default" {
            return arg.expression
        }
        return nil
    }

    /// Extracts oneOf options from @Parameter attribute.
    private static func extractOneOfOptions(from attr: AttributeSyntax) -> [String]? {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }

        for arg in arguments {
            if arg.label?.text == "oneOf",
               let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
                var options: [String] = []
                for element in arrayExpr.elements {
                    if let stringLiteral = element.expression.as(StringLiteralExprSyntax.self),
                       let option = extractStaticStringLiteral(from: stringLiteral) {
                        options.append(option)
                    }
                }
                return options
            }
        }
        return nil
    }

    /// Checks if the declaration already has an init.
    private static func hasInit(in declaration: some DeclGroupSyntax) -> Bool {
        for member in declaration.memberBlock.members where member.decl.is(InitializerDeclSyntax.self) {
            return true
        }
        return false
    }

    /// Generates the parameters array code.
    private static func generateParametersArray(_ parameters: [ParameterInfo]) -> String {
        if parameters.isEmpty {
            return "[]"
        }

        let parameterStrings = parameters.map { param -> String in
            let isRequired = !param.isOptional

            var defaultValueStr = ""
            if let sendableDefault = param.sendableDefaultLiteral {
                defaultValueStr = ", defaultValue: \(sendableDefault)"
            }

            return """
                ToolParameter(
                    name: \(stringLiteral(param.name)),
                    description: \(stringLiteral(param.description)),
                    type: \(param.schemaLiteral),
                    isRequired: \(isRequired)\(defaultValueStr)
                )
            """
        }

        return "[\n        " + parameterStrings.joined(separator: ",\n        ") + "\n    ]"
    }

    private static func stringLiteral(_ value: String) -> String {
        String(reflecting: value)
    }

    private static func extractStaticStringLiteral(from stringLiteral: StringLiteralExprSyntax) -> String? {
        let rawDelimiterCount = stringLiteral.openingQuote.text.prefix { $0 == "#" }.count
        var value = ""

        for segment in stringLiteral.segments {
            guard let stringSegment = segment.as(StringSegmentSyntax.self) else {
                return nil
            }
            value += decodeStringLiteralSegment(stringSegment.content.text, rawDelimiterCount: rawDelimiterCount)
        }

        return value
    }

    private static func decodeStringLiteralSegment(_ text: String, rawDelimiterCount: Int) -> String {
        var decoded = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "\\" else {
                decoded.append(character)
                index = text.index(after: index)
                continue
            }

            index = text.index(after: index)
            var hashCount = 0
            var scanIndex = index
            while scanIndex < text.endIndex, text[scanIndex] == "#" {
                hashCount += 1
                scanIndex = text.index(after: scanIndex)
            }

            guard hashCount == rawDelimiterCount, scanIndex < text.endIndex else {
                decoded.append("\\")
                continue
            }

            index = scanIndex
            let escaped = text[index]
            switch escaped {
            case "\"":
                decoded.append("\"")
            case "\\":
                decoded.append("\\")
            case "0":
                decoded.append("\0")
            case "n":
                decoded.append("\n")
            case "r":
                decoded.append("\r")
            case "t":
                decoded.append("\t")
            case "u":
                if decodeUnicodeEscape(from: text, index: &index, into: &decoded) {
                    continue
                }
                decoded += rawEscape(escaped, rawDelimiterCount: rawDelimiterCount)
            default:
                decoded += rawEscape(escaped, rawDelimiterCount: rawDelimiterCount)
            }
            index = text.index(after: index)
        }

        return decoded
    }

    private static func decodeUnicodeEscape(
        from text: String,
        index: inout String.Index,
        into decoded: inout String
    ) -> Bool {
        var scanIndex = text.index(after: index)
        guard scanIndex < text.endIndex, text[scanIndex] == "{" else {
            return false
        }

        scanIndex = text.index(after: scanIndex)
        var hex = ""
        while scanIndex < text.endIndex, text[scanIndex] != "}" {
            hex.append(text[scanIndex])
            scanIndex = text.index(after: scanIndex)
        }

        guard scanIndex < text.endIndex,
              let scalarValue = UInt32(hex, radix: 16),
              let scalar = UnicodeScalar(scalarValue) else {
            return false
        }

        decoded.append(Character(scalar))
        index = text.index(after: scanIndex)
        return true
    }

    private static func rawEscape(_ escaped: Character, rawDelimiterCount: Int) -> String {
        "\\" + String(repeating: "#", count: rawDelimiterCount) + String(escaped)
    }

    // MARK: - Tool Protocol Member Generation

    /// Extracts the return type of the user's execute() method.
    private static func extractUserExecuteReturnType(from declaration: some DeclGroupSyntax) -> String {
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self),
               funcDecl.name.text == "execute",
               funcDecl.signature.parameterClause.parameters.isEmpty {
                if let returnClause = funcDecl.signature.returnClause {
                    return returnClause.type.description.trimmingCharacters(in: .whitespaces)
                }
                return "Void"
            }
        }
        return "Void"
    }

    /// Generates the nested `Input` struct conforming to `Codable & Sendable`.
    private static func generateInputStruct(parameters: [ParameterInfo]) -> DeclSyntax {
        if parameters.isEmpty {
            return """
                public struct Input: Codable, Sendable {
                }
                """
        }

        let properties = parameters.map { param -> String in
            let swiftType: String
            if param.isOptional && !param.typeIsOptional {
                swiftType = param.swiftType + "?"
            } else {
                swiftType = param.swiftType
            }
            if let defaultValue = param.defaultValue {
                return "    public var \(param.name): \(swiftType) = \(defaultValue)"
            } else {
                return "    public var \(param.name): \(swiftType)"
            }
        }.joined(separator: "\n")

        return """
            public struct Input: Codable, Sendable {
            \(raw: properties)
            }
            """
    }

    /// Generates the typed `execute(_ input: Input) async throws -> Output` method.
    private static func generateTypedExecute(parameters: [ParameterInfo], returnType: String) -> DeclSyntax {
        if parameters.isEmpty {
            let conversion = generateTypedReturnConversion(returnType)
            return """
                public func execute(_ input: Input) async throws -> Output {
                    var toolCopy = self
                    \(raw: conversion)
                }
                """
        }

        // For optional params (those with defaults), the Input property is Optional<T>.
        // When assigning back to a non-optional property, use nil-coalescing with the default value.
        let assignments = parameters.map { param -> String in
            // Input property is optional when the schema parameter is optional
            // but the stored Swift type is not already Optional.
            let inputIsOptional = param.isOptional && !param.typeIsOptional
            if inputIsOptional, let defaultValue = param.defaultValue {
                return "toolCopy.\(param.name) = input.\(param.name) ?? \(defaultValue)"
            } else {
                return "toolCopy.\(param.name) = input.\(param.name)"
            }
        }.joined(separator: "\n        ")

        let conversion = generateTypedReturnConversion(returnType)

        return """
            public func execute(_ input: Input) async throws -> Output {
                var toolCopy = self
                \(raw: assignments)
                \(raw: conversion)
            }
            """
    }

    /// Generates the return statement for the typed execute method.
    /// For most types the user's execute() IS the Output, so we just return it directly.
    private static func generateTypedReturnConversion(_ returnType: String) -> String {
        let clean = returnType.trimmingCharacters(in: .whitespaces)
        if clean == "Void" || clean == "()" {
            return "try await toolCopy.execute()"
        }
        return "return try await toolCopy.execute()"
    }
}

// MARK: - ParameterInfo

/// Information about a tool parameter.
struct ParameterInfo {
    let name: String
    let description: String
    let swiftType: String
    let isOptional: Bool
    let typeIsOptional: Bool
    let defaultValue: String?
    let sendableDefaultLiteral: String?
    let schemaLiteral: String
}

// MARK: - MacroError

/// Errors that can occur during macro expansion.
enum MacroError: Error, CustomStringConvertible {
    case missingDescription
    case onlyApplicableToStruct

    var description: String {
        switch self {
        case .missingDescription:
            return "@Tool requires a description string argument"
        case .onlyApplicableToStruct:
            return "@Tool can only be applied to structs"
        }
    }
}
