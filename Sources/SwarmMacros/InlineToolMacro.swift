// InlineToolMacro.swift
// SwarmMacros
//
// Implementation of the #Tool freestanding expression macro for inline tool creation.

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - InlineToolMacro

/// The `#Tool` freestanding expression macro creates an inline Tool-conforming value
/// from a closure with labeled parameters.
///
/// Usage:
/// ```swift
/// #Tool("greet", "Says hello") { (name: String, age: Int) in
///     "Hello, \(name)! You are \(age)."
/// }
/// ```
///
/// Generates an anonymous IIFE that defines a Codable input struct and a
/// Tool-conforming struct, then returns an instance of it.
public struct InlineToolMacro: ExpressionMacro {

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // ---- Extract name (1st argument) ----
        let arguments = Array(node.arguments)
        guard arguments.count >= 1,
              let nameLiteral = arguments[0].expression.as(StringLiteralExprSyntax.self),
              let nameSegment = nameLiteral.segments.first?.as(StringSegmentSyntax.self)
        else {
            throw InlineToolMacroError.missingName
        }

        let toolName = nameSegment.content.text

        // ---- Extract description (2nd argument) ----
        guard arguments.count >= 2,
              let descLiteral = arguments[1].expression.as(StringLiteralExprSyntax.self),
              let descSegment = descLiteral.segments.first?.as(StringSegmentSyntax.self)
        else {
            throw InlineToolMacroError.missingDescription
        }

        let toolDescription = descSegment.content.text

        // ---- Extract trailing closure ----
        guard let trailingClosure = node.trailingClosure else {
            throw InlineToolMacroError.missingClosure
        }

        // ---- Parse closure parameters ----
        let closureParams = extractClosureParams(from: trailingClosure)

        // ---- Build generated struct names ----
        let capitalizedName = toolName.prefix(1).uppercased() + toolName.dropFirst()
        let inputStructName = "_\(capitalizedName)Input"
        let toolStructName = "_InlineTool_\(toolName)"

        // ---- Rewrite closure body: bare param refs → input.paramName ----
        // Avoid SyntaxRewriter subclasses: Swift 6.2 + swift-syntax 602 can fail to
        // link visitationFunc depending on parallel job count (swiftlang/swift-package-manager#9495).
        let paramNames = Set(closureParams.map(\.name))
        let rewrittenBodyText = rewriteBareParamReferences(
            in: trailingClosure.statements.description,
            paramNames: paramNames
        )

        // Normalise statement indentation to 12 spaces (3 levels × 4 spaces) so
        // the execute body sits cleanly inside `func execute(...) { }`.
        let executeLines = rewrittenBodyText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let executeBody = executeLines
            .map { "            \($0)" }
            .joined(separator: "\n")

        // ---- Build Input struct members (8-space indent inside the struct) ----
        let inputMembers = closureParams
            .map { "        let \($0.name): \($0.swiftType)" }
            .joined(separator: "\n")

        // ---- Build ToolParameter array ----
        let parametersArray: String
        if closureParams.isEmpty {
            parametersArray = "[]"
        } else {
            let entries = closureParams.map { param -> String in
                let paramType = mapSwiftTypeToParameterType(param.swiftType)
                let isRequired = !param.isOptional
                return "            ToolParameter(name: \"\(param.name)\", description: \"\(param.name)\", type: \(paramType), isRequired: \(isRequired))"
            }.joined(separator: ",\n")
            parametersArray = "[\n\(entries)\n        ]"
        }

        // ---- Assemble Input struct body ----
        // For an empty struct, produce `{}`. For non-empty, produce `{\n    members\n    }`.
        let inputBody: String
        if inputMembers.isEmpty {
            inputBody = ""
        } else {
            inputBody = "\n\(inputMembers)\n    "
        }

        // ---- Assemble the IIFE expression ----
        let generated: ExprSyntax = """
        {
            struct \(raw: inputStructName): Codable, Sendable {\(raw: inputBody)}
            struct \(raw: toolStructName): Tool, Sendable {
                typealias Input = \(raw: inputStructName)
                typealias Output = String
                let name = \(literal: toolName)
                let description = \(literal: toolDescription)
                let parameters: [ToolParameter] = \(raw: parametersArray)
                func execute(_ input: \(raw: inputStructName)) async throws -> String {
        \(raw: executeBody)
                }
            }
            return \(raw: toolStructName)()
        }()
        """

        return generated
    }

    // MARK: - Private Helpers

    /// Represents a single closure parameter.
    private struct ClosureParam {
        let name: String
        let swiftType: String
        let isOptional: Bool
    }

    /// Extracts typed parameters from a closure signature `(label: Type, ...)`.
    private static func extractClosureParams(from closure: ClosureExprSyntax) -> [ClosureParam] {
        guard let signature = closure.signature,
              let paramClause = signature.parameterClause
        else {
            return []
        }

        switch paramClause {
        case .parameterClause(let clause):
            return clause.parameters.compactMap { param in
                // secondName is the internal label (used in the body); firstName is the external label.
                // For `(name: String)` there is only firstName; for `(ext int: String)`,
                // firstName = "ext", secondName = "int" and the body uses "int".
                let paramName = param.secondName?.text ?? param.firstName.text
                guard let typeAnnotation = param.type else { return nil }
                let rawType = typeAnnotation.description.trimmingCharacters(in: .whitespaces)
                let isOptional = typeAnnotation.is(OptionalTypeSyntax.self)
                    || typeAnnotation.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                return ClosureParam(name: paramName, swiftType: rawType, isOptional: isOptional)
            }

        case .simpleInput(let items):
            // Simple input like `name, age` — no type annotations, default to String
            return items.map { item in
                ClosureParam(name: item.name.text, swiftType: "String", isOptional: false)
            }
        }
    }

    /// Maps a Swift type string to its ToolParameter.ParameterType literal.
    private static func mapSwiftTypeToParameterType(_ swiftType: String) -> String {
        let cleanType = swiftType
            .replacingOccurrences(of: "Optional<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespaces)

        switch cleanType {
        case "String": return ".string"
        case "Int":    return ".int"
        case "Double", "Float": return ".double"
        case "Bool":   return ".bool"
        default:       return ".string"
        }
    }
}

// MARK: - Parameter rewriting

/// Rewrites bare parameter references like `name` to `input.name` in a closure body
/// so the generated `execute` method reads fields from the input struct.
///
/// Uses string rewriting rather than `SyntaxRewriter` to avoid a known Swift 6.2
/// linker failure on private `SyntaxRewriter.visitationFunc` (swift-package-manager#9495).
private func rewriteBareParamReferences(in source: String, paramNames: Set<String>) -> String {
    guard !paramNames.isEmpty else { return source }

    // Longest names first so shorter params do not partially rewrite longer ones.
    let ordered = paramNames.sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
    var result = source
    for name in ordered {
        let pattern = #"(?<![.\w])"# + NSRegularExpression.escapedPattern(for: name) + #"(?!\w)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = regex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "input.\(name)"
        )
    }
    return result
}

// MARK: - InlineToolMacroError

/// Errors thrown during `InlineToolMacro` expansion (converted to compiler diagnostics).
enum InlineToolMacroError: Error, CustomStringConvertible {
    case missingName
    case missingDescription
    case missingClosure

    var description: String {
        switch self {
        case .missingName:
            return "#Tool requires a name string as the first argument"
        case .missingDescription:
            return "#Tool requires a description string as the second argument"
        case .missingClosure:
            return "#Tool requires a trailing closure"
        }
    }
}
