// IntentToolMacroTests.swift
// SwarmMacrosTests
//
// Expansion and diagnostic tests for @IntentTool and @AgentIntent.

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(SwarmMacros)
    @testable import SwarmMacros

    private let intentMacros: [String: Macro.Type] = [
        "IntentTool": IntentToolMacro.self,
        "AgentIntent": AgentIntentMacro.self,
    ]
#endif

// MARK: - IntentToolMacroTests

final class IntentToolMacroTests: XCTestCase {
    func testMirrorsToolParametersAsIntentParameters() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("Gets the weather for a city")
                @IntentTool("Get Weather")
                struct WeatherTool {
                    @Parameter("City name")
                    var city: String = ""

                    @Parameter("Temperature units", oneOf: ["celsius", "fahrenheit"])
                    var units: String = "celsius"

                    @Parameter("Days of forecast", default: 3)
                    var days: Int = 3

                    @Parameter("Scale")
                    var scale: Float?

                    @Parameter("Tags")
                    var tags: [String] = []

                    @Parameter("Note", default: "")
                    var note: String = ""

                    func execute() async throws -> String { "" }
                }
                """,
                expandedSource: """
                @Tool("Gets the weather for a city")
                struct WeatherTool {
                    @Parameter("City name")
                    var city: String = ""

                    @Parameter("Temperature units", oneOf: ["celsius", "fahrenheit"])
                    var units: String = "celsius"

                    @Parameter("Days of forecast", default: 3)
                    var days: Int = 3

                    @Parameter("Scale")
                    var scale: Float?

                    @Parameter("Tags")
                    var tags: [String] = []

                    @Parameter("Note", default: "")
                    var note: String = ""

                    func execute() async throws -> String { "" }

                    public struct Intent: AppIntents.AppIntent {
                        public static let title: LocalizedStringResource = "Get Weather"

                        public static let description: AppIntents.IntentDescription = AppIntents.IntentDescription("Gets the weather for a city")

                        @AppIntents.IntentParameter(title: "City", description: "City name")
                        public var city: String

                        @AppIntents.IntentParameter(title: "Units", description: "Temperature units", default: "celsius", optionsProvider: UnitsOptions())
                        public var units: String

                        @AppIntents.IntentParameter(title: "Days", description: "Days of forecast", default: 3)
                        public var days: Int

                        @AppIntents.IntentParameter(title: "Scale", description: "Scale")
                        public var scale: Double?

                        @AppIntents.IntentParameter(title: "Tags", description: "Tags")
                        public var tags: [String]

                        @AppIntents.IntentParameter(title: "Note", description: "Note", default: "")
                        public var note: String

                        public struct UnitsOptions: AppIntents.DynamicOptionsProvider {
                            public init() {
                            }

                            public func results() async throws -> [String] {
                                ["celsius", "fahrenheit"]
                            }
                        }

                        public init() {
                        }

                        public func perform() async throws -> some AppIntents.IntentResult & AppIntents.ReturnsValue<String> & AppIntents.ProvidesDialog {
                            var swarmArguments: [String: SendableValue] = [:]
                            swarmArguments["city"] = SwarmIntentArgument.encode(self.city)
                            swarmArguments["units"] = SwarmIntentArgument.encode(self.units)
                            swarmArguments["days"] = SwarmIntentArgument.encode(self.days)
                            swarmArguments["scale"] = SwarmIntentArgument.encode(self.scale)
                            swarmArguments["tags"] = SwarmIntentArgument.encode(self.tags)
                            swarmArguments["note"] = SwarmIntentArgument.encode(self.note)
                            let swarmOutput = try await SwarmIntentBridge.run(WeatherTool(), arguments: swarmArguments)
                            return .result(value: swarmOutput, dialog: "\\(swarmOutput)")
                        }
                    }
                }
                """,
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testDerivesTitleAndAcceptsDescriptionOverride() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Swarm.Tool("Looks up a stock quote")
                @IntentTool(description: "Shows the latest price")
                struct GetStockQuoteTool {
                    func execute() async throws -> Double { 1 }
                }
                """,
                expandedSource: """
                @Swarm.Tool("Looks up a stock quote")
                struct GetStockQuoteTool {
                    func execute() async throws -> Double { 1 }

                    public struct Intent: AppIntents.AppIntent {
                        public static let title: LocalizedStringResource = "Get Stock Quote"

                        public static let description: AppIntents.IntentDescription = AppIntents.IntentDescription("Shows the latest price")

                        public init() {
                        }

                        public func perform() async throws -> some AppIntents.IntentResult & AppIntents.ReturnsValue<String> & AppIntents.ProvidesDialog {
                            var swarmArguments: [String: SendableValue] = [:]
                            let swarmOutput = try await SwarmIntentBridge.run(GetStockQuoteTool(), arguments: swarmArguments)
                            return .result(value: swarmOutput, dialog: "\\(swarmOutput)")
                        }
                    }
                }
                """,
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testRequiresToolAttribute() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @IntentTool("Orphan")
                struct OrphanTool {
                }
                """,
                expandedSource: """
                struct OrphanTool {
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@IntentTool requires the struct to also be annotated with @Tool(\"description\")",
                        line: 1,
                        column: 1
                    ),
                ],
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testRejectsNonStructAndGenericDeclarations() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("x")
                @IntentTool
                enum NotAStruct {
                }

                @Tool("x")
                @IntentTool
                struct GenericTool<T> {
                }
                """,
                expandedSource: """
                @Tool("x")
                enum NotAStruct {
                }

                @Tool("x")
                struct GenericTool<T> {
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: "@IntentTool can only be applied to a struct", line: 2, column: 1),
                    DiagnosticSpec(
                        message: "@IntentTool cannot be applied to a generic struct; App Intents must be concrete types",
                        line: 7,
                        column: 1
                    ),
                ],
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testRejectsParameterTypesAppIntentsCannotRepresent() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Tool("x")
                @IntentTool
                struct MatrixTool {
                    @Parameter("Rows")
                    var rows: [[Int]] = []

                    @Parameter("Maybe names")
                    var names: [String?] = []
                }
                """,
                expandedSource: """
                @Tool("x")
                struct MatrixTool {
                    @Parameter("Rows")
                    var rows: [[Int]] = []

                    @Parameter("Maybe names")
                    var names: [String?] = []
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: """
                        Parameter 'rows' has type '[[Int]]', which App Intents cannot represent. \
                        @IntentTool supports String, Int, Double, Float, Bool, arrays of those, and Optional of those.
                        """,
                        line: 2,
                        column: 1
                    ),
                    DiagnosticSpec(
                        message: """
                        Parameter 'names' has type '[String?]', which App Intents cannot represent. \
                        @IntentTool supports String, Int, Double, Float, Bool, arrays of those, and Optional of those.
                        """,
                        line: 2,
                        column: 1
                    ),
                ],
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testDefersToToolDiagnosticsForInvalidToolParameters() throws {
        #if canImport(SwarmMacros)
            // @Tool already reports the dictionary parameter; @IntentTool stays quiet
            // rather than emitting a second error for the same property.
            assertMacroExpansion(
                """
                @Tool("x")
                @IntentTool
                struct BadTool {
                    @Parameter("Map")
                    var map: [String: Int] = [:]
                }
                """,
                expandedSource: """
                @Tool("x")
                struct BadTool {
                    @Parameter("Map")
                    var map: [String: Int] = [:]
                }
                """,
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testHumanizesIdentifiers() throws {
        #if canImport(SwarmMacros)
            XCTAssertEqual(humanize("city"), "City")
            XCTAssertEqual(humanize("includeForecast"), "Include Forecast")
            XCTAssertEqual(humanize("max_results"), "Max Results")
            XCTAssertEqual(humanize("sourceURL"), "Source URL")
            XCTAssertEqual(humanize("URLString"), "URL String")
            XCTAssertEqual(deriveTitle(fromTypeName: "WeatherTool"), "Weather")
            XCTAssertEqual(deriveTitle(fromTypeName: "GetStockQuoteTool"), "Get Stock Quote")
            XCTAssertEqual(deriveTitle(fromTypeName: "Tool"), "Tool")
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

// MARK: - AgentIntentMacroTests

final class AgentIntentMacroTests: XCTestCase {
    func testAsyncThrowingFactory() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentIntent("Plan a Trip", description: "Plans weekend trips")
                struct PlanTripIntent {
                    static func makeAgent() async throws -> some AgentRuntime { try await build() }
                }
                """,
                expandedSource: """
                struct PlanTripIntent {
                    static func makeAgent() async throws -> some AgentRuntime { try await build() }

                    public static let title: LocalizedStringResource = "Plan a Trip"

                    public static let description: AppIntents.IntentDescription = AppIntents.IntentDescription("Plans weekend trips")

                    @AppIntents.IntentParameter(title: "Request")
                    public var prompt: String

                    public init() {
                    }

                    public func perform() async throws -> some AppIntents.IntentResult & AppIntents.ReturnsValue<String> & AppIntents.ProvidesDialog {
                        let swarmAgent = try await Self.makeAgent()
                        let swarmOutput = try await SwarmIntentBridge.run(agent: swarmAgent, prompt: self.prompt)
                        return .result(value: swarmOutput, dialog: "\\(swarmOutput)")
                    }
                }

                extension PlanTripIntent: AppIntents.AppIntent {
                }
                """,
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testSynchronousFactoryAndCustomPromptTitle() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentIntent("Ask Chef", promptTitle: "Question")
                struct AskChefIntent {
                    static func makeAgent() -> any AgentRuntime { chef }
                }
                """,
                expandedSource: """
                struct AskChefIntent {
                    static func makeAgent() -> any AgentRuntime { chef }

                    public static let title: LocalizedStringResource = "Ask Chef"

                    @AppIntents.IntentParameter(title: "Question")
                    public var prompt: String

                    public init() {
                    }

                    public func perform() async throws -> some AppIntents.IntentResult & AppIntents.ReturnsValue<String> & AppIntents.ProvidesDialog {
                        let swarmAgent = Self.makeAgent()
                        let swarmOutput = try await SwarmIntentBridge.run(agent: swarmAgent, prompt: self.prompt)
                        return .result(value: swarmOutput, dialog: "\\(swarmOutput)")
                    }
                }

                extension AskChefIntent: AppIntents.AppIntent {
                }
                """,
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testRequiresStaticMakeAgent() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentIntent("Ask")
                struct AskIntent {
                    func makeAgent() -> any AgentRuntime { chef }
                }
                """,
                expandedSource: """
                struct AskIntent {
                    func makeAgent() -> any AgentRuntime { chef }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: """
                        @AgentIntent requires 'static func makeAgent() -> some AgentRuntime' (it may be async and/or throws)
                        """,
                        line: 1,
                        column: 1
                    ),
                ],
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testRequiresTitleAndStruct() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentIntent(description: "No title")
                struct UntitledIntent {
                    static func makeAgent() -> any AgentRuntime { chef }
                }

                @AgentIntent("Ask")
                actor ActorIntent {
                    static func makeAgent() -> any AgentRuntime { chef }
                }
                """,
                expandedSource: """
                struct UntitledIntent {
                    static func makeAgent() -> any AgentRuntime { chef }
                }
                actor ActorIntent {
                    static func makeAgent() -> any AgentRuntime { chef }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(
                        message: "@AgentIntent requires a title string literal, e.g. @AgentIntent(\"Ask Assistant\")",
                        line: 1,
                        column: 1
                    ),
                    DiagnosticSpec(message: "@AgentIntent can only be applied to a struct", line: 6, column: 1),
                ],
                macros: intentMacros
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
