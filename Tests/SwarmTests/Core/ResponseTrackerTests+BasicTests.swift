// ResponseTrackerTests+BasicTests.swift
// SwarmTests
//
// Basic tests for ResponseTracker: initialization, record/retrieve, and session isolation.

import Foundation
@testable import Swarm
import Testing

// MARK: - ResponseTrackerBasicTests

@Suite("ResponseTracker Basic Tests")
struct ResponseTrackerBasicTests {
    // MARK: Internal

    // MARK: - Record and Retrieve Tests

    @Test("Record and retrieve response")
    func recordAndRetrieveResponse() async {
        let tracker = ResponseTracker()
        let response = makeTestResponse(id: "test_id_123", output: "Hello, World!")

        await tracker.recordResponse(response, sessionId: "session1")

        let retrieved = await tracker.getResponse(responseId: "test_id_123", sessionId: "session1")

        #expect(retrieved != nil)
        #expect(retrieved?.responseId == "test_id_123")
        #expect(retrieved?.output == "Hello, World!")
        #expect(retrieved?.agentName == "TestAgent")
    }

    @Test("Retrieve non-existent response returns nil")
    func retrieveNonExistentResponseReturnsNil() async {
        let tracker = ResponseTracker()

        let retrieved = await tracker.getResponse(responseId: "non_existent", sessionId: "session1")

        #expect(retrieved == nil)
    }

    @Test("Retrieve from non-existent session returns nil")
    func retrieveFromNonExistentSessionReturnsNil() async {
        let tracker = ResponseTracker()
        let response = makeTestResponse()

        await tracker.recordResponse(response, sessionId: "session1")

        let retrieved = await tracker.getResponse(responseId: response.responseId, sessionId: "session2")

        #expect(retrieved == nil)
    }

    // MARK: - Session Isolation Tests

    @Test("Sessions are isolated")
    func sessionIsolation() async {
        let tracker = ResponseTracker()

        // Add responses to different sessions
        let response1 = makeTestResponse(id: "session1_resp", output: "Session 1 Output")
        let response2 = makeTestResponse(id: "session2_resp", output: "Session 2 Output")
        let response3 = makeTestResponse(id: "session3_resp", output: "Session 3 Output")

        await tracker.recordResponse(response1, sessionId: "session1")
        await tracker.recordResponse(response2, sessionId: "session2")
        await tracker.recordResponse(response3, sessionId: "session3")

        // Verify each session has only its own response
        let session1Count = await tracker.getCount(for: "session1")
        let session2Count = await tracker.getCount(for: "session2")
        let session3Count = await tracker.getCount(for: "session3")

        #expect(session1Count == 1)
        #expect(session2Count == 1)
        #expect(session3Count == 1)

        // Cross-session retrieval should fail
        let crossRetrieve = await tracker.getResponse(responseId: "session1_resp", sessionId: "session2")
        #expect(crossRetrieve == nil)
    }

    @Test("Session isolation with history limits")
    func sessionIsolationWithHistoryLimits() async {
        let tracker = ResponseTracker(maxHistorySize: 3)

        // Fill session1 to capacity
        for i in 0..<5 {
            let response = makeTestResponse(id: "s1_\(i)")
            await tracker.recordResponse(response, sessionId: "session1")
        }

        // Add to session2
        for i in 0..<2 {
            let response = makeTestResponse(id: "s2_\(i)")
            await tracker.recordResponse(response, sessionId: "session2")
        }

        // Session1 should have 3 (limited), session2 should have 2
        let s1Count = await tracker.getCount(for: "session1")
        let s2Count = await tracker.getCount(for: "session2")

        #expect(s1Count == 3)
        #expect(s2Count == 2)

        // Session1's oldest should be trimmed
        let s1Old = await tracker.getResponse(responseId: "s1_0", sessionId: "session1")
        #expect(s1Old == nil)

        // Session2's responses should all exist
        let s2First = await tracker.getResponse(responseId: "s2_0", sessionId: "session2")
        #expect(s2First != nil)
    }

    // MARK: - Get All Session IDs Tests

    @Test("Get all session IDs")
    func testGetAllSessionIds() async {
        let tracker = ResponseTracker()

        await tracker.recordResponse(makeTestResponse(), sessionId: "alpha")
        await tracker.recordResponse(makeTestResponse(), sessionId: "beta")
        await tracker.recordResponse(makeTestResponse(), sessionId: "gamma")

        let sessionIds = await tracker.getAllSessionIds()

        #expect(sessionIds.count == 3)
        #expect(sessionIds.contains("alpha"))
        #expect(sessionIds.contains("beta"))
        #expect(sessionIds.contains("gamma"))
    }

    @Test("Get all session IDs when empty")
    func getAllSessionIdsWhenEmpty() async {
        let tracker = ResponseTracker()

        let sessionIds = await tracker.getAllSessionIds()

        #expect(sessionIds.isEmpty)
    }

    // MARK: - Response Content Verification Tests

    @Test("Response content is preserved correctly")
    func responseContentIsPreservedCorrectly() async {
        let tracker = ResponseTracker()
        let timestamp = Date()

        let original = AgentResponse(
            responseId: "unique_id_12345",
            output: "This is a test output with special characters: @#$%^&*()",
            agentName: "SpecialAgent",
            timestamp: timestamp,
            metadata: ["key": .string("value"), "number": .int(42)],
            toolCalls: [
                ToolCallRecord(
                    toolName: "test_tool",
                    arguments: ["arg": .string("val")],
                    result: .bool(true),
                    duration: .seconds(1)
                )
            ],
            usage: TokenUsage(inputTokens: 100, outputTokens: 50)
        )

        await tracker.recordResponse(original, sessionId: "test_session")

        let retrieved = await tracker.getResponse(responseId: "unique_id_12345", sessionId: "test_session")

        #expect(retrieved != nil)
        #expect(retrieved?.responseId == original.responseId)
        #expect(retrieved?.output == original.output)
        #expect(retrieved?.agentName == original.agentName)
        #expect(retrieved?.timestamp == original.timestamp)
        #expect(retrieved?.metadata == original.metadata)
        #expect(retrieved?.toolCalls.count == original.toolCalls.count)
        #expect(retrieved?.usage?.inputTokens == 100)
        #expect(retrieved?.usage?.outputTokens == 50)
    }

    @Test("Invalid init values are coerced to safe bounds")
    func invalidInitValuesAreCoerced() {
        let tracker = ResponseTracker(maxHistorySize: 0, maxSessions: 0)
        #expect(tracker.maxHistorySize == 1)
        #expect(tracker.maxSessions == 1)
    }

    @Test("Invalid record inputs are dropped without crashing")
    func invalidRecordInputsAreDropped() async {
        let tracker = ResponseTracker()
        let invalidResponse = makeTestResponse(id: "")

        await tracker.recordResponse(invalidResponse, sessionId: "valid-session")
        await tracker.recordResponse(makeTestResponse(id: "ok"), sessionId: "")

        #expect(await tracker.getCount(for: "valid-session") == 0)
        #expect(await tracker.getAllSessionIds().isEmpty)
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
