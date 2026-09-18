// ToolArgumentsLatticeTests.swift
// SwarmTests
//
// Pins ToolArguments.require / optional to the ToolArgumentValue lattice.
// URL.self is intentionally omitted: it must not compile (AC-003).

@testable import Swarm
import Testing

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
}
