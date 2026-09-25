// TraceableMacroTests.swift
// SwarmMacrosTests
//
// Tests for the @Traceable macro expansion.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(SwarmMacros)
    import SwarmMacros

    private func traceableMacros() -> [String: Macro.Type] {
        [
        "Traceable": TraceableMacro.self
        ]
    }
#endif

// MARK: - TraceableMacroTests

final class TraceableMacroTests: XCTestCase {
    // MARK: - Basic Traceable Tests

    func testTraceableMacroExpansion() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Traceable
                struct WeatherTool: Tool {
                    let name = "weather"
                    let description = "Gets weather"
                    let parameters: [ToolParameter] = []

                    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                        return .string("Sunny")
                    }
                }
                """,
                expandedSource: """
                struct WeatherTool: Tool {
                    let name = "weather"
                    let description = "Gets weather"
                    let parameters: [ToolParameter] = []

                    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
                        return .string("Sunny")
                    }
                }

                /// Executes the tool with tracing enabled.
                /// - Parameters:
                ///   - arguments: The tool arguments.
                ///   - tracer: Optional tracer for recording events.
                /// - Returns: The result of execution.
                public func executeWithTracing(
                    arguments: [String: SendableValue],
                    tracer: (any Tracer)? = nil
                ) async throws -> SendableValue {
                    let startTime = ContinuousClock.now
                    let traceId = UUID()
                    let spanId = UUID()
                    let argumentKeys = arguments.keys.sorted().map {
                        SendableValue.string($0)
                    }

                    // Emit start event
                    if let tracer = tracer {
                        await tracer.trace(TraceEvent(
                            traceId: traceId,
                            spanId: spanId,
                            kind: .toolCall,
                            level: .debug,
                            message: "Tool call: \\(name)",
                            metadata: [
                                "tool_name": .string(name),
                                "argument_count": .int(arguments.count),
                                "argument_keys": .array(argumentKeys),
                                "arguments_redacted": .bool(true)
                            ],
                            toolName: name
                        ))
                    }

                    do {
                        let result = try await execute(arguments: arguments)
                        let duration = ContinuousClock.now - startTime

                        // Emit success event
                        if let tracer = tracer {
                            await tracer.trace(TraceEvent(
                                traceId: traceId,
                                spanId: spanId,
                                duration: duration.timeInterval,
                                kind: .toolResult,
                                level: .debug,
                                message: "Tool result: \\(name)",
                                metadata: [
                                    "tool_name": .string(name),
                                    "result_length": .int(String(describing: result).count),
                                    "duration_ms": .double(duration.timeInterval * 1000),
                                    "success": .bool(true)
                                ],
                                toolName: name
                            ))
                        }

                        return result
                    } catch {
                        let duration = ContinuousClock.now - startTime

                        // Emit error event
                        if let tracer = tracer {
                            await tracer.trace(TraceEvent(
                                traceId: traceId,
                                spanId: spanId,
                                duration: duration.timeInterval,
                                kind: .toolError,
                                level: .error,
                                message: "Tool error: \\(name)",
                                metadata: [
                                    "tool_name": .string(name),
                                    "error_type": .string(String(describing: type(of: error))),
                                    "duration_ms": .double(duration.timeInterval * 1000),
                                    "success": .bool(false)
                                ],
                                toolName: name
                            ))
                        }

                        throw error
                    }
                }
                """,
                macros: traceableMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - Error Cases

    func testTraceableOnlyAppliesToStruct() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @Traceable
                class InvalidTool {
                }
                """,
                expandedSource: """
                class InvalidTool {
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: "@Traceable can only be applied to structs", line: 1, column: 1)
                ],
                macros: traceableMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
