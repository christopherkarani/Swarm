// IntentToolMacro.swift
// SwarmMacros
//
// Implementation of the @IntentTool and @AgentIntent macros, which bridge Swarm
// tools and agents to Apple's App Intents (Siri, Shortcuts, Spotlight, and
// Apple Intelligence).

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - IntentToolMacro

/// The `@IntentTool` macro generates a nested `Intent` type conforming to
/// `AppIntents.AppIntent` for a struct that is also annotated with `@Tool`.
///
/// Usage:
/// ```swift
/// @Tool("Gets the current weather for a city")
/// @IntentTool("Get Weather")
/// struct WeatherTool {
///     @Parameter("City name") var city: String
///     func execute() async throws -> String { "Sunny in \(city)" }
/// }
///
/// // WeatherTool.Intent is now an AppIntent for Siri and Shortcuts.
/// ```
///
/// The generated intent:
/// - mirrors every `@Parameter` as an `AppIntents.IntentParameter`,
/// - reuses the `@Tool` description as the intent description,
/// - runs the tool through Swarm's tool registry (so guardrails, argument
///   normalization, and `isEnabled` all apply), and
/// - returns the rendered tool output as both a Shortcuts value and a Siri
///   dialog.
public struct IntentToolMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                IntentMacroDiagnostic.intentToolRequiresStruct.diagnostic(at: node),
            ])
        }
        if structDecl.genericParameterClause != nil {
            throw DiagnosticsError(diagnostics: [
                IntentMacroDiagnostic.genericToolUnsupported.diagnostic(at: node),
            ])
        }
        guard let toolAttribute = findAttribute(named: "Tool", in: structDecl.attributes),
              let toolDescription = ToolMacro.extractDescription(from: toolAttribute)
        else {
            throw DiagnosticsError(diagnostics: [
                IntentMacroDiagnostic.missingToolAttribute.diagnostic(at: node),
            ])
        }

        let typeName = structDecl.name.text
        let arguments = IntentMacroArguments(node)
        let title = arguments.string(at: 0, label: nil) ?? deriveTitle(fromTypeName: typeName)
        let description = arguments.string(at: nil, label: "description") ?? toolDescription

        // @Tool reports its own parameter diagnostics; if it fails, emit nothing
        // here so the user sees one clear error instead of two.
        let (parameters, toolDiagnostics) = ToolMacro.extractParameters(from: declaration)
        if !toolDiagnostics.isEmpty {
            return []
        }

        var intentParameters: [IntentParameterSpec] = []
        var diagnostics: [Diagnostic] = []
        for parameter in parameters {
            switch IntentParameterSpec.make(from: parameter) {
            case let .success(spec):
                intentParameters.append(spec)
            case let .failure(message):
                diagnostics.append(message.diagnostic(at: node))
            }
        }
        if !diagnostics.isEmpty {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        var body: [String] = []
        body.append("public static let title: LocalizedStringResource = \(literal(title))")
        body.append(
            "public static let description: AppIntents.IntentDescription = "
                + "AppIntents.IntentDescription(\(literal(description)))"
        )
        for spec in intentParameters {
            body.append(spec.propertyDeclaration)
        }
        for spec in intentParameters {
            if let provider = spec.optionsProviderDeclaration {
                body.append(provider)
            }
        }
        body.append("public init() {\n}")

        var performLines: [String] = ["var swarmArguments: [String: SendableValue] = [:]"]
        for spec in intentParameters {
            performLines.append(
                "swarmArguments[\(literal(spec.name))] = SwarmIntentArgument.encode(self.\(spec.name))"
            )
        }
        performLines.append(
            "let swarmOutput = try await SwarmIntentBridge.run(\(typeName)(), arguments: swarmArguments)"
        )
        performLines.append("return .result(value: swarmOutput, dialog: \"\\(swarmOutput)\")")
        body.append(performDeclaration(lines: performLines))

        let intent: DeclSyntax = """
            public struct Intent: AppIntents.AppIntent {
            \(raw: body.map { indent($0) }.joined(separator: "\n\n"))
            }
            """
        return [intent]
    }
}

// MARK: - AgentIntentMacro

/// The `@AgentIntent` macro turns a struct into an `AppIntents.AppIntent` that
/// sends a natural-language request to a Swarm agent.
///
/// Usage:
/// ```swift
/// @AgentIntent("Plan a Trip", description: "Plans trips using live weather")
/// struct PlanTripIntent {
///     static func makeAgent() throws -> some AgentRuntime {
///         try Agent("You plan weekend trips.") { WeatherTool() }
///     }
/// }
/// ```
///
/// The struct must declare `static func makeAgent()` returning an
/// `AgentRuntime`. It may be `async` and/or `throws`.
public struct AgentIntentMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                IntentMacroDiagnostic.agentIntentRequiresStruct.diagnostic(at: node),
            ])
        }
        let arguments = IntentMacroArguments(node)
        guard let title = arguments.string(at: 0, label: nil) else {
            throw DiagnosticsError(diagnostics: [
                IntentMacroDiagnostic.missingTitle.diagnostic(at: node),
            ])
        }
        guard let factory = findMakeAgent(in: declaration) else {
            throw DiagnosticsError(diagnostics: [
                IntentMacroDiagnostic.missingMakeAgent.diagnostic(at: node),
            ])
        }

        let description = arguments.string(at: nil, label: "description")
        let promptTitle = arguments.string(at: nil, label: "promptTitle") ?? "Request"

        let effects = factory.signature.effectSpecifiers
        var call = "Self.makeAgent()"
        if effects?.asyncSpecifier != nil {
            call = "await " + call
        }
        if effects?.throwsClause != nil {
            call = "try " + call
        }

        var members: [DeclSyntax] = []
        members.append("public static let title: LocalizedStringResource = \(raw: literal(title))")
        if let description {
            members.append(
                """
                public static let description: AppIntents.IntentDescription = \
                AppIntents.IntentDescription(\(raw: literal(description)))
                """
            )
        }
        members.append(
            """
            @AppIntents.IntentParameter(title: \(raw: literal(promptTitle)))
            public var prompt: String
            """
        )
        members.append("public init() {\n}")
        members.append(DeclSyntax(stringLiteral: performDeclaration(lines: [
            "let swarmAgent = \(call)",
            "let swarmOutput = try await SwarmIntentBridge.run(agent: swarmAgent, prompt: self.prompt)",
            "return .result(value: swarmOutput, dialog: \"\\(swarmOutput)\")",
        ])))
        return members
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self),
              IntentMacroArguments(node).string(at: 0, label: nil) != nil,
              findMakeAgent(in: declaration) != nil
        else {
            return []
        }
        return [try ExtensionDeclSyntax("extension \(type): AppIntents.AppIntent {}")]
    }

    private static func findMakeAgent(in declaration: some DeclGroupSyntax) -> FunctionDeclSyntax? {
        for member in declaration.memberBlock.members {
            guard let function = member.decl.as(FunctionDeclSyntax.self),
                  function.name.text == "makeAgent",
                  function.signature.parameterClause.parameters.isEmpty,
                  function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) })
            else {
                continue
            }
            return function
        }
        return nil
    }
}

// MARK: - Intent parameter mapping

/// How one `@Parameter` on a Swarm tool is exposed as an App Intents parameter.
struct IntentParameterSpec {
    let name: String
    let title: String
    let description: String
    /// Swift type of the `IntentParameter` property (Float is widened to Double).
    let intentType: String
    let defaultExpression: String?
    let options: [String]?

    var optionsProviderName: String {
        name.prefix(1).uppercased() + name.dropFirst() + "Options"
    }

    var propertyDeclaration: String {
        var arguments = ["title: \(literal(title))", "description: \(literal(description))"]
        if let defaultExpression {
            arguments.append("default: \(defaultExpression)")
        }
        if options != nil {
            arguments.append("optionsProvider: \(optionsProviderName)()")
        }
        return """
            @AppIntents.IntentParameter(\(arguments.joined(separator: ", ")))
            public var \(name): \(intentType)
            """
    }

    var optionsProviderDeclaration: String? {
        guard let options else { return nil }
        let values = options.map(literal).joined(separator: ", ")
        return """
            public struct \(optionsProviderName): AppIntents.DynamicOptionsProvider {
                public init() {
                }

                public func results() async throws -> [String] {
                    [\(values)]
                }
            }
            """
    }

    enum Outcome {
        case success(IntentParameterSpec)
        case failure(IntentMacroDiagnostic)
    }

    /// Maps a `@Tool` parameter onto an App Intents–supported Swift type.
    ///
    /// App Intents natively supports `String`, `Int`, `Double`, `Bool`, arrays
    /// of those, and optionals of those. `Float` is widened to `Double` (the
    /// value round-trips through `SendableValue.double`). Arrays of optionals
    /// and nested arrays are rejected.
    static func make(from parameter: ParameterInfo) -> Outcome {
        let parsed = ParameterTypeMapping.parseTypeSyntax(parameter.swiftType)
        let (core, isOptional) = ParameterTypeMapping.stripOptionals(parsed)

        guard let coreSpelling = intentCoreType(core) else {
            return .failure(.unsupportedIntentParameter(name: parameter.name, type: parameter.swiftType))
        }

        // `@Tool` structs need an initial value on every stored property, so
        // `var city: String = ""` is usually a placeholder rather than a real
        // default. Treat empty string/array placeholders as "no default" so
        // Siri asks for the value instead of silently running with "".
        let defaultExpression: String?
        if let value = parameter.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !["nil", "\"\"", "[]"].contains(value) {
            defaultExpression = value
        } else {
            defaultExpression = nil
        }

        return .success(IntentParameterSpec(
            name: parameter.name,
            title: humanize(parameter.name),
            description: parameter.description,
            intentType: isOptional ? coreSpelling + "?" : coreSpelling,
            defaultExpression: defaultExpression,
            options: parameter.oneOfOptions
        ))
    }

    private static func intentCoreType(_ type: TypeSyntax) -> String? {
        if let array = type.as(ArrayTypeSyntax.self) {
            return intentArrayType(element: array.element)
        }
        guard let identifier = type.as(IdentifierTypeSyntax.self) else {
            return nil
        }
        if identifier.name.text == "Array" {
            guard let clause = identifier.genericArgumentClause,
                  clause.arguments.count == 1,
                  case let .type(element) = clause.arguments.first?.argument
            else {
                return nil
            }
            return intentArrayType(element: element)
        }
        return intentScalarType(identifier)
    }

    private static func intentArrayType(element: TypeSyntax) -> String? {
        let (core, isOptional) = ParameterTypeMapping.stripOptionals(element)
        guard !isOptional,
              let identifier = core.as(IdentifierTypeSyntax.self),
              let scalar = intentScalarType(identifier)
        else {
            return nil
        }
        return "[\(scalar)]"
    }

    private static func intentScalarType(_ identifier: IdentifierTypeSyntax) -> String? {
        guard identifier.genericArgumentClause == nil else { return nil }
        switch identifier.name.text {
        case "String", "Int", "Double", "Bool":
            return identifier.name.text
        case "Float":
            return "Double"
        default:
            return nil
        }
    }
}

// MARK: - Diagnostics

enum IntentMacroDiagnostic: DiagnosticMessage {
    case intentToolRequiresStruct
    case genericToolUnsupported
    case missingToolAttribute
    case unsupportedIntentParameter(name: String, type: String)
    case agentIntentRequiresStruct
    case missingTitle
    case missingMakeAgent

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        let id = switch self {
        case .intentToolRequiresStruct: "intentToolRequiresStruct"
        case .genericToolUnsupported: "genericToolUnsupported"
        case .missingToolAttribute: "missingToolAttribute"
        case .unsupportedIntentParameter: "unsupportedIntentParameter"
        case .agentIntentRequiresStruct: "agentIntentRequiresStruct"
        case .missingTitle: "missingTitle"
        case .missingMakeAgent: "missingMakeAgent"
        }
        return MessageID(domain: "SwarmMacros", id: id)
    }

    var message: String {
        switch self {
        case .intentToolRequiresStruct:
            "@IntentTool can only be applied to a struct"
        case .genericToolUnsupported:
            "@IntentTool cannot be applied to a generic struct; App Intents must be concrete types"
        case .missingToolAttribute:
            "@IntentTool requires the struct to also be annotated with @Tool(\"description\")"
        case let .unsupportedIntentParameter(name, type):
            """
            Parameter '\(name)' has type '\(type)', which App Intents cannot represent. \
            @IntentTool supports String, Int, Double, Float, Bool, arrays of those, and Optional of those.
            """
        case .agentIntentRequiresStruct:
            "@AgentIntent can only be applied to a struct"
        case .missingTitle:
            "@AgentIntent requires a title string literal, e.g. @AgentIntent(\"Ask Assistant\")"
        case .missingMakeAgent:
            """
            @AgentIntent requires 'static func makeAgent() -> some AgentRuntime' (it may be async and/or throws)
            """
        }
    }

    func diagnostic(at node: some SyntaxProtocol) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: self)
    }
}

// MARK: - Shared helpers

/// Reads string-literal arguments from a macro attribute.
private struct IntentMacroArguments {
    let arguments: [LabeledExprSyntax]

    init(_ node: AttributeSyntax) {
        arguments = node.arguments?.as(LabeledExprListSyntax.self).map(Array.init) ?? []
    }

    /// Returns the string literal at `position` (when unlabeled) or for `label`.
    func string(at position: Int?, label: String?) -> String? {
        let match: LabeledExprSyntax?
        if let label {
            match = arguments.first { $0.label?.text == label }
        } else if let position, position < arguments.count, arguments[position].label == nil {
            match = arguments[position]
        } else {
            match = nil
        }
        guard let literal = match?.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        return ToolMacro.extractStaticStringLiteral(from: literal)
    }
}

/// Finds `@Name` or `@Module.Name` in an attribute list.
private func findAttribute(named name: String, in attributes: AttributeListSyntax) -> AttributeSyntax? {
    for element in attributes {
        guard let attribute = element.as(AttributeSyntax.self) else { continue }
        if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == name {
            return attribute
        }
        if let member = attribute.attributeName.as(MemberTypeSyntax.self),
           member.name.text == name {
            return attribute
        }
    }
    return nil
}

private func performDeclaration(lines: [String]) -> String {
    """
    public func perform() async throws -> some AppIntents.IntentResult & AppIntents.ReturnsValue<String> & AppIntents.ProvidesDialog {
    \(lines.map { "    " + $0 }.joined(separator: "\n"))
    }
    """
}

private func indent(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? "" : "    " + $0 }
        .joined(separator: "\n")
}

private func literal(_ value: String) -> String {
    String(reflecting: value)
}

/// `"WeatherTool"` → `"Weather"`, `"GetStockQuoteTool"` → `"Get Stock Quote"`.
func deriveTitle(fromTypeName typeName: String) -> String {
    var name = typeName
    if name.hasSuffix("Tool"), name.count > 4 {
        name = String(name.dropLast(4))
    }
    return humanize(name)
}

/// `"includeForecast"` → `"Include Forecast"`, `"max_results"` → `"Max Results"`.
func humanize(_ identifier: String) -> String {
    var words: [String] = []
    var current = ""
    let characters = Array(identifier)
    for (index, character) in characters.enumerated() {
        if character == "_" {
            if !current.isEmpty { words.append(current) }
            current = ""
            continue
        }
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        let startsWord = character.isUppercase && !current.isEmpty
            && (previous?.isLowercase == true || previous?.isNumber == true || next?.isLowercase == true)
        if startsWord {
            words.append(current)
            current = ""
        }
        current.append(character)
    }
    if !current.isEmpty { words.append(current) }
    return words
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
