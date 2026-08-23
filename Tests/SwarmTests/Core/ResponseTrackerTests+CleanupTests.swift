// ResponseTrackerTests+CleanupTests.swift
// SwarmTests
//
// Session cleanup and metadata tests for ResponseTracker.

import Foundation
@testable import Swarm
import Testing

// MARK: - ResponseTrackerCleanupTests

@Suite("ResponseTracker Cleanup Tests")
struct ResponseTrackerCleanupTests {
    // MARK: Internal

    // MARK: - Session Cleanup Tests

    @Test("Remove sessions by absolute date threshold")
    func removeSessionsByAbsoluteDate() async throws {
        let tracker = ResponseTracker()

        // Create a reference time
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-1 * 24 * 3600)

        // Record responses for old session (simulate old timestamps)
        await tracker.recordResponse(
            makeTestResponse(id: "old_1", timestamp: oneDayAgo.addingTimeInterval(-1)),
            sessionId: "old_session"
        )

        // Record responses for recent session
        await tracker.recordResponse(makeTestResponse(id: "recent_1"), sessionId: "recent_session")

        // Verify both sessions exist
        #expect(await tracker.getCount(for: "old_session") == 1)
        #expect(await tracker.getCount(for: "recent_session") == 1)

        // Remove sessions older than 1 day
        let removed = await tracker.removeSessions(lastAccessedBefore: oneDayAgo)

        // Should remove old session but keep recent
        #expect(removed == 1)
        #expect(await tracker.getCount(for: "old_session") == 0)
        #expect(await tracker.getCount(for: "recent_session") == 1)
    }

    @Test("Remove sessions by time interval")
    func removeSessionsByTimeInterval() async throws {
        // Deterministic fake clock instead of Task.sleep (spec T1 / AC-002).
        let clock = MutableTestClock(start: Date(timeIntervalSince1970: 1_000_000))
        let tracker = ResponseTracker(now: { clock.now })

        // Record some responses with explicit timestamps relative to the fake clock
        await tracker.recordResponse(
            makeTestResponse(id: "resp_1", timestamp: clock.now.addingTimeInterval(-0.1)),
            sessionId: "session_1"
        )
        await tracker.recordResponse(
            makeTestResponse(id: "resp_2", timestamp: clock.now.addingTimeInterval(-0.02)),
            sessionId: "session_2"
        )

        // Record another response for session_2 (making it more recent)
        await tracker.recordResponse(
            makeTestResponse(id: "resp_3", timestamp: clock.now),
            sessionId: "session_2"
        )

        // Remove sessions not accessed within 50ms of the fake clock
        let removed = await tracker.removeSessions(notAccessedWithin: 0.05)

        // session_1 should be removed, session_2 should remain
        #expect(removed == 1)
        #expect(await tracker.getCount(for: "session_1") == 0)
        #expect(await tracker.getCount(for: "session_2") == 2)
    }

    @Test("Remove sessions returns zero when no sessions match")
    func removeSessionsNoMatches() async {
        let tracker = ResponseTracker()

        // Record some recent responses
        await tracker.recordResponse(makeTestResponse(id: "resp_1"), sessionId: "session_1")
        await tracker.recordResponse(makeTestResponse(id: "resp_2"), sessionId: "session_2")

        // Try to remove sessions older than 1 year ago (none should match)
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 3600)
        let removed = await tracker.removeSessions(lastAccessedBefore: oneYearAgo)

        #expect(removed == 0)
        #expect(await tracker.getCount(for: "session_1") == 1)
        #expect(await tracker.getCount(for: "session_2") == 1)
    }

    @Test("Remove sessions on empty tracker")
    func removeSessionsEmptyTracker() async {
        let tracker = ResponseTracker()

        let removed = await tracker.removeSessions(lastAccessedBefore: Date())

        #expect(removed == 0)
    }

    // MARK: - Session Metadata Tests

    @Test("Get session metadata for existing session")
    func getSessionMetadata() async {
        let tracker = ResponseTracker()

        // Record some responses
        await tracker.recordResponse(makeTestResponse(id: "resp_1"), sessionId: "test_session")
        await tracker.recordResponse(makeTestResponse(id: "resp_2"), sessionId: "test_session")
        await tracker.recordResponse(makeTestResponse(id: "resp_3"), sessionId: "test_session")

        let metadata = await tracker.getSessionMetadata(for: "test_session")

        #expect(metadata != nil)
        #expect(metadata?.sessionId == "test_session")
        #expect(metadata?.responseCount == 3)
        #expect(metadata?.lastAccessTime != nil)
    }

    @Test("Get session metadata for non-existent session")
    func getSessionMetadataForNonExistentSession() async {
        let tracker = ResponseTracker()

        let metadata = await tracker.getSessionMetadata(for: "non_existent")

        #expect(metadata == nil)
    }

    @Test("Get all session metadata")
    func getAllSessionMetadata() async {
        let tracker = ResponseTracker()

        // Record responses for multiple sessions
        await tracker.recordResponse(makeTestResponse(id: "a_1"), sessionId: "session_a")
        await tracker.recordResponse(makeTestResponse(id: "b_1"), sessionId: "session_b")
        await tracker.recordResponse(makeTestResponse(id: "b_2"), sessionId: "session_b")
        await tracker.recordResponse(makeTestResponse(id: "c_1"), sessionId: "session_c")

        let allMetadata = await tracker.getAllSessionMetadata()

        #expect(allMetadata.count == 3)

        // Find each session in metadata
        let sessionA = allMetadata.first { $0.sessionId == "session_a" }
        let sessionB = allMetadata.first { $0.sessionId == "session_b" }
        let sessionC = allMetadata.first { $0.sessionId == "session_c" }

        #expect(sessionA?.responseCount == 1)
        #expect(sessionB?.responseCount == 2)
        #expect(sessionC?.responseCount == 1)
    }

    @Test("Get all session metadata returns empty for empty tracker")
    func getAllSessionMetadataEmpty() async {
        let tracker = ResponseTracker()

        let allMetadata = await tracker.getAllSessionMetadata()

        #expect(allMetadata.isEmpty)
    }

    @Test("Session metadata is sorted by recency")
    func sessionMetadataSortedByRecency() async throws {
        let tracker = ResponseTracker()

        // Record sessions in order: A, B, C using explicit increasing
        // timestamps instead of Task.sleep (deterministic, spec T1 / AC-005).
        let base = Date(timeIntervalSince1970: 2_000_000)
        await tracker.recordResponse(
            makeTestResponse(id: "a_1", timestamp: base),
            sessionId: "session_a"
        )
        await tracker.recordResponse(
            makeTestResponse(id: "b_1", timestamp: base.addingTimeInterval(10)),
            sessionId: "session_b"
        )
        await tracker.recordResponse(
            makeTestResponse(id: "c_1", timestamp: base.addingTimeInterval(20)),
            sessionId: "session_c"
        )

        let allMetadata = await tracker.getAllSessionMetadata()

        // Should be sorted newest first: C, B, A
        #expect(allMetadata.count == 3)
        #expect(allMetadata[0].sessionId == "session_c")
        #expect(allMetadata[1].sessionId == "session_b")
        #expect(allMetadata[2].sessionId == "session_a")
    }

    @Test("Cleanup removes both history and access times")
    func cleanupRemovesBothHistoryAndAccessTimes() async {
        let tracker = ResponseTracker()

        // Record some responses
        await tracker.recordResponse(makeTestResponse(id: "resp_1"), sessionId: "session_1")
        await tracker.recordResponse(makeTestResponse(id: "resp_2"), sessionId: "session_2")

        // Verify sessions exist
        #expect(await tracker.getAllSessionIds().count == 2)

        // Remove all sessions
        let removed = await tracker.removeSessions(lastAccessedBefore: Date())

        #expect(removed == 2)
        #expect(await tracker.getAllSessionIds().isEmpty)
        #expect(await tracker.getAllSessionMetadata().isEmpty)
    }

    // MARK: Private

    // MARK: - Test Helpers

    private func makeTestResponse(
        id: String = UUID().uuidString,
        output: String = "test output",
        agentName: String = "TestAgent",
        timestamp: Date = Date()
    ) -> AgentResponse {
        AgentResponse(
            responseId: id,
            output: output,
            agentName: agentName,
            timestamp: timestamp,
            metadata: [:],
            toolCalls: [],
            usage: nil
        )
    }
}
