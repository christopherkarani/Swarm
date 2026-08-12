// InlineToolMacro.swift
// SwarmMacros
//
// Implementation of the #Tool freestanding expression macro for inline tool creation.

import SwiftDiagnostics
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
        let (closureParams, diagnostics) = extractClosureParams(from: trailingClosure)
        if !diagnostics.isEmpty {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        // ---- Build generated struct names ----
        let capitalizedName = toolName.prefix(1).uppercased() + toolName.dropFirst()
        let inputStructName = "_\(capitalizedName)Input"
        let toolStructName = "_InlineTool_\(toolName)"

        // ---- Rewrite closure body: bare param refs → input.paramName ----
        // Prefer AST-position rewrites over naive regex and avoid SyntaxRewriter
        // subclasses: Swift 6.2 + swift-syntax 602 can fail to link
        // visitationFunc under high parallel job counts (swiftlang/swift-package-manager#9495).
        let paramNames = Set(closureParams.map(\.name))
        let rewrittenBodyText = rewriteBareParamReferences(
            in: trailingClosure.statements,
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
                let isRequired = !param.isOptional
                return "            ToolParameter(name: \"\(param.name)\", description: \"\(param.name)\", type: \(param.schemaLiteral), isRequired: \(isRequired))"
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
        let schemaLiteral: String
    }

    /// Extracts typed parameters from a closure signature `(label: Type, ...)`.
    private static func extractClosureParams(
        from closure: ClosureExprSyntax
    ) -> (params: [ClosureParam], diagnostics: [Diagnostic]) {
        guard let signature = closure.signature,
              let paramClause = signature.parameterClause
        else {
            return ([], [])
        }

        switch paramClause {
        case .parameterClause(let clause):
            var params: [ClosureParam] = []
            var diagnostics: [Diagnostic] = []
            for param in clause.parameters {
                // secondName is the internal label (used in the body); firstName is the external label.
                // For `(name: String)` there is only firstName; for `(ext int: String)`,
                // firstName = "ext", secondName = "int" and the body uses "int".
                let paramName = param.secondName?.text ?? param.firstName.text
                guard let typeAnnotation = param.type else { continue }
                let rawType = typeAnnotation.description.trimmingCharacters(in: .whitespaces)
                switch ParameterTypeMapping.map(typeAnnotation) {
                case let .mapped(mapped):
                    params.append(ClosureParam(
                        name: paramName,
                        swiftType: rawType,
                        isOptional: mapped.isTypeOptional,
                        schemaLiteral: mapped.schemaLiteral
                    ))
                case let .diagnostic(diagnostic):
                    diagnostics.append(diagnostic)
                }
            }
            return (params, diagnostics)

        case .simpleInput(let items):
            // Simple input like `name, age` — no type annotations, default to String
            let stringType = ParameterTypeMapping.parseTypeSyntax("String")
            switch ParameterTypeMapping.map(stringType) {
            case let .mapped(mapped):
                let params = items.map { item in
                    ClosureParam(
                        name: item.name.text,
                        swiftType: "String",
                        isOptional: false,
                        schemaLiteral: mapped.schemaLiteral
                    )
                }
                return (params, [])
            case let .diagnostic(diagnostic):
                return ([], [diagnostic])
            }
        }
    }
}

// MARK: - Parameter rewriting

/// Rewrites bare parameter references like `name` to `input.name` in a closure body
/// so the generated `execute` method reads fields from the input struct.
///
/// Walks the SwiftSyntax tree and rewrites only `DeclReferenceExprSyntax` nodes
/// (not string-literal text, not member names after `.`). The replacement is then
/// applied to the original source by UTF-8 absolute positions so we never depend
/// on `SyntaxRewriter` subclasses (linker flakiness under parallel builds —
/// swiftlang/swift-package-manager#9495).
private func rewriteBareParamReferences(
    in statements: CodeBlockItemListSyntax,
    paramNames: Set<String>
) -> String {
    guard !paramNames.isEmpty else { return statements.description }

    let source = statements.description
    let baseUTF8Offset = statements.position.utf8Offset

    var replacements: [(utf8Offset: Int, utf8Length: Int, replacement: String)] = []
    collectBareParamReplacements(
        Syntax(statements),
        paramNames: paramNames,
        baseUTF8Offset: baseUTF8Offset,
        into: &replacements
    )

    guard !replacements.isEmpty else { return source }

    // Apply from the end so earlier offsets stay valid.
    var result = source
    for entry in replacements.sorted(by: { $0.utf8Offset > $1.utf8Offset }) {
        guard
            let start = utf8Index(in: result, offset: entry.utf8Offset),
            let end = utf8Index(in: result, offset: entry.utf8Offset + entry.utf8Length)
        else {
            continue
        }
        result.replaceSubrange(start..<end, with: entry.replacement)
    }
    return result
}

private func collectBareParamReplacements(
    _ node: Syntax,
    paramNames: Set<String>,
    baseUTF8Offset: Int,
    into replacements: inout [(utf8Offset: Int, utf8Length: Int, replacement: String)]
) {
    if let decl = node.as(DeclReferenceExprSyntax.self),
       paramNames.contains(decl.baseName.text),
       !isMemberAccessName(decl)
    {
        let token = decl.baseName
        let relative = token.positionAfterSkippingLeadingTrivia.utf8Offset - baseUTF8Offset
        let length = token.text.utf8.count
        if relative >= 0, length > 0 {
            replacements.append(
                (
                    utf8Offset: relative,
                    utf8Length: length,
                    replacement: "input.\(token.text)"
                )
            )
        }
    }

    for child in node.children(viewMode: .sourceAccurate) {
        collectBareParamReplacements(
            child,
            paramNames: paramNames,
            baseUTF8Offset: baseUTF8Offset,
            into: &replacements
        )
    }
}

/// True when `node` is the member name of `base.member` (must not become `base.input.member`).
private func isMemberAccessName(_ node: DeclReferenceExprSyntax) -> Bool {
    guard let parent = node.parent else { return false }
    if let member = parent.as(MemberAccessExprSyntax.self) {
        return member.declName.position == node.position
    }
    if parent.is(KeyPathPropertyComponentSyntax.self) {
        return true
    }
    return false
}

private func utf8Index(in string: String, offset: Int) -> String.Index? {
    guard offset >= 0, offset <= string.utf8.count else { return nil }
    let utf8Index = string.utf8.index(string.utf8.startIndex, offsetBy: offset)
    return String.Index(utf8Index, within: string)
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
