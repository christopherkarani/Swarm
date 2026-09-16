import Foundation
@testable import Swarm
import Testing

@Suite("PromptEnvelope")
struct PromptEnvelopeTests {
    @Test("strict4k keeps a non-empty system when the latest user exceeds the input budget")
    func enforceKeepsSystemWhenLatestUserExceedsBudget() async {
        let maxTokens = ContextProfile.strict4k.budget.maxInputTokens
        let system = InferenceMessage.system("You are the system prompt. Keep this.")
        let hugeUser = String(repeating: "u", count: (maxTokens + 200) * 4)
        let messages = [system, .user(hugeUser)]

        let result = await PromptEnvelope.enforce(messages: messages, profile: .strict4k)

        #expect(result.first?.role == .system)
        #expect(result.contains(where: { $0.role == .system && !$0.content.isEmpty }))
        #expect(result.contains(where: { $0.role == .user }))
        #expect(result.last?.role == .user)
        let tokens = await PromptTokenBudgeting.countTokens(in: InferenceMessage.flattenPrompt(result))
        #expect(tokens <= maxTokens)
    }

    @Test("strict4k first-turn overflow does not drop the leading system")
    func enforceFirstTurnOverflowKeepsSystem() async {
        let maxTokens = ContextProfile.strict4k.budget.maxInputTokens
        let system = InferenceMessage.system(String(repeating: "S", count: 80))
        let user = InferenceMessage.user(String(repeating: "U", count: maxTokens * 4))
        let result = await PromptEnvelope.enforce(messages: [system, user], profile: .strict4k)

        #expect(result.count == 2)
        #expect(result[0].role == .system)
        #expect(!result[0].content.isEmpty)
        #expect(result[1].role == .user)
    }

    @Test("strict4k drops oldest history but keeps the leading system and last turn")
    func enforceDropsMiddleKeepsSystemAndLast() async {
        let padding = String(repeating: "x", count: 200)
        var messages: [InferenceMessage] = [.system("Stay concise.")]
        for index in 0 ..< 80 {
            messages.append(.user("old-user-\(index) \(padding)"))
            messages.append(.assistant("old-assistant-\(index) \(padding)"))
        }
        messages.append(.user("needle-latest"))

        let result = await PromptEnvelope.enforce(messages: messages, profile: .strict4k)

        #expect(result.first?.role == .system)
        #expect(result.first?.content == "Stay concise.")
        #expect(result.last?.role == .user)
        #expect(result.last?.content == "needle-latest")
        #expect(!result.contains(where: { $0.content.contains("old-user-0") }))
        let tokens = await PromptTokenBudgeting.countTokens(in: InferenceMessage.flattenPrompt(result))
        #expect(tokens <= ContextProfile.strict4k.budget.maxInputTokens)
    }

    @Test("every profile fits the assembled prompt to its input budget")
    func enforceFitsNonStrictProfiles() async {
        let profile = ContextProfile.platformDefault
        let maxTokens = profile.budget.maxInputTokens
        let system = InferenceMessage.system("You are the system prompt. Keep this.")
        let hugeUser = String(repeating: "u", count: (maxTokens + 200) * 4)
        let messages = [system, .user(hugeUser)]

        let result = await PromptEnvelope.enforce(messages: messages, profile: profile)

        #expect(result.first?.role == .system)
        #expect(result.contains(where: { $0.role == .system && !$0.content.isEmpty }))
        #expect(result.last?.role == .user)
        let tokens = await PromptTokenBudgeting.countTokens(in: InferenceMessage.flattenPrompt(result))
        #expect(tokens <= maxTokens)
    }

    @Test("over-budget tool results are stubbed before the last two")
    func enforceStubsOlderToolResults() async {
        let profile = ContextProfile.lite(maxContextTokens: 400)
        let padding = String(repeating: "p", count: 800)
        let messages: [InferenceMessage] = [
            .system("Stay."),
            .tool(name: "websearch", content: "old-search \(padding)"),
            .tool(name: "fetch_url", content: "old-page \(padding)"),
            .tool(name: "websearch", content: "recent-search \(padding)"),
            .tool(name: "fetch_url", content: "recent-page \(padding)"),
            .user("needle-latest"),
        ]

        let result = await PromptEnvelope.enforce(messages: messages, profile: profile)

        #expect(result.contains(where: { $0.content.contains("old-search") }) == false)
        #expect(result.contains(where: { $0.content.contains("old-page") }) == false)
        #expect(result.last?.content == "needle-latest")
        let tokens = await PromptTokenBudgeting.countTokens(in: InferenceMessage.flattenPrompt(result))
        #expect(tokens <= profile.budget.maxInputTokens)
    }

    @Test("compactForRetry keeps leading system and the last turn")
    func compactForRetryKeepsSystemAndLast() {
        let compacted = PromptEnvelope.compactForRetry([
            .system("Stay."),
            .tool(name: "websearch", content: "huge dump"),
            .user("needle-latest"),
        ])
        #expect(compacted.map(\.role) == [.system, .user])
        #expect(compacted.map(\.content) == ["Stay.", "needle-latest"])
    }
}
