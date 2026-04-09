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
        await memory.add(.assistant("remembered-needle: retain this exact context marker"))
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

        guard let prompt = await latestPrompt(from: provider) else {
            Issue.record("Expected Agent to generate a strict4k prompt when no tools are configured")
            return
        }

        #expect(prompt.contains("[Retrieved Context]"))
        #expect(prompt.contains("[Current Conversation]"))
        #expect(prompt.contains("needle-user-input"))
        #expect(prompt.contains("instructions-0"))
        #expect(prompt.contains("remembered-needle"))
        #expect(occurrenceCount(of: "remembered-needle", in: prompt) == 1)
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

        guard let prompt = await latestPrompt(from: provider) else {
            Issue.record("Expected Agent to generate a strict4k prompt when no tools are configured")
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

        guard let prompt = await latestPrompt(from: provider) else {
            Issue.record("Expected Agent to generate a strict4k prompt when no tools are configured")
            return
        }

        let tokenCountCalls = await provider.tokenCountCalls.count
        let tokenCount = try await provider.countTokens(in: prompt)
        #expect(tokenCount <= ContextProfile.strict4k.budget.maxInputTokens)
        #expect(prompt.contains("needle-user-input"))
        #expect(tokenCountCalls > 0)
    }

    @Test("Strict4k prompt includes compact web evidence for follow-up recall")
    func strict4kPromptIncludesCompactWebEvidence() async throws {
        let provider = MockInferenceProvider(responses: ["agent-ok"])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("strict4k-web-evidence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let memory = try DefaultAgentMemory(
            configuration: .init(
                contextCoreConfiguration: .default,
                waxStoreURL: root.appendingPathComponent("memory.mv2s"),
                webEvidenceStoreURL: root.appendingPathComponent("web-evidence", isDirectory: true)
            )
        )
        await memory.addWebSearchResult(
            rawPayload: "raw-websearch-payload",
            evidence: WebSearchEvidenceRecord(
                query: "Apple Foundation Models prompt engineering",
                mode: "search",
                summary: "Apple's prompting guide covers on-device prompting constraints.",
                semanticCore: "Prompting guidance for on-device foundation models.",
                primaryHit: .init(
                    title: "Prompting an on-device foundation model - Apple Developer",
                    url: "https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model",
                    snippet: "Prompting techniques for on-device foundation models.",
                    domain: "developer.apple.com",
                    score: 0.88
                )
            )
        )
        let session = try await makeLargeSession()

        let agent = try Agent(
            tools: [],
            instructions: longBlock("instructions", lines: 80),
            configuration: strict4kConfig(),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("What did the Apple Foundation Models prompting guide say?", session: session)

        guard let prompt = await latestPrompt(from: provider) else {
            Issue.record("Expected Agent to generate a strict4k prompt with web evidence")
            return
        }

        #expect(prompt.contains("Web Search Evidence (curated)"))
        #expect(prompt.contains("Prompting an on-device foundation model - Apple Developer"))
        #expect(prompt.contains("developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model"))
    }
}

private func occurrenceCount(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return haystack.components(separatedBy: needle).count - 1
}

private func latestPrompt(from provider: MockInferenceProvider) async -> String? {
    if let prompt = await provider.lastGenerateCall?.prompt {
        return prompt
    }
    if let messages = await provider.generateMessageCalls.last?.messages {
        return InferenceMessage.flattenPrompt(messages)
    }
    return nil
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
