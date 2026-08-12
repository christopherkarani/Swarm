// ParameterTypeMapping.swift
// SwarmMacros
//
// Syntax-aware Swift type → ToolParameter.ParameterType mapping shared by
// @Tool and #Tool. Unsupported types produce compile errors, never a silent
// `.string` fallback.

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax

// MARK: - Mapped parameter type

/// Result of mapping a Swift parameter type onto a schema literal.
struct MappedParameterType {
    /// Source spelling of `ToolParameter.ParameterType`, e.g. `.string` or
    /// `.array(elementType: .int)`.
    let schemaLiteral: String

    /// True when the Swift type itself is optional (`T?`, `T!`, or `Optional<T>`).
    let isTypeOptional: Bool
}

/// Success or a compiler diagnostic. `Diagnostic` is not `Error`, so this is
/// not `Result`.
enum MappingOutcome<Value> {
    case mapped(Value)
    case diagnostic(Diagnostic)
}

// MARK: - Mapping

enum ParameterTypeMapping {
    /// Parses a type spelling with SwiftParser so callers that only have text
    /// still walk a real `TypeSyntax` tree.
    static func parseTypeSyntax(_ text: String) -> TypeSyntax {
        var parser = Parser(text)
        return TypeSyntax.parse(from: &parser)
    }

    /// Maps `type` to a `ToolParameter.ParameterType` literal.
    ///
    /// `oneOf` is valid only on `String` (including `Optional<String>`).
    /// Optionality is tracked separately and does not affect the schema case.
    static func map(
        _ type: TypeSyntax,
        oneOf: [String]? = nil
    ) -> MappingOutcome<MappedParameterType> {
        let (coreType, isTypeOptional) = stripOptionals(type)

        switch mapCore(coreType) {
        case let .mapped(schemaLiteral):
            if let options = oneOf, !options.isEmpty {
                guard schemaLiteral == ".string" else {
                    return .diagnostic(
                        ToolParameterTypeDiagnostic.oneOfRequiresString(type.trimmedDescription)
                            .diagnostic(at: type)
                    )
                }
                let optionsStr = options.map { stringLiteral($0) }.joined(separator: ", ")
                return .mapped(MappedParameterType(
                    schemaLiteral: ".oneOf([\(optionsStr)])",
                    isTypeOptional: isTypeOptional
                ))
            }
            return .mapped(MappedParameterType(
                schemaLiteral: schemaLiteral,
                isTypeOptional: isTypeOptional
            ))
        case let .failed(error):
            return .diagnostic(error.diagnostic(at: type))
        }
    }

    /// Encodes a default-value expression as `SendableValue` syntax.
    ///
    /// Unknown types and non-literal array defaults are errors — never silent
    /// string coercion.
    static func convertDefault(
        _ expression: ExprSyntax,
        type: TypeSyntax
    ) -> MappingOutcome<String> {
        let trimmed = expression.trimmedDescription
        if trimmed == "nil" {
            return .mapped("nil")
        }

        let (coreType, _) = stripOptionals(type)
        if let encoded = encodeExpression(expression, as: coreType) {
            return .mapped(encoded)
        }

        return .diagnostic(
            ToolParameterTypeDiagnostic.unencodableDefault(type.trimmedDescription)
                .diagnostic(at: expression)
        )
    }

    // MARK: Core mapping

    private enum CoreError {
        case unsupported(String)
        case dictionary(String)

        func diagnostic(at node: some SyntaxProtocol) -> Diagnostic {
            switch self {
            case let .unsupported(typeName):
                ToolParameterTypeDiagnostic.unsupportedType(typeName).diagnostic(at: node)
            case let .dictionary(typeName):
                ToolParameterTypeDiagnostic.dictionaryType(typeName).diagnostic(at: node)
            }
        }
    }

    private enum CoreOutcome {
        case mapped(String)
        case failed(CoreError)
    }

    private static func mapCore(_ type: TypeSyntax) -> CoreOutcome {
        let type = unwrapAttributed(type)

        if let array = type.as(ArrayTypeSyntax.self) {
            return mapArrayElement(array.element, spelled: type.trimmedDescription)
        }

        if type.is(DictionaryTypeSyntax.self) {
            return .failed(.dictionary(type.trimmedDescription))
        }

        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return mapIdentifier(identifier, spelled: type.trimmedDescription)
        }

        return .failed(.unsupported(type.trimmedDescription))
    }

    private static func mapIdentifier(
        _ identifier: IdentifierTypeSyntax,
        spelled: String
    ) -> CoreOutcome {
        let name = identifier.name.text
        let genericArgs = genericTypeArguments(of: identifier)

        switch name {
        case "Array":
            guard let element = genericArgs.first, genericArgs.count == 1 else {
                return .failed(.unsupported(spelled))
            }
            return mapArrayElement(element, spelled: spelled)

        case "Dictionary":
            return .failed(.dictionary(spelled))

        case "String" where genericArgs.isEmpty:
            return .mapped(".string")
        case "Int" where genericArgs.isEmpty:
            return .mapped(".int")
        case "Double" where genericArgs.isEmpty, "Float" where genericArgs.isEmpty:
            return .mapped(".double")
        case "Bool" where genericArgs.isEmpty:
            return .mapped(".bool")

        default:
            return .failed(.unsupported(spelled))
        }
    }

    private static func mapArrayElement(
        _ element: TypeSyntax,
        spelled: String
    ) -> CoreOutcome {
        let (coreElement, _) = stripOptionals(element)
        switch mapCore(coreElement) {
        case let .mapped(elementLiteral):
            return .mapped(".array(elementType: \(elementLiteral))")
        case let .failed(error):
            // Preserve dictionary errors so `[String: Int]` nested in an array
            // still names the dictionary, not the outer array spelling.
            switch error {
            case .dictionary:
                return .failed(error)
            case .unsupported:
                return .failed(.unsupported(spelled))
            }
        }
    }

    // MARK: Optionality

    /// Unwraps `T?`, `T!`, and `Optional<T>` (including nested / attributed forms).
    static func stripOptionals(_ type: TypeSyntax) -> (core: TypeSyntax, isOptional: Bool) {
        var current = unwrapAttributed(type)
        var isOptional = false

        while true {
            if let optional = current.as(OptionalTypeSyntax.self) {
                isOptional = true
                current = unwrapAttributed(optional.wrappedType)
                continue
            }
            if let iuo = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                isOptional = true
                current = unwrapAttributed(iuo.wrappedType)
                continue
            }
            if let identifier = current.as(IdentifierTypeSyntax.self),
               identifier.name.text == "Optional" {
                let args = genericTypeArguments(of: identifier)
                guard let wrapped = args.first, args.count == 1 else {
                    break
                }
                isOptional = true
                current = unwrapAttributed(wrapped)
                continue
            }
            break
        }

        return (current, isOptional)
    }

    private static func unwrapAttributed(_ type: TypeSyntax) -> TypeSyntax {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return unwrapAttributed(attributed.baseType)
        }
        return type
    }

    private static func genericTypeArguments(of identifier: IdentifierTypeSyntax) -> [TypeSyntax] {
        guard let clause = identifier.genericArgumentClause else { return [] }
        return clause.arguments.compactMap { argument in
            switch argument.argument {
            case let .type(type):
                return type
            default:
                return nil
            }
        }
    }

    // MARK: Default-value encoding

    private static func encodeExpression(_ expression: ExprSyntax, as type: TypeSyntax) -> String? {
        let trimmed = expression.trimmedDescription
        let type = unwrapAttributed(type)

        if let array = type.as(ArrayTypeSyntax.self) {
            return encodeArrayLiteral(expression, elementType: array.element)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self),
           identifier.name.text == "Array",
           let element = genericTypeArguments(of: identifier).first {
            return encodeArrayLiteral(expression, elementType: element)
        }

        switch scalarName(type) {
        case "String":
            return ".string(\(trimmed))"
        case "Int":
            return ".int(\(trimmed))"
        case "Double", "Float":
            return ".double(\(trimmed))"
        case "Bool":
            return ".bool(\(trimmed))"
        default:
            return nil
        }
    }

    private static func encodeArrayLiteral(
        _ expression: ExprSyntax,
        elementType: TypeSyntax
    ) -> String? {
        guard let arrayExpr = expression.as(ArrayExprSyntax.self) else {
            return nil
        }
        let (coreElement, _) = stripOptionals(elementType)
        var encoded: [String] = []
        encoded.reserveCapacity(arrayExpr.elements.count)
        for element in arrayExpr.elements {
            guard let value = encodeExpression(element.expression, as: coreElement) else {
                return nil
            }
            encoded.append(value)
        }
        return ".array([\(encoded.joined(separator: ", "))])"
    }

    private static func scalarName(_ type: TypeSyntax) -> String? {
        unwrapAttributed(type).as(IdentifierTypeSyntax.self)?.name.text
    }

    private static func stringLiteral(_ value: String) -> String {
        String(reflecting: value)
    }
}

// MARK: - Diagnostics

enum ToolParameterTypeDiagnostic: DiagnosticMessage {
    case unsupportedType(String)
    case dictionaryType(String)
    case unencodableDefault(String)
    case missingTypeAnnotation(String)
    case oneOfRequiresString(String)

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        switch self {
        case .unsupportedType:
            MessageID(domain: "SwarmMacros", id: "unsupportedParameterType")
        case .dictionaryType:
            MessageID(domain: "SwarmMacros", id: "unsupportedDictionaryParameter")
        case .unencodableDefault:
            MessageID(domain: "SwarmMacros", id: "unencodableParameterDefault")
        case .missingTypeAnnotation:
            MessageID(domain: "SwarmMacros", id: "missingParameterTypeAnnotation")
        case .oneOfRequiresString:
            MessageID(domain: "SwarmMacros", id: "oneOfRequiresString")
        }
    }

    var message: String {
        switch self {
        case let .unsupportedType(typeName):
            """
            Unsupported parameter type '\(typeName)'. Supported types are String, Int, Double, Float, Bool, arrays of those types, and Optional of those types. Use @Parameter(oneOf:) for string enums. For advanced schemas, write a FunctionTool instead.
            """
        case let .dictionaryType(typeName):
            """
            Dictionary parameter type '\(typeName)' is not supported. ToolParameter.ParameterType has no homogeneous-dictionary case; `.object(properties:)` requires known keys. Use explicit object properties, a JSON-string parameter, or FunctionTool with `.any`.
            """
        case let .unencodableDefault(typeName):
            """
            Cannot encode a default value for parameter type '\(typeName)'. Supported types are String, Int, Double, Float, Bool, arrays of those types, and Optional of those types. For advanced schemas, write a FunctionTool instead.
            """
        case let .missingTypeAnnotation(name):
            """
            Parameter '\(name)' is missing a type annotation. Supported types are String, Int, Double, Float, Bool, arrays of those types, and Optional of those types.
            """
        case let .oneOfRequiresString(typeName):
            """
            @Parameter(oneOf:) requires a String parameter (or Optional<String>). Parameter type '\(typeName)' cannot be a string enum.
            """
        }
    }

    func diagnostic(at node: some SyntaxProtocol) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: self)
    }
}
