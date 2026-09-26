// ToolArgumentsLatticeTests.swift
// SwarmTests
//
// Pins ToolArguments.require / optional / optionalValue to the ToolArgumentValue
// extraction lattice (AC-001..AC-003). The lattice is open: URL joins it below
// via the extract requirement (spec section 9).

@testable import Swarm
import Foundation
import Testing

extension URL: ToolArgumentValue {
    public static func extract(from value: SendableValue) -> URL? {
        guard case let .string(s) = value else { return nil }
        return URL(string: s)
    }
}

struct ToolArgumentsLatticeTests {
    @Test("String, Int, Double, and Bool conform to ToolArgumentValue")
    func latticeTypesConformToToolArgumentValue() {
        func assertConformance<T: ToolArgumentValue>(_: T.Type) {}
        assertConformance(String.self)
        assertConformance(Int.self)
        assertConformance(Double.self)
        assertConformance(Bool.self)
    }

    @Test("require extracts String")
    func requireExtractsString() throws {
        let args = ToolArguments(["city": .string("Tokyo")])
        #expect(try args.require("city", as: String.self) == "Tokyo")
    }

    @Test("require extracts Int")
    func requireExtractsInt() throws {
        let args = ToolArguments(["count": .int(5)])
        #expect(try args.require("count", as: Int.self) == 5)
    }

    @Test("require extracts Double")
    func requireExtractsDouble() throws {
        let args = ToolArguments(["ratio": .double(1.5)])
        #expect(try args.require("ratio", as: Double.self) == 1.5)
    }

    @Test("require extracts Bool")
    func requireExtractsBool() throws {
        let args = ToolArguments(["ok": .bool(true)])
        #expect(try args.require("ok", as: Bool.self) == true)
    }

    @Test("optional extracts String")
    func optionalExtractsString() {
        let args = ToolArguments(["city": .string("Tokyo")])
        #expect(args.optional("city", as: String.self) == "Tokyo")
    }

    @Test("optional extracts Int")
    func optionalExtractsInt() {
        let args = ToolArguments(["count": .int(5)])
        #expect(args.optional("count", as: Int.self) == 5)
    }

    @Test("optional extracts Double")
    func optionalExtractsDouble() {
        let args = ToolArguments(["ratio": .double(1.5)])
        #expect(args.optional("ratio", as: Double.self) == 1.5)
    }

    @Test("optional extracts Bool")
    func optionalExtractsBool() {
        let args = ToolArguments(["ok": .bool(false)])
        #expect(args.optional("ok", as: Bool.self) == false)
    }

    @Test("require throws invalidToolArguments when a required String key is missing")
    func requireMissingStringThrows() {
        let args = ToolArguments([:], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Missing required argument: url"
        )) {
            _ = try args.require("url", as: String.self)
        }
    }

    @Test("require throws invalidToolArguments when a required Int key is missing")
    func requireMissingIntThrows() {
        let args = ToolArguments([:], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Missing required argument: n"
        )) {
            _ = try args.require("n", as: Int.self)
        }
    }

    @Test("require throws invalidToolArguments when a required Double key is missing")
    func requireMissingDoubleThrows() {
        let args = ToolArguments([:], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Missing required argument: ratio"
        )) {
            _ = try args.require("ratio", as: Double.self)
        }
    }

    @Test("require throws invalidToolArguments when a required Bool key is missing")
    func requireMissingBoolThrows() {
        let args = ToolArguments([:], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Missing required argument: ok"
        )) {
            _ = try args.require("ok", as: Bool.self)
        }
    }

    @Test("optional returns nil when a lattice key is missing")
    func optionalReturnsNilForMissingLatticeKeys() {
        let args = ToolArguments([:])
        #expect(args.optional("city", as: String.self) == nil)
        #expect(args.optional("count", as: Int.self) == nil)
        #expect(args.optional("ratio", as: Double.self) == nil)
        #expect(args.optional("ok", as: Bool.self) == nil)
    }

    // MARK: - Extraction rules (AC-001, AC-002)

    @Test("extract is exact-case with no coercion")
    func extractIsExactCase() {
        #expect(String.extract(from: .string("hi")) == "hi")
        #expect(String.extract(from: .int(1)) == nil)
        #expect(Int.extract(from: .int(5)) == 5)
        #expect(Int.extract(from: .double(5.0)) == nil)
        #expect(Int.extract(from: .string("5")) == nil)
        #expect(Double.extract(from: .double(1.5)) == 1.5)
        #expect(Double.extract(from: .int(1)) == nil)
        #expect(Bool.extract(from: .bool(true)) == true)
        #expect(Bool.extract(from: .string("true")) == nil)
        #expect(Bool.extract(from: .int(1)) == nil)
    }

    @Test("require throws invalidToolArguments on mistyped values")
    func requireMistypedThrows() {
        let args = ToolArguments(["count": .string("5")], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Argument 'count' is not of type Int"
        )) {
            _ = try args.require("count", as: Int.self)
        }
    }

    @Test("require rejects int-for-double coercion")
    func requireRejectsNumericCoercion() {
        let args = ToolArguments(["ratio": .int(1)], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Argument 'ratio' is not of type Double"
        )) {
            _ = try args.require("ratio", as: Double.self)
        }
    }

    @Test("optional returns nil on mistyped values")
    func optionalMistypedReturnsNil() {
        let args = ToolArguments(["count": .string("5")])
        #expect(args.optional("count", as: Int.self) == nil)
    }

    @Test("custom conformance joins the lattice via extract")
    func customConformanceJoinsLatticeViaExtract() throws {
        let args = ToolArguments(["site": .string("https://example.com")])
        #expect(try args.require("site", as: URL.self) == URL(string: "https://example.com"))
        #expect(args.optional("site", as: URL.self) == URL(string: "https://example.com"))
        #expect(args.optional("missing", as: URL.self) == nil)
    }

    @Test("custom conformance rejects non-string values")
    func customConformanceRejectsNonStringValues() {
        let args = ToolArguments(["site": .int(42)], toolName: "lookup")
        #expect(args.optional("site", as: URL.self) == nil)
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Argument 'site' is not of type URL"
        )) {
            _ = try args.require("site", as: URL.self)
        }
    }

    // MARK: - Strict optional (AC-003)

    @Test("optionalValue returns the value when present and well-typed")
    func optionalValueReturnsValueWhenPresent() throws {
        let args = ToolArguments(["city": .string("Tokyo")])
        #expect(try args.optionalValue("city", as: String.self) == "Tokyo")
    }

    @Test("optionalValue returns nil when the key is missing")
    func optionalValueReturnsNilWhenMissing() throws {
        let args = ToolArguments([:])
        #expect(try args.optionalValue("city", as: String.self) == nil)
    }

    @Test("optionalValue throws invalidToolArguments on mistyped values")
    func optionalValueMistypedThrows() {
        let args = ToolArguments(["precision": .string("high")], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Argument 'precision' is not of type Int"
        )) {
            _ = try args.optionalValue("precision", as: Int.self)
        }
    }

    @Test("optionalValue distinguishes missing from mistyped for custom conformances")
    func optionalValueCustomConformance() throws {
        let missing = ToolArguments([:])
        #expect(try missing.optionalValue("site", as: URL.self) == nil)
        let present = ToolArguments(["site": .string("https://example.com")])
        #expect(try present.optionalValue("site", as: URL.self) == URL(string: "https://example.com"))
        let mistyped = ToolArguments(["site": .int(42)], toolName: "lookup")
        #expect(throws: AgentError.invalidToolArguments(
            toolName: "lookup",
            reason: "Argument 'site' is not of type URL"
        )) {
            _ = try mistyped.optionalValue("site", as: URL.self)
        }
    }
}
