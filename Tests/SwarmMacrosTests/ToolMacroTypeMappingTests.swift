// ToolMacroTypeMappingTests.swift
// SwarmMacrosTests
//
// Expansion and diagnostic tests for @Tool parameter type mapping.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(SwarmMacros)
    import SwarmMacros

    private func toolMacros() -> [String: Macro.Type] {
        [
            "Tool": ToolMacro.self,
            "Parameter": ParameterMacro.self
        ]
    }
#endif

private enum ExpectedDiagnostic {
    static let unsupportedDate = """
        Unsupported parameter type 'Date'. Supported types are String, Int, Double, Float, Bool, arrays of those types, and Optional of those types. Use @Parameter(oneOf:) for string enums. For advanced schemas, write a FunctionTool instead.
        """

    static let dictionaryStringInt = """
        Dictionary parameter type '[String: Int]' is not supported. ToolParameter.ParameterType has no homogeneous-dictionary case; `.object(properties:)` requires known keys. Use explicit object properties, a JSON-string parameter, or FunctionTool with `.any`.
        """

    static let dictionaryGeneric = """
        Dictionary parameter type 'Dictionary<String, Int>' is not supported. ToolParameter.ParameterType has no homogeneous-dictionary case; `.object(properties:)` requires known keys. Use explicit object properties, a JSON-string parameter, or FunctionTool with `.any`.
        """

    static let unencodableArrayDefault = """
        Cannot encode a default value for parameter type '[Int]'. Supported types are String, Int, Double, Float, Bool, arrays of those types, and Optional of those types. For advanced schemas, write a FunctionTool instead.
        """
}

// MARK: - ToolMacroTypeMappingTests

final class ToolMacroTypeMappingTests: XCTestCase {

    // MARK: Newly supported spellings

    func testArrayShorthandParameter() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Tags items")
                struct TagTool {
                    @Parameter("Tag list")
                    var tags: [String]

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct TagTool {
                    var tags: [String]

                    func execute() async throws -> String {
                        return ""
                    }

                    public let name: String = "tag"

                    public let description: String = "Tags items"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "tags",
                            description: "Tag list",
                            type: .array(elementType: .string),
                            isRequired: true
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var tags: [String]
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.tags = input.tags
                        return try await toolCopy.execute()
                    }
                }

                extension TagTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testArrayGenericSpelling() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Counts values")
                struct ValuesTool {
                    @Parameter("Values")
                    var values: Array<Int>

                    func execute() async throws -> Int {
                        return values.count
                    }
                }
                """,
                expandedSource: """
                struct ValuesTool {
                    var values: Array<Int>

                    func execute() async throws -> Int {
                        return values.count
                    }

                    public let name: String = "values"

                    public let description: String = "Counts values"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "values",
                            description: "Values",
                            type: .array(elementType: .int),
                            isRequired: true
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var values: Array<Int>
                    }

                    public typealias Output = Int

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.values = input.values
                        return try await toolCopy.execute()
                    }
                }

                extension ValuesTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testOptionalGenericSpelling() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Greets")
                struct OptionalNameTool {
                    @Parameter("Optional name")
                    var name: Optional<String>

                    func execute() async throws -> String {
                        return name ?? ""
                    }
                }
                """,
                expandedSource: """
                struct OptionalNameTool {
                    var name: Optional<String>

                    func execute() async throws -> String {
                        return name ?? ""
                    }

                    public let name: String = "optional_name"

                    public let description: String = "Greets"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "name",
                            description: "Optional name",
                            type: .string,
                            isRequired: false
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var name: Optional<String>
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.name = input.name
                        return try await toolCopy.execute()
                    }
                }

                extension OptionalNameTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testOptionalArrayShorthand() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Lists tags")
                struct OptionalTagsTool {
                    @Parameter("Optional tags")
                    var tags: [String]?

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct OptionalTagsTool {
                    var tags: [String]?

                    func execute() async throws -> String {
                        return ""
                    }

                    public let name: String = "optional_tags"

                    public let description: String = "Lists tags"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "tags",
                            description: "Optional tags",
                            type: .array(elementType: .string),
                            isRequired: false
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var tags: [String]?
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.tags = input.tags
                        return try await toolCopy.execute()
                    }
                }

                extension OptionalTagsTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testOptionalArrayGeneric() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Lists scores")
                struct OptionalScoresTool {
                    @Parameter("Optional scores")
                    var scores: Array<Double>?

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct OptionalScoresTool {
                    var scores: Array<Double>?

                    func execute() async throws -> String {
                        return ""
                    }

                    public let name: String = "optional_scores"

                    public let description: String = "Lists scores"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "scores",
                            description: "Optional scores",
                            type: .array(elementType: .double),
                            isRequired: false
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var scores: Array<Double>?
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.scores = input.scores
                        return try await toolCopy.execute()
                    }
                }

                extension OptionalScoresTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testNestedArrayParameter() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Groups rows")
                struct NestedArrayTool {
                    @Parameter("Rows")
                    var rows: [[String]]

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct NestedArrayTool {
                    var rows: [[String]]

                    func execute() async throws -> String {
                        return ""
                    }

                    public let name: String = "nested_array"

                    public let description: String = "Groups rows"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "rows",
                            description: "Rows",
                            type: .array(elementType: .array(elementType: .string)),
                            isRequired: true
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var rows: [[String]]
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.rows = input.rows
                        return try await toolCopy.execute()
                    }
                }

                extension NestedArrayTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testOptionalWrappedArrayGeneric() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Lists flags")
                struct OptionalWrappedArrayTool {
                    @Parameter("Optional flags")
                    var flags: Optional<[Bool]>

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct OptionalWrappedArrayTool {
                    var flags: Optional<[Bool]>

                    func execute() async throws -> String {
                        return ""
                    }

                    public let name: String = "optional_wrapped_array"

                    public let description: String = "Lists flags"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "flags",
                            description: "Optional flags",
                            type: .array(elementType: .bool),
                            isRequired: false
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var flags: Optional<[Bool]>
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.flags = input.flags
                        return try await toolCopy.execute()
                    }
                }

                extension OptionalWrappedArrayTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testArrayLiteralDefaultEncodesAsSendableValue() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Tags items")
                struct DefaultTagsTool {
                    @Parameter("Tag list")
                    var tags: [String] = ["a", "b"]

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct DefaultTagsTool {
                    var tags: [String] = ["a", "b"]

                    func execute() async throws -> String {
                        return ""
                    }

                    public let name: String = "default_tags"

                    public let description: String = "Tags items"

                    public let parameters: [ToolParameter] = [
                                ToolParameter(
                            name: "tags",
                            description: "Tag list",
                            type: .array(elementType: .string),
                            isRequired: false, defaultValue: .array([.string("a"), .string("b")])
                        )
                        ]

                    public init() {
                    }

                    public struct Input: Codable, Sendable {
                        public var tags: [String]? = ["a", "b"]
                    }

                    public typealias Output = String

                    public func execute(_ input: Input) async throws -> Output {
                        var toolCopy = self
                        toolCopy.tags = input.tags ?? ["a", "b"]
                        return try await toolCopy.execute()
                    }
                }

                extension DefaultTagsTool: Tool, Sendable {
                }
                """,
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: Compile errors

    func testDictionaryShorthandIsCompileError() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Looks up values")
                struct LookupTool {
                    @Parameter("Keyed values")
                    var table: [String: Int]

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct LookupTool {
                    var table: [String: Int]

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: ExpectedDiagnostic.dictionaryStringInt, line: 4, column: 16)
                ],
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testDictionaryGenericIsCompileError() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Looks up values")
                struct LookupGenericTool {
                    @Parameter("Keyed values")
                    var table: Dictionary<String, Int>

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct LookupGenericTool {
                    var table: Dictionary<String, Int>

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: ExpectedDiagnostic.dictionaryGeneric, line: 4, column: 16)
                ],
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testUnknownTypeIsCompileError() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Schedules work")
                struct ScheduleTool {
                    @Parameter("When")
                    var when: Date

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct ScheduleTool {
                    var when: Date

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: ExpectedDiagnostic.unsupportedDate, line: 4, column: 15)
                ],
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testNonLiteralArrayDefaultIsCompileError() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Counts")
                struct DynamicDefaultTool {
                    @Parameter("Values")
                    var values: [Int] = makeValues()

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct DynamicDefaultTool {
                    var values: [Int] = makeValues()

                    func execute() async throws -> String {
                        return ""
                    }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: ExpectedDiagnostic.unencodableArrayDefault, line: 4, column: 25)
                ],
                macros: toolMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
