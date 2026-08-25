// AgentContextKeySurfaceTests.swift
// SwarmTests
//
// Typed ContextKey orchestration slots on the unified AgentContext store.

import Foundation
@testable import Swarm
import Testing

// MARK: - Collision Contexts

private struct ContextTypeA: AgentContextProviding {
    static let contextKey = "same"
    let n: Int
}

private struct ContextTypeB: AgentContextProviding {
    static let contextKey = "same"
    let n: Int
}

// MARK: - AgentContextKeySurfaceTests

@Suite("AgentContext key surfaces")
struct AgentContextKeySurfaceTests {

    // MARK: - Orchestration Key Names (REQ-001)

    @Test("orchestration ContextKey names match AgentContextKey raw values")
    func orchestrationKeyNamesMatchLegacyRawValues() {
        #expect(ContextKey<String>.originalInput.name == AgentContextKey.originalInput.rawValue)
        #expect(ContextKey<String>.previousOutput.name == AgentContextKey.previousOutput.rawValue)
        #expect(ContextKey<String>.currentAgentName.name == AgentContextKey.currentAgentName.rawValue)
        #expect(ContextKey<[String]>.executionPath.name == AgentContextKey.executionPath.rawValue)
        #expect(ContextKey<Date>.startTime.name == AgentContextKey.startTime.rawValue)

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

        #expect(snapshot[AgentContextKey.originalInput.rawValue] == .string("User query"))
        #expect(snapshot[AgentContextKey.executionPath.rawValue] == .array([.string("Fetcher")]))
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

    // MARK: - Deprecated AgentContextKey (REQ-005)

    @Test("deprecated AgentContextKey get and set still function")
    func deprecatedAgentContextKeyAccessorsStillWork() async {
        let context = AgentContext(input: "seed")

        await context.set(AgentContextKey.metadata, value: .string("meta"))
        #expect(await context.get(AgentContextKey.metadata) == .string("meta"))
        #expect(await context.get("metadata") == .string("meta"))

        await context.set(AgentContextKey.previousOutput, value: .string("legacy"))
        #expect(await context.get(AgentContextKey.previousOutput)?.stringValue == "legacy")
        #expect(await context.get(.previousOutput) == "legacy")
    }

    // MARK: - Type-Indexed Typed Contexts (REQ-006, AC-003)

    @Test("two AgentContextProviding types that share contextKey both persist")
    func sharedContextKeyTypesBothPersist() async {
        let context = AgentContext(input: "seed")
        await context.setTyped(ContextTypeA(n: 1))
        await context.setTyped(ContextTypeB(n: 2))

        #expect(ContextTypeA.contextKey == ContextTypeB.contextKey)
        #expect(await context.typed(ContextTypeA.self)?.n == 1)
        #expect(await context.typed(ContextTypeB.self)?.n == 2)
        #expect(await context.hasTyped(ContextTypeA.self))
        #expect(await context.hasTyped(ContextTypeB.self))
    }
}
