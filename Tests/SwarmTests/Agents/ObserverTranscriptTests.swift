// ObserverTranscriptTests.swift
// SwarmTests
//
// Observers receive the role-tagged transcript the provider sees — not a
// flattened single-user-string shadow.

import Foundation
@testable import Swarm
import Testing

private actor TranscriptRecordingObserver: AgentObserver {
    private(set) var llmStarts: [(systemPrompt: String?, inputMessages: [InferenceMessage])] = []

    func onLLMStart(
        context _: AgentContext?,
        agent _: any AgentRuntime,
        systemPrompt: String?,
        inputMessages: [InferenceMessage]
    ) async {
        llmStarts.append((systemPrompt, inputMessages))
    }
}

@Suite("Observer LLM transcript")
struct ObserverTranscriptTests {
    @Test("onLLMStart receives the role-tagged messages the provider receives")
    func observerReceivesRoleTaggedMessages() async throws {
        let provider = MockInferenceProvider(responses: ["agent-ok"])
        let observer = TranscriptRecordingObserver()
        let agent = try Agent(
            tools: [],
            instructions: "You are a math tutor.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        _ = try await agent.run("What is 2+2?", observer: observer)

        #expect(await provider.generateCalls.isEmpty)
        let providerMessages = await provider.generateMessageCalls.last?.messages
        let observed = await observer.llmStarts.last

        guard let providerMessages, let observed else {
            Issue.record("Expected one onLLMStart carrying the turn transcript")
            return
        }

        // The observer payload is exactly the provider's input transcript.
        #expect(observed.inputMessages == providerMessages)
        #expect(observed.inputMessages.contains(where: { $0.role == .system && $0.content.contains("math tutor") }))
        #expect(observed.inputMessages.contains(where: { $0.role == .user && $0.content.contains("What is 2+2?") }))

        // Not a flattened single synthetic user string.
        let singleFlattenedUser = observed.inputMessages.count == 1
            && observed.inputMessages[0].role == .user
            && observed.inputMessages[0].content.contains("[System]:")
        #expect(!singleFlattenedUser)
    }

    @Test("Tool-loop iterations also deliver the real transcript to observers")
    func toolLoopObserverReceivesRoleTaggedMessages() async throws {
        let tool = MockTool(name: "echo", result: .string("echoed"))
        let provider = MockInferenceProvider(responses: ["done"])
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [InferenceResponse.ParsedToolCall(id: "t1", name: "echo", arguments: [:])]
            )
        ])
        let observer = TranscriptRecordingObserver()
        let agent = try Agent(
            tools: [tool],
            instructions: "Use the echo tool.",
            configuration: AgentConfiguration.default
                .enableStreaming(false)
                .timeout(.seconds(15))
                .defaultTracingEnabled(false),
            inferenceProvider: provider
        )

        _ = try await agent.run("call echo", observer: observer)

        let starts = await observer.llmStarts
        #expect(starts.count >= 2)
        for start in starts {
            #expect(start.inputMessages.contains(where: { $0.role == .user && $0.content.contains("call echo") }))
            let singleFlattenedUser = start.inputMessages.count == 1
                && start.inputMessages[0].role == .user
                && start.inputMessages[0].content.contains("[System]:")
            #expect(!singleFlattenedUser)
        }
    }
}
