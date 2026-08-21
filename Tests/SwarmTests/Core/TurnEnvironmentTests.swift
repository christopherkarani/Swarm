// TurnEnvironmentTests.swift
// SwarmTests
//
// Deterministic clock & identity seam tests (spec ticket T1, AC-001/AC-002).

import Foundation
import os.lock
@testable import Swarm
import Testing

// MARK: - Fakes

/// A mutable, Sendable fake clock for tests.
struct MutableTestClock: Sendable {
    private let storage: OSAllocatedUnfairLock<Date>

    init(start: Date) {
        storage = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date {
        storage.withLock { $0 }
    }

    func advance(_ interval: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// A deterministic `TurnEnvironment` fake: fixed base instant and a
/// monotonically increasing sequence of UUIDs.
struct FixedEnvironment {
    let base: Date
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    init(base: Date) {
        self.base = base
    }

    var environment: TurnEnvironment {
        TurnEnvironment(
            now: { base },
            newUUID: {
                let n = counter.withLock {
                    $0 += 1
                    return $0
                }
                return UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d", n
                    )
                )!
            }
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
