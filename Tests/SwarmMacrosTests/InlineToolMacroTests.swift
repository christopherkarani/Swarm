// InlineToolMacroTests.swift
// SwarmMacrosTests
//
// Tests for the #Tool freestanding expression macro expansion.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(SwarmMacros)
    import SwarmMacros

    private func inlineToolMacros() -> [String: Macro.Type] {
        [
        "Tool": InlineToolMacro.self,
        ]
    }
#endif

// MARK: - InlineToolMacroTests

final class InlineToolMacroTests: XCTestCase {

    // MARK: - Single Parameter

    func testSingleStringParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("greet", "Says hello") { (name: String) in
                    "Hello, \\(name)!"
                }
                """,
                expandedSource: """
                {
                    struct _GreetInput: Codable, Sendable {
                        let name: String
                    }
                    struct _InlineTool_greet: Tool, Sendable {
                        typealias Input = _GreetInput
                        typealias Output = String
                        let name = "greet"
                        let description = "Says hello"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "name", description: "name", type: .string, isRequired: true)
                        ]
                        func execute(_ input: _GreetInput) async throws -> String {
                            "Hello, \\(input.name)!"
                        }
                    }
                    return _InlineTool_greet()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Multiple Parameters

    func testMultipleParams() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("greet", "Says hello") { (name: String, age: Int) in
                    "Hello, \\(name)! You are \\(age)."
                }
                """,
                expandedSource: """
                {
                    struct _GreetInput: Codable, Sendable {
                        let name: String
                        let age: Int
                    }
                    struct _InlineTool_greet: Tool, Sendable {
                        typealias Input = _GreetInput
                        typealias Output = String
                        let name = "greet"
                        let description = "Says hello"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "name", description: "name", type: .string, isRequired: true),
                            ToolParameter(name: "age", description: "age", type: .int, isRequired: true)
                        ]
                        func execute(_ input: _GreetInput) async throws -> String {
                            "Hello, \\(input.name)! You are \\(input.age)."
                        }
                    }
                    return _InlineTool_greet()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Optional Parameter

    func testOptionalParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("greet", "Says hello") { (name: String, title: String?) in
                    "Hello, \\(name)!"
                }
                """,
                expandedSource: """
                {
                    struct _GreetInput: Codable, Sendable {
                        let name: String
                        let title: String?
                    }
                    struct _InlineTool_greet: Tool, Sendable {
                        typealias Input = _GreetInput
                        typealias Output = String
                        let name = "greet"
                        let description = "Says hello"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "name", description: "name", type: .string, isRequired: true),
                            ToolParameter(name: "title", description: "title", type: .string, isRequired: false)
                        ]
                        func execute(_ input: _GreetInput) async throws -> String {
                            "Hello, \\(input.name)!"
                        }
                    }
                    return _InlineTool_greet()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - No Parameters

    func testNoParams() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("ping", "Returns pong") { () in
                    "pong"
                }
                """,
                expandedSource: """
                {
                    struct _PingInput: Codable, Sendable {
                    }
                    struct _InlineTool_ping: Tool, Sendable {
                        typealias Input = _PingInput
                        typealias Output = String
                        let name = "ping"
                        let description = "Returns pong"
                        let parameters: [ToolParameter] = []
                        func execute(_ input: _PingInput) async throws -> String {
                            "pong"
                        }
                    }
                    return _InlineTool_ping()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Bool Parameter

    func testBoolParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("toggle", "Toggles a feature") { (enabled: Bool) in
                    "Feature is \\(enabled)."
                }
                """,
                expandedSource: """
                {
                    struct _ToggleInput: Codable, Sendable {
                        let enabled: Bool
                    }
                    struct _InlineTool_toggle: Tool, Sendable {
                        typealias Input = _ToggleInput
                        typealias Output = String
                        let name = "toggle"
                        let description = "Toggles a feature"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "enabled", description: "enabled", type: .bool, isRequired: true)
                        ]
                        func execute(_ input: _ToggleInput) async throws -> String {
                            "Feature is \\(input.enabled)."
                        }
                    }
                    return _InlineTool_toggle()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Double Parameter

    func testDoubleParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("compute", "Computes a value") { (score: Double) in
                    "Score: \\(score)"
                }
                """,
                expandedSource: """
                {
                    struct _ComputeInput: Codable, Sendable {
                        let score: Double
                    }
                    struct _InlineTool_compute: Tool, Sendable {
                        typealias Input = _ComputeInput
                        typealias Output = String
                        let name = "compute"
                        let description = "Computes a value"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "score", description: "score", type: .double, isRequired: true)
                        ]
                        func execute(_ input: _ComputeInput) async throws -> String {
                            "Score: \\(input.score)"
                        }
                    }
                    return _InlineTool_compute()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Rewrite safety (AST-guided, not naive string replace)

    /// Param identifiers inside string *literals* must stay untouched; only
    /// DeclReferenceExpr occurrences (including interpolations) rewrite to `input.`.
    func testParamNameInStringLiteralIsNotRewritten() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("echo", "Echo") { (name: String) in
                    "literal name and \\(name)"
                }
                """,
                expandedSource: """
                {
                    struct _EchoInput: Codable, Sendable {
                        let name: String
                    }
                    struct _InlineTool_echo: Tool, Sendable {
                        typealias Input = _EchoInput
                        typealias Output = String
                        let name = "echo"
                        let description = "Echo"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "name", description: "name", type: .string, isRequired: true)
                        ]
                        func execute(_ input: _EchoInput) async throws -> String {
                            "literal name and \\(input.name)"
                        }
                    }
                    return _InlineTool_echo()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    /// Member access like `values.count` must not rewrite the member name when
    /// a parameter is also named `count`.
    func testMemberAccessNameIsNotRewritten() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("compare", "Compare counts") { (count: Int) in
                    "\\(values.count) vs \\(count)"
                }
                """,
                expandedSource: """
                {
                    struct _CompareInput: Codable, Sendable {
                        let count: Int
                    }
                    struct _InlineTool_compare: Tool, Sendable {
                        typealias Input = _CompareInput
                        typealias Output = String
                        let name = "compare"
                        let description = "Compare counts"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "count", description: "count", type: .int, isRequired: true)
                        ]
                        func execute(_ input: _CompareInput) async throws -> String {
                            "\\(values.count) vs \\(input.count)"
                        }
                    }
                    return _InlineTool_compare()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Array / Optional spellings

    func testArrayShorthandParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("tags", "Lists tags") { (tags: [String]) in
                    tags.joined()
                }
                """,
                expandedSource: """
                {
                    struct _TagsInput: Codable, Sendable {
                        let tags: [String]
                    }
                    struct _InlineTool_tags: Tool, Sendable {
                        typealias Input = _TagsInput
                        typealias Output = String
                        let name = "tags"
                        let description = "Lists tags"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "tags", description: "tags", type: .array(elementType: .string), isRequired: true)
                        ]
                        func execute(_ input: _TagsInput) async throws -> String {
                            input.tags.joined()
                        }
                    }
                    return _InlineTool_tags()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testArrayGenericParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("values", "Lists values") { (values: Array<Int>) in
                    "\\(values.count)"
                }
                """,
                expandedSource: """
                {
                    struct _ValuesInput: Codable, Sendable {
                        let values: Array<Int>
                    }
                    struct _InlineTool_values: Tool, Sendable {
                        typealias Input = _ValuesInput
                        typealias Output = String
                        let name = "values"
                        let description = "Lists values"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "values", description: "values", type: .array(elementType: .int), isRequired: true)
                        ]
                        func execute(_ input: _ValuesInput) async throws -> String {
                            "\\(input.values.count)"
                        }
                    }
                    return _InlineTool_values()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testOptionalGenericParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("greet", "Says hello") { (name: Optional<String>) in
                    "Hello"
                }
                """,
                expandedSource: """
                {
                    struct _GreetInput: Codable, Sendable {
                        let name: Optional<String>
                    }
                    struct _InlineTool_greet: Tool, Sendable {
                        typealias Input = _GreetInput
                        typealias Output = String
                        let name = "greet"
                        let description = "Says hello"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "name", description: "name", type: .string, isRequired: false)
                        ]
                        func execute(_ input: _GreetInput) async throws -> String {
                            "Hello"
                        }
                    }
                    return _InlineTool_greet()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testOptionalArrayParam() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("tags", "Lists tags") { (tags: [String]?) in
                    "ok"
                }
                """,
                expandedSource: """
                {
                    struct _TagsInput: Codable, Sendable {
                        let tags: [String]?
                    }
                    struct _InlineTool_tags: Tool, Sendable {
                        typealias Input = _TagsInput
                        typealias Output = String
                        let name = "tags"
                        let description = "Lists tags"
                        let parameters: [ToolParameter] = [
                            ToolParameter(name: "tags", description: "tags", type: .array(elementType: .string), isRequired: false)
                        ]
                        func execute(_ input: _TagsInput) async throws -> String {
                            "ok"
                        }
                    }
                    return _InlineTool_tags()
                }()
                """,
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testDictionaryParamIsCompileError() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("lookup", "Looks up") { (table: [String: Int]) in
                    "ok"
                }
                """,
                expandedSource: """
                #Tool("lookup", "Looks up") { (table: [String: Int]) in
                    "ok"
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "Dictionary parameter type '[String: Int]' is not supported. ToolParameter.ParameterType has no homogeneous-dictionary case; `.object(properties:)` requires known keys. Use explicit object properties, a JSON-string parameter, or FunctionTool with `.any`.",
                        line: 1,
                        column: 39
                    )
                ],
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testUnknownTypeParamIsCompileError() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("schedule", "Schedules") { (when: Date) in
                    "ok"
                }
                """,
                expandedSource: """
                #Tool("schedule", "Schedules") { (when: Date) in
                    "ok"
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "Unsupported parameter type 'Date'. Supported types are String, Int, Double, Float, Bool, arrays of those types, and Optional of those types. Use @Parameter(oneOf:) for string enums. For advanced schemas, write a FunctionTool instead.",
                        line: 1,
                        column: 41
                    )
                ],
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Error Cases

    func testMissingNameArgument() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool() { (name: String) in
                    "Hello, \\(name)!"
                }
                """,
                expandedSource: """
                #Tool() { (name: String) in
                    "Hello, \\(name)!"
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: "#Tool requires a name string as the first argument", line: 1, column: 1),
                ],
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMissingDescriptionArgument() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                #Tool("greet") { (name: String) in
                    "Hello, \\(name)!"
                }
                """,
                expandedSource: """
                #Tool("greet") { (name: String) in
                    "Hello, \\(name)!"
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: "#Tool requires a description string as the second argument", line: 1, column: 1),
                ],
                macros: inlineToolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
