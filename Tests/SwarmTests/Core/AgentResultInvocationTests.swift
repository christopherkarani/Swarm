// AgentResultInvocationTests.swift
// SwarmTests
//
// Pins Builder pending/completed pairing and makeResponse invocation mapping.

import Foundation
@testable import Swarm
import Testing

@Suite("AgentResult invocation pairing", .ephemeralDefaultStores)
struct AgentResultInvocationTests {
    @Test("Agent+ProviderResolution.swift does not re-join with uniqueKeysWithValues")
    func providerResolutionDoesNotUseUniqueKeysWithValues() throws {
        let source = try String(contentsOf: providerResolutionSourceURL, encoding: .utf8)
        #expect(
            source.contains("uniqueKeysWithValues") == false,
            "makeResponse must map result.invocations instead of Dictionary(uniqueKeysWithValues:)"
        )
    }

    @Test("makeResponse does not trap when two invocations share a call ID")
    func makeResponseAllowsDuplicateInvocationCallIDs() throws {
        let agent = try Agent(
            instructions: "Reply shortly.",
            inferenceProvider: MockInferenceProvider(responses: ["unused"])
        )
        let callID = UUID()
        let call = ToolCall(id: callID, toolName: "a")
        let first = ToolInvocation(call: call, duration: .zero, outcome: .success(.null))
        let second = ToolInvocation(call: call, duration: .milliseconds(1), outcome: .success(.int(1)))
        let result = AgentResult(output: "x", invocations: [first, second])

        let response = agent.makeResponse(from: result, responseID: "r")

        #expect(response.toolCalls.count == 2)
        #expect(response.toolCalls[0].callId == callID)
        #expect(response.toolCalls[1].callId == callID)
        #expect(response.toolCalls[0].toolName == "a")
        #expect(response.toolCalls[1].toolName == "a")
        #expect(response.toolCalls[0].result == .null)
        #expect(response.toolCalls[1].result == .int(1))
        #expect(response.toolCalls[0].duration == .zero)
        #expect(response.toolCalls[1].duration == .milliseconds(1))
    }

    @Test("addToolResult ignores a call ID with no pending call")
    func addToolResultDoesNotCompleteUnknownCallID() {
        let builder = AgentResult.Builder()
        _ = builder.setOutput("done")
        let orphan = ToolResult.success(
            callId: UUID(),
            output: .string("lost"),
            duration: .zero
        )
        _ = builder.addToolResult(orphan)

        let result = builder.build()
        #expect(result.invocations.isEmpty)
        #expect(result.toolCalls.isEmpty)
        #expect(result.toolResults.isEmpty)
    }

    @Test("addToolResult pairs the first pending call with a matching call ID")
    func addToolResultPairsFirstPendingMatch() {
        let builder = AgentResult.Builder()
        let callID = UUID()
        let first = ToolCall(id: callID, toolName: "first")
        let second = ToolCall(id: callID, toolName: "second")
        _ = builder.addToolCall(first)
        _ = builder.addToolCall(second)
        _ = builder.addToolResult(
            ToolResult.success(callId: callID, output: .int(1), duration: .zero)
        )

        let result = builder.build()
        #expect(result.invocations.count == 1)
        #expect(result.invocations[0].call.toolName == "first")
        #expect(result.invocations[0].result.output == .int(1))
    }

    @Test("build omits unpaired pending calls")
    func buildOmitsUnpairedPendingCalls() {
        let builder = AgentResult.Builder()
        _ = builder.setOutput("partial")
        _ = builder.addToolCall(ToolCall(toolName: "pending"))

        let result = builder.build()
        #expect(result.invocations.isEmpty)
        #expect(result.toolCalls.isEmpty)
    }

    @Test("addInvocation clears a matching pending call so a later result cannot pair twice")
    func addInvocationRemovesMatchingPending() {
        let builder = AgentResult.Builder()
        let call = ToolCall(toolName: "echo")
        let invocation = ToolInvocation(call: call, duration: .zero, outcome: .success(.int(2)))
        _ = builder.addToolCall(call)
        _ = builder.addInvocation(invocation)
        _ = builder.addToolResult(
            ToolResult.success(callId: call.id, output: .int(99), duration: .zero)
        )

        let result = builder.build()
        #expect(result.invocations.count == 1)
        #expect(result.invocations[0].result.output == .int(2))
    }

    @Test("addInvocation removes the exact pending call when two share a call ID")
    func addInvocationRemovesExactPendingAmongDuplicateIDs() {
        let builder = AgentResult.Builder()
        let callID = UUID()
        let first = ToolCall(id: callID, toolName: "first")
        let second = ToolCall(id: callID, toolName: "second")
        _ = builder.addToolCall(first)
        _ = builder.addToolCall(second)
        _ = builder.addInvocation(
            ToolInvocation(call: second, duration: .zero, outcome: .success(.int(2)))
        )
        _ = builder.addToolResult(
            ToolResult.success(callId: callID, output: .int(1), duration: .zero)
        )

        let result = builder.build()
        #expect(result.invocations.count == 2)
        #expect(result.invocations[0].call.toolName == "second")
        #expect(result.invocations[0].result.output == .int(2))
        #expect(result.invocations[1].call.toolName == "first")
        #expect(result.invocations[1].result.output == .int(1))
    }

    private var providerResolutionSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Swarm/Agents/Agent+ProviderResolution.swift")
    }
}
