import Foundation
@testable import Swarm
import Testing

@Suite("Agent Conversation History Fidelity")
struct AgentConversationHistoryTests {
    @Test("Multi-turn session delivers exact role-tagged history to the provider")
    func multiTurnSessionDeliversExactMessageArray() async throws {
        let provider = MockInferenceProvider(responses: ["first reply", "second reply"])
        let session = InMemorySession()
        let agent = try Agent(
            tools: [],
            instructions: "Stay concise.",
            inferenceProvider: provider
        )

        _ = try await agent.run("Hello", session: session)
        _ = try await agent.run("Follow up", session: session)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 2)
        #expect(await provider.generateCalls.isEmpty)

        let turn1 = calls[0].messages
        #expect(turn1.map(\.role) == [.system, .user])
        #expect(turn1[0].content.contains("Stay concise."))
        #expect(turn1[1] == .user("Hello"))

        let turn2 = calls[1].messages
        #expect(turn2.map(\.role) == [.system, .user, .assistant, .user])
        #expect(turn2[0].content.contains("Stay concise."))
        #expect(turn2[1] == .user("Hello"))
        #expect(turn2[2] == .assistant("first reply"))
        #expect(turn2[3] == .user("Follow up"))
    }

    @Test("strict4k windowing still delivers role-tagged messages")
    func strict4kDeliversRoleTaggedMessages() async throws {
        let provider = MockInferenceProvider(responses: ["ok"])
        let session = InMemorySession()
        try await session.addItems([
            .user("Hello"),
            .assistant("Hi there"),
        ])
        let agent = try Agent(
            tools: [],
            instructions: "Stay concise.",
            configuration: AgentConfiguration(contextMode: .strict4k, defaultTracingEnabled: false),
            inferenceProvider: provider
        )

        _ = try await agent.run("Follow up", session: session)

        let calls = await provider.generateMessageCalls
        #expect(calls.count == 1)
        #expect(await provider.generateCalls.isEmpty)
        guard let delivered = calls.first?.messages else {
            return
        }

        let roles = delivered.map(\.role)
        #expect(roles.contains(.system))
        #expect(roles.contains(.user))
        #expect(roles.contains(.assistant))
        #expect(delivered.contains(where: { $0.role == .user && $0.content == "Follow up" }))
        #expect(delivered.contains(where: { $0.role == .assistant && $0.content == "Hi there" }))
    }

    @Test("strict4k drops oldest messages but keeps roles and the latest user turn")
    func strict4kWindowsMessagesWithoutFlattening() async throws {
        let provider = MockInferenceProvider(responses: ["ok"])
        let session = InMemorySession()
        let padding = String(repeating: "x", count: 200)
        for index in 0 ..< 80 {
            try await session.addItems([
                .user("old-user-\(index) \(padding)"),
                .assistant("old-assistant-\(index) \(padding)"),
            ])
        }
        let agent = try Agent(
            tools: [],
            instructions: "Stay concise.",
            configuration: AgentConfiguration(contextMode: .strict4k, defaultTracingEnabled: false),
            memory: MockAgentMemory(context: ""),
            inferenceProvider: provider
        )

        _ = try await agent.run("needle-latest", session: session)

        let calls = await provider.generateMessageCalls
        #expect(await provider.generateCalls.isEmpty)
        guard let delivered = calls.first?.messages else {
            Issue.record("Expected a messages generate call")
            return
        }

        #expect(delivered.contains(where: { $0.role == .system }))
        #expect(delivered.contains(where: { $0.role == .user && $0.content == "needle-latest" }))
        #expect(!delivered.contains(where: { $0.content.contains("old-user-0") }))
        let flattened = InferenceMessage.flattenPrompt(delivered)
        let tokenCount = try await provider.countTokens(in: flattened)
        #expect(tokenCount <= ContextProfile.strict4k.budget.maxInputTokens)
    }

    @Test("Tool-loop history keeps assistant tool calls and tool results in order")
    func toolLoopPreservesAssistantAndToolResultMessages() async throws {
        let echo = MockTool(name: "echo", result: .string("pong"))
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: "checking echo",
                toolCalls: [
                    .init(id: "call_echo", name: "echo", arguments: ["text": .string("ping")])
                ],
                finishReason: .toolCall
            ),
            InferenceResponse(content: "done", finishReason: .completed),
        ])

        let agent = try Agent(
            tools: [echo],
            instructions: "Use echo when asked.",
            configuration: .default.maxIterations(3),
            inferenceProvider: provider
        )

        let result = try await agent.run("ping the echo tool")
        #expect(result.output == "done")

        let calls = await provider.toolCallMessageCalls
        #expect(calls.count == 2)
        #expect(await provider.toolCallCalls.isEmpty)

        let first = calls[0].messages
        #expect(first.map(\.role) == [.system, .user])
        #expect(first[1] == .user("ping the echo tool"))

        let followup = calls[1].messages
        #expect(followup.map(\.role) == [.system, .user, .assistant, .tool])
        #expect(followup[1] == .user("ping the echo tool"))
        #expect(followup[2].role == .assistant)
        #expect(followup[2].content == "checking echo")
        #expect(followup[2].toolCalls.count == 1)
        #expect(followup[2].toolCalls[0].id == "call_echo")
        #expect(followup[2].toolCalls[0].name == "echo")
        #expect(followup[3] == .tool(name: "echo", content: "pong", toolCallID: "call_echo"))
    }
}
