// AgentContextKeySurfaceTests.swift
// SwarmTests
//
// Typed ContextKey orchestration slots on the unified AgentContext store.

import Foundation
@testable import Swarm
import Testing

// MARK: - AgentContextKeySurfaceTests

@Suite("AgentContext key surfaces")
struct AgentContextKeySurfaceTests {

    // MARK: - Orchestration Key Names (REQ-001)

    @Test("orchestration ContextKey names keep their wire names")
    func orchestrationKeyNamesKeepWireNames() {
        #expect(ContextKey<String>.originalInput.name == "original_input")
        #expect(ContextKey<String>.previousOutput.name == "previous_output")
        #expect(ContextKey<String>.currentAgentName.name == "current_agent_name")
        #expect(ContextKey<[String]>.executionPath.name == "execution_path")
        #expect(ContextKey<Date>.startTime.name == "start_time")
    }

    // MARK: - Snapshot Wire (AC-001, REQ-003)

    @Test("init recordExecution and previous output keep today's snapshot shapes")
    func snapshotWireFormatUnchanged() async {
        let context = AgentContext(input: "User query")
        await context.recordExecution(agentName: "Fetcher")
        await context.setPreviousOutput(AgentResult(output: "fetched"))

        let snapshot = await context.snapshot
        #expect(snapshot["original_input"] == .string("User query"))
        #expect(snapshot["previous_output"] == .string("fetched"))
        #expect(snapshot["current_agent_name"] == .string("Fetcher"))
        #expect(snapshot["execution_path"] == .array([.string("Fetcher")]))
        #expect(snapshot["start_time"] == .double(context.createdAt.timeIntervalSince1970))
    }

    @Test("typed ContextKey set updates the same snapshot slots")
    func typedSetUpdatesSnapshotSlots() async {
        let context = AgentContext(input: "initial")
        await context.set(.originalInput, "hello")
        await context.set(.previousOutput, "done")
        await context.set(.currentAgentName, "Writer")
        await context.set(.executionPath, ["Writer"])

        let snapshot = await context.snapshot
        #expect(snapshot["original_input"] == .string("hello"))
        #expect(snapshot["previous_output"] == .string("done"))
        #expect(snapshot["current_agent_name"] == .string("Writer"))
        #expect(snapshot["execution_path"] == .array([.string("Writer")]))

        #expect(await context.get(.originalInput) == "hello")
        #expect(await context.get(.previousOutput) == "done")
        #expect(await context.get(.currentAgentName) == "Writer")
        #expect(await context.get(.executionPath) == ["Writer"])
    }

    // MARK: - Primitive ContextKey Accessors (REQ-004)

    @Test("primitive String Int Bool Double and array keys round-trip")
    func primitiveKeysRoundTrip() async {
        let context = AgentContext(input: "seed")

        await context.set(.userID, "user-123")
        await context.set(.retryCount, 3)
        await context.set(.isAuthenticated, true)
        await context.set(ContextKey<Double>("score"), 2.5)
        await context.set(.tags, ["alpha", "beta"])

        #expect(await context.get(.userID) == "user-123")
        #expect(await context.get(.retryCount) == 3)
        #expect(await context.get(.isAuthenticated) == true)
        #expect(await context.get(ContextKey<Double>("score")) == 2.5)
        #expect(await context.get(.tags) == ["alpha", "beta"])

        #expect(await context.getTyped(.userID) == "user-123")
        #expect(await context.getTyped(.retryCount) == 3)
    }

    @Test("Date ContextKey set and setTyped store epoch seconds")
    func dateKeysStoreEpochSeconds() async {
        let context = AgentContext(input: "seed")
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        await context.set(.startTime, date)
        #expect(await context.get(.startTime)?.timeIntervalSince1970 == 1_700_000_000)
        #expect(await context.getTyped(.startTime)?.timeIntervalSince1970 == 1_700_000_000)

        let later = Date(timeIntervalSince1970: 1_800_000_000)
        await context.setTyped(.timestamp, value: later)
        #expect(await context.getTyped(.timestamp)?.timeIntervalSince1970 == 1_800_000_000)
        #expect(await context.get(.timestamp)?.timeIntervalSince1970 == 1_800_000_000)
    }

    // MARK: - Raw String Writes

    @Test("raw string write replaces a typed orchestration slot")
    func rawStringWriteReplacesTypedOrchestrationSlot() async {
        let context = AgentContext(input: "seed")
        #expect(await context.get(.originalInput) == "seed")

        await context.set("original_input", value: .string("raw-original"))
        #expect(await context.get(.originalInput) == "raw-original")
        #expect(await context.snapshot["original_input"] == .string("raw-original"))
    }
}
