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

    @Test("non-strict4k profiles leave messages unchanged")
    func enforceIgnoresNonStrictProfiles() async {
        let messages = [
            InferenceMessage.system("system"),
            .user(String(repeating: "u", count: 20_000)),
        ]
        let result = await PromptEnvelope.enforce(messages: messages, profile: .balanced)
        #expect(result == messages)
    }
}
