// AgentResponseProjectionTests.swift
// SwarmTests
//
// Duplicate tool-call ids must last-win without trapping.

import Foundation
@testable import Swarm
import Testing

@Suite("Agent Response Projection", .ephemeralDefaultStores)
struct AgentResponseProjectionTests {
    @Test("Duplicate tool-call ids keep the last call and do not trap")
    func duplicateToolCallIDsKeepLastCall() throws {
        let result = duplicateIDResult()
        let response = AgentResponseProjection.make(from: result, responseID: "r", agentName: "A")

        #expect(response.responseId == "r")
        #expect(response.agentName == "A")
        #expect(response.output == "done")
        #expect(response.iterationCount == 2)
        #expect(response.usage == TokenUsage(inputTokens: 3, outputTokens: 5))
        #expect(response.metadata["k"] == .string("v"))
        try #require(response.toolCalls.count == 2)
        #expect(response.toolCalls[0].toolName == "last")
        #expect(response.toolCalls[0].arguments["n"] == .int(2))
        #expect(response.toolCalls[0].duration == .milliseconds(1))
        #expect(response.toolCalls[0].result == .string("first-out"))
        #expect(response.toolCalls[1].toolName == "last")
        #expect(response.toolCalls[1].arguments["n"] == .int(2))
        #expect(response.toolCalls[1].duration == .milliseconds(2))
        #expect(response.toolCalls[1].result == .string("last-out"))
    }

    @Test("Distinct tool-call ids keep each call")
    func distinctToolCallIDsKeepEachCall() {
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let secondID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let timestamp = Date(timeIntervalSince1970: 10)
        let result = AgentResult(
            output: "ok",
            invocations: [
                ToolInvocation(
                    call: ToolCall(
                        id: firstID,
                        toolName: "alpha",
                        arguments: ["n": .int(1)],
                        timestamp: timestamp
                    ),
                    duration: .milliseconds(1),
                    outcome: .success(.string("a"))
                ),
                ToolInvocation(
                    call: ToolCall(
                        id: secondID,
                        toolName: "beta",
                        arguments: ["n": .int(2)],
                        timestamp: timestamp
                    ),
                    duration: .milliseconds(2),
                    outcome: .success(.string("b"))
                ),
            ]
        )

        let response = AgentResponseProjection.make(from: result, responseID: "r", agentName: "A")
        #expect(response.toolCalls.map(\.toolName) == ["alpha", "beta"])
        #expect(response.toolCalls.map(\.result) == [.string("a"), .string("b")])
    }

    @Test("Agent.makeResponse uses the same last-wins join")
    func agentMakeResponseUsesProjection() throws {
        let result = duplicateIDResult()
        let agent = try Agent(
            configuration: AgentConfiguration.default.name("A"),
            inferenceProvider: MockInferenceProvider(responses: ["unused"])
        )
        let projected = AgentResponseProjection.make(from: result, responseID: "r", agentName: "A")
        let response = agent.makeResponse(from: result, responseID: "r")

        #expect(response.responseId == projected.responseId)
        #expect(response.agentName == projected.agentName)
        #expect(response.output == projected.output)
        #expect(response.metadata == projected.metadata)
        #expect(response.usage == projected.usage)
        #expect(response.iterationCount == projected.iterationCount)
        #expect(response.toolCalls.map(\.toolName) == projected.toolCalls.map(\.toolName))
        #expect(response.toolCalls.map(\.arguments) == projected.toolCalls.map(\.arguments))
        #expect(response.toolCalls.map(\.duration) == projected.toolCalls.map(\.duration))
        #expect(response.toolCalls.map(\.timestamp) == projected.toolCalls.map(\.timestamp))
        #expect(response.toolCalls.map(\.outcome) == projected.toolCalls.map(\.outcome))
    }

    @Test("AgentRuntime.runWithResponse default uses the same last-wins join")
    func runtimeDefaultUsesProjection() async throws {
        let result = duplicateIDResult()
        let runtime = FixedResultRuntime(
            configuration: AgentConfiguration.default.name("A"),
            result: result
        )
        let response = try await runtime.runWithResponse("input")
        let projected = AgentResponseProjection.make(
            from: result,
            responseID: response.responseId,
            agentName: "A"
        )

        #expect(response.agentName == "A")
        #expect(response.output == projected.output)
        #expect(response.toolCalls.map(\.toolName) == projected.toolCalls.map(\.toolName))
        #expect(response.toolCalls.map(\.arguments) == projected.toolCalls.map(\.arguments))
        #expect(response.toolCalls.map(\.duration) == projected.toolCalls.map(\.duration))
        #expect(response.toolCalls.map(\.timestamp) == projected.toolCalls.map(\.timestamp))
        #expect(response.toolCalls.map(\.outcome) == projected.toolCalls.map(\.outcome))
    }

    // MARK: - Fixtures

    private func duplicateIDResult() -> AgentResult {
        let sharedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let timestamp = Date(timeIntervalSince1970: 10)
        return AgentResult(
            output: "done",
            invocations: [
                ToolInvocation(
                    call: ToolCall(
                        id: sharedID,
                        toolName: "first",
                        arguments: ["n": .int(1)],
                        timestamp: timestamp
                    ),
                    duration: .milliseconds(1),
                    outcome: .success(.string("first-out"))
                ),
                ToolInvocation(
                    call: ToolCall(
                        id: sharedID,
                        toolName: "last",
                        arguments: ["n": .int(2)],
                        timestamp: timestamp
                    ),
                    duration: .milliseconds(2),
                    outcome: .success(.string("last-out"))
                ),
            ],
            iterationCount: 2,
            tokenUsage: TokenUsage(inputTokens: 3, outputTokens: 5),
            metadata: ["k": .string("v")]
        )
    }
}

private struct FixedResultRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "test"
    nonisolated let configuration: AgentConfiguration
    let result: AgentResult

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        _ = (input, session, observer)
        return result
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        _ = (input, session, observer)
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancel() async {}
}
