#if SWARM_INTEGRATIONS && canImport(ContextCore)
import Foundation
@testable import Swarm
import Testing

@Suite("Strict4k Prompt Envelope")
struct Strict4kPromptEnvelopeTests {
    @Test("DefaultAgentMemory strict4k prompt retains retrieved context and current request")
    func defaultMemoryPromptKeepsLiveConversation() async throws {
        let provider = MockInferenceProvider(responses: ["agent-ok"])
        let waxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wax")
        let memory = try DefaultAgentMemory(
            configuration: .init(
                contextCoreConfiguration: .default,
                waxStoreURL: waxURL
            )
        )
        await memory.add(.assistant(longBlock("remembered", lines: 20)))
        let session = try await makeLargeSession()

        let agent = try Agent(
            tools: [],
            instructions: longBlock("instructions", lines: 220),
            configuration: strict4kConfig(),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("needle-user-input", session: session)

        guard let prompt = await provider.lastGenerateCall?.prompt else {
            Issue.record("Expected Agent to call generate() when no tools are configured")
            return
        }

        #expect(prompt.contains("[Retrieved Context]"))
        #expect(prompt.contains("[Current Conversation]"))
        #expect(prompt.contains("needle-user-input"))
        #expect(prompt.contains("instructions-0"))
        #expect(prompt.contains("remembered-0"))
    }

    @Test("Agent caps prompt to strict4k max input budget")
    func agentCapsPrompt() async throws {
        let provider = MockInferenceProvider(responses: ["agent-ok"])
        let memory = MockAgentMemory(context: longBlock("memory", lines: 420))
        let session = try await makeLargeSession()

        let agent = try Agent(
            tools: [],
            instructions: longBlock("instructions", lines: 220),
            configuration: strict4kConfig(),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("needle-user-input", session: session)

        guard let prompt = await provider.lastGenerateCall?.prompt else {
            Issue.record("Expected Agent to call generate() when no tools are configured")
            return
        }

        let tokenCountCalls = await provider.tokenCountCalls.count
        let tokenCount = try await provider.countTokens(in: prompt)
        #expect(tokenCount <= ContextProfile.strict4k.budget.maxInputTokens)
        #expect(prompt.contains("needle-user-input"))
        #expect(tokenCountCalls > 0)
    }

    @Test("Agent caps prompt to strict4k max input budget")
    func reactAgentCapsPrompt() async throws {
        let provider = MockInferenceProvider(responses: ["Final Answer: react-ok"])
        let memory = MockAgentMemory(context: longBlock("memory", lines: 420))
        let session = try await makeLargeSession()

        let agent = try Agent(
            tools: [],
            instructions: longBlock("instructions", lines: 220),
            configuration: strict4kConfig(),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("needle-user-input", session: session)

        guard let prompt = await provider.lastGenerateCall?.prompt else {
            Issue.record("Expected Agent to call generate() when no tools are configured")
            return
        }

        let tokenCountCalls = await provider.tokenCountCalls.count
        let tokenCount = try await provider.countTokens(in: prompt)
        #expect(tokenCount <= ContextProfile.strict4k.budget.maxInputTokens)
        #expect(prompt.contains("needle-user-input"))
        #expect(tokenCountCalls > 0)
    }
}

private func strict4kConfig() -> AgentConfiguration {
    AgentConfiguration(
        name: "strict4k-test",
        contextMode: .strict4k,
        defaultTracingEnabled: false
    )
}

private func longBlock(_ label: String, lines: Int) -> String {
    (0 ..< lines)
        .map { index in
            "\(label)-\(index): this is intentionally verbose content to stress prompt budget enforcement."
        }
        .joined(separator: "\n")
}

private func makeLargeSession() async throws -> InMemorySession {
    let session = InMemorySession()
    for index in 0 ..< 120 {
        try await session.addItems([
            .user("history-user-\(index): \(longBlock("u", lines: 1))"),
            .assistant("history-assistant-\(index): \(longBlock("a", lines: 1))"),
        ])
    }
    return session
}
#endif
