import Foundation
@testable import Swarm
import Testing

@Suite("PromptEnvelope ContextWindow")
struct PromptEnvelopeContextWindowTests {
    @Test("fit drops oldest history and keeps a protected system plus the last turn")
    func fitKeepsProtectedSystemAndLast() async throws {
        let system = InferenceMessage.system("Stay")
        let oldest = InferenceMessage.user("old-user")
        let last = InferenceMessage.user("needle-latest")
        let messages = [system, oldest, last]
        let budget = flattenCharacterCount([system, last])
        try #require(flattenCharacterCount(messages) > budget)

        let fitted = await ContextWindow.fit(
            messages: messages,
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: true,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted == [system, last])
        #expect(flattenCharacterCount(fitted) <= budget)
    }

    @Test("fit honors an explicit budget without a strict4k profile")
    func fitUsesExplicitBudgetIndependentOfPreset() async {
        let messages = [
            InferenceMessage.system("sys"),
            .user("old"),
            .user("new"),
        ]
        let budget = flattenCharacterCount([.system("sys"), .user("new")])

        let fitted = await ContextWindow.fit(
            messages: messages,
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: true,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted.map(\.content) == ["sys", "new"])
        #expect(fitted.map(\.role) == [.system, .user])
    }

    @Test("fit can drop a leading system when protection is off")
    func fitDropsUnprotectedLeadingSystem() async throws {
        let system = InferenceMessage.system("SYSTEM-LONG")
        let last = InferenceMessage.user("x")
        let budget = flattenCharacterCount([last])
        try #require(flattenCharacterCount([system, last]) > budget)

        let fitted = await ContextWindow.fit(
            messages: [system, last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: false,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted == [last])
    }

    @Test("fit with alwaysKeepLast false drops oldest history first")
    func fitWithoutKeepingLastDropsOldest() async throws {
        let oldest = InferenceMessage.user("old-user")
        let newest = InferenceMessage.user("new-user")
        let budget = flattenCharacterCount([newest])
        try #require(flattenCharacterCount([oldest, newest]) > budget)

        let fitted = await ContextWindow.fit(
            messages: [oldest, newest],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: false,
                alwaysKeepLast: false
            ),
            countTokens: characterCount
        )

        #expect(fitted == [newest])
        #expect(flattenCharacterCount(fitted) <= budget)
    }

    @Test("fit with alwaysKeepLast false retains an oversized sole message")
    func fitWithoutKeepingLastRetainsAtLeastOneMessage() async throws {
        let last = InferenceMessage.user(String(repeating: "u", count: 40))
        let budget = 4
        try #require(flattenCharacterCount([last]) > budget)

        let fitted = await ContextWindow.fit(
            messages: [last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: false,
                alwaysKeepLast: false
            ),
            countTokens: characterCount
        )

        #expect(fitted == [last])
        #expect(flattenCharacterCount(fitted) > budget)
    }

    @Test("fit with alwaysKeepLast false keeps a protected system and may drop the last turn")
    func fitWithoutKeepingLastProtectsLeadingSystem() async throws {
        let system = InferenceMessage.system("Stay")
        let last = InferenceMessage.user("needle-latest")
        let budget = flattenCharacterCount([system])
        try #require(flattenCharacterCount([system, last]) > budget)

        let fitted = await ContextWindow.fit(
            messages: [system, last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: true,
                alwaysKeepLast: false
            ),
            countTokens: characterCount
        )

        #expect(fitted == [system])
        #expect(flattenCharacterCount(fitted) <= budget)
    }

    @Test("fit truncates an oversized last turn instead of dropping it")
    func fitTruncatesLastTurnToBudget() async {
        let last = InferenceMessage.user(String(repeating: "u", count: 40))
        let budget = 20

        let fitted = await ContextWindow.fit(
            messages: [last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: false,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted.count == 1)
        #expect(fitted[0].role == .user)
        #expect(fitted[0].content.isEmpty == false)
        #expect(flattenCharacterCount(fitted) <= budget)
        #expect(fitted[0].content.count < last.content.count)
    }

    @Test("fit keeps a non-empty protected system when last overflows")
    func fitTruncatesLastBeforeClippingProtectedSystem() async throws {
        let system = InferenceMessage.system("You are the system.")
        let last = InferenceMessage.user(String(repeating: "u", count: 80))
        let budget = flattenCharacterCount([system, .user("")]) + 8
        try #require(flattenCharacterCount([system, last]) > budget)

        let fitted = await ContextWindow.fit(
            messages: [system, last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: true,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted.count == 2)
        #expect(fitted[0].role == .system)
        #expect(fitted[0].content == system.content)
        #expect(fitted[1].role == .user)
        #expect(fitted[1].content.isEmpty == false)
        #expect(flattenCharacterCount(fitted) <= budget)
    }

    @Test("longestPrefix uses the injected counter")
    func longestPrefixHonorsFakeCounter() async {
        let clipped = await ContextWindow.longestPrefix(
            of: "abcdefghij",
            maxTokens: 4,
            countTokens: characterCount
        )

        #expect(clipped == "abcd")
    }

    @Test("evictOldest keeps newest messages under an additive budget")
    func evictOldestKeepsNewest() async {
        let kept = await ContextWindow.evictOldest(
            from: [10, 20, 30, 40],
            maxTokens: 70,
            tokensOf: { $0 }
        )

        #expect(kept == [30, 40])
    }

    @Test("evictOldest keeps a single oversized message")
    func evictOldestKeepsSingleOversized() async {
        let kept = await ContextWindow.evictOldest(
            from: [50],
            maxTokens: 10,
            tokensOf: { $0 }
        )

        #expect(kept == [50])
    }

    @Test("synchronous evictOldest matches the async keep-newest result")
    func synchronousEvictOldestMatchesAsync() async {
        let messages = [10, 20, 30, 40]
        let asyncKept = await ContextWindow.evictOldest(
            from: messages,
            maxTokens: 70,
            tokensOf: { $0 }
        )
        let syncKept = ContextWindow.evictOldest(
            from: messages,
            maxTokens: 70,
            tokensOf: { $0 }
        )

        #expect(syncKept == asyncKept)
        #expect(syncKept == [30, 40])
    }

    @Test("strict4k enforce matches ContextWindow.fit with the same counter")
    func enforceMatchesSharedFit() async {
        let padding = String(repeating: "x", count: 80)
        var messages: [InferenceMessage] = [.system("Stay concise.")]
        for index in 0 ..< 12 {
            messages.append(.user("old-user-\(index) \(padding)"))
            messages.append(.assistant("old-assistant-\(index) \(padding)"))
        }
        messages.append(.user("needle-latest"))

        let viaEnvelope = await PromptEnvelope.enforce(messages: messages, profile: .strict4k)
        let viaFit = await ContextWindow.fit(
            messages: messages,
            policy: .strict4k(.strict4k),
            countTokens: { await PromptTokenBudgeting.countTokens(in: $0) }
        )

        #expect(viaEnvelope == viaFit)
    }
}

private func characterCount(_ text: String) async -> Int {
    do {
        return try await CharacterCountTokenCounter().countTokens(in: text)
    } catch {
        Issue.record("CharacterCountTokenCounter is not expected to throw")
        return text.count
    }
}

private func flattenCharacterCount(_ messages: [InferenceMessage]) -> Int {
    InferenceMessage.flattenPrompt(messages).count
}

/// Deterministic fake ``PromptTokenCounter``: one token per character.
/// Used to exercise ``ContextWindow`` without constructing Agent or Memory.
private struct CharacterCountTokenCounter: PromptTokenCounter {
    func countTokens(in text: String) async throws -> Int {
        text.count
    }
}
