// TurnEnvironmentTests.swift
// SwarmTests
//
// Deterministic clock & identity seam tests (spec ticket T1, AC-001/AC-002).

import Foundation
@testable import Swarm
import Testing

// MARK: - Fakes

/// A mutable fake clock for tests.
///
/// `@unchecked Sendable` because `date` is guarded by `lock` (established
/// repo test pattern, e.g. `TraceHeaderState` in WebSearchSupportTests).
/// Uses `NSLock` rather than `OSAllocatedUnfairLock` so the suite still
/// compiles on Linux CI.
final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(start: Date) {
        self.date = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date = date.addingTimeInterval(interval)
    }
}

/// A lock-guarded monotonically increasing fake UUID generator.
private final class SequentialIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d", count
            )
        )!
    }
}

/// A deterministic `TurnEnvironment` fake: fixed base instant and a
/// monotonically increasing sequence of UUIDs.
struct FixedEnvironment {
    let base: Date
    private let ids = SequentialIDGenerator()

    init(base: Date) {
        self.base = base
    }

    var environment: TurnEnvironment {
        TurnEnvironment(
            now: { base },
            newUUID: { ids.next() }
        )
    }
}

// MARK: - TurnEnvironmentTests

@Suite("TurnEnvironment Tests")
struct TurnEnvironmentTests {
    // MARK: - AC-001: deterministic values across identical runs

    private func makeValueSequence(environment: TurnEnvironment) -> [String] {
        var serialized: [String] = []

        // ToolCall (AgentEvent.swift)
        let call = ToolCall(
            id: environment.newUUID(),
            toolName: "search",
            arguments: ["q": .string("hello")],
            timestamp: environment.now()
        )
        serialized.append("\(call.id.uuidString)|\(call.timestamp.timeIntervalSince1970)")

        // ToolCallRecord (AgentResponse.swift)
        let record = ToolCallRecord(
            toolName: "search",
            arguments: ["q": .string("hello")],
            duration: .seconds(1),
            timestamp: environment.now(),
            outcome: .success(.string("ok"))
        )
        serialized.append("\(record.timestamp.timeIntervalSince1970)")

        // Transcript entry (SwarmTranscript.swift)
        let message = SwarmTranscriptCodec.encodeMessage(
            role: .assistant,
            content: "hi",
            timestamp: environment.now(),
            messageID: environment.newUUID()
        )
        serialized.append("\(message.id.uuidString)|\(message.timestamp.timeIntervalSince1970)")
        serialized.append(message.metadata[SwarmTranscriptCodec.entryIDKey] ?? "")

        // AgentResponse (AgentResponse.swift)
        let response = AgentResponse(
            responseId: environment.newID(),
            output: "done",
            agentName: "TestAgent",
            timestamp: environment.now()
        )
        serialized.append("\(response.responseId)|\(response.timestamp.timeIntervalSince1970)")

        // ToolExecutionResult (Tools/ToolExecutionResult.swift)
        let toolResult = ToolExecutionResult(
            toolName: "search",
            arguments: ["q": .string("hello")],
            result: .success(.string("ok")),
            duration: .seconds(1),
            timestamp: environment.now()
        )
        serialized.append("\(toolResult.timestamp.timeIntervalSince1970)")

        return serialized
    }

    @Test("Deterministic environment produces identical ids/timestamps across two identical runs")
    func deterministicValuesAcrossRuns() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let first = makeValueSequence(environment: FixedEnvironment(base: base).environment)
        let second = makeValueSequence(environment: FixedEnvironment(base: base).environment)

        #expect(first == second)
        #expect(!first.isEmpty)
        // Every generated id must be present and non-empty.
        #expect(first.allSatisfy { !$0.isEmpty })
    }

    // MARK: - AC-002: ResponseTracker window flips with a fake clock

    @Test("ResponseTracker rate-limit window flips when fake clock advances past it")
    func responseTrackerWindowFlipsWithFakeClock() async {
        let clock = MutableTestClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let tracker = ResponseTracker(maxHistorySize: 10, maxSessions: nil, now: { clock.now })

        func response(id: String, timestamp: Date) -> AgentResponse {
            AgentResponse(
                responseId: id,
                output: "output",
                agentName: "TestAgent",
                timestamp: timestamp
            )
        }

        // A session accessed exactly at the clock's current instant.
        await tracker.recordResponse(
            response(id: "s1_1", timestamp: clock.now),
            sessionId: "session_1"
        )

        // Window of 60s: nothing is stale yet.
        let removedBefore = await tracker.removeSessions(notAccessedWithin: 60)
        #expect(removedBefore == 0)
        #expect(await tracker.getCount(for: "session_1") == 1)

        // Advance the fake clock past the window: the decision flips,
        // with no Task.sleep involved.
        clock.advance(61)
        let removedAfter = await tracker.removeSessions(notAccessedWithin: 60)
        #expect(removedAfter == 1)
        #expect(await tracker.getCount(for: "session_1") == 0)
    }
}
