import Foundation
import Testing
@testable import Swarm

@Suite("TokenUsage breakdowns")
struct TokenUsageTests {
    @Test("Breakdowns default to nil so existing call sites keep their meaning")
    func breakdownsDefaultToNil() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 4)
        #expect(usage.cachedInputTokens == nil)
        #expect(usage.reasoningTokens == nil)
        #expect(usage.totalTokens == 14)
    }

    @Test("Breakdowns are subsets and do not change totalTokens")
    func breakdownsDoNotChangeTotal() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 40, cachedInputTokens: 80, reasoningTokens: 30)
        #expect(usage.totalTokens == 140)
    }

    @Test("Merging sums reported breakdowns and keeps unreported ones nil")
    func mergingBreakdowns() {
        let reported = TokenUsage(inputTokens: 10, outputTokens: 5, cachedInputTokens: 6, reasoningTokens: 2)
        let unreported = TokenUsage(inputTokens: 3, outputTokens: 1)

        let mixed = reported.merging(unreported)
        #expect(mixed == TokenUsage(inputTokens: 13, outputTokens: 6, cachedInputTokens: 6, reasoningTokens: 2))

        let bothReported = reported.merging(reported)
        #expect(bothReported.cachedInputTokens == 12)
        #expect(bothReported.reasoningTokens == 4)

        let neither = unreported.merging(unreported)
        #expect(neither.cachedInputTokens == nil)
        #expect(neither.reasoningTokens == nil)
    }

    @Test("Description lists breakdowns only when reported")
    func descriptionListsBreakdowns() {
        #expect(
            TokenUsage(inputTokens: 1, outputTokens: 2).description
                == "TokenUsage(input: 1, output: 2, total: 3)"
        )
        #expect(
            TokenUsage(inputTokens: 10, outputTokens: 5, cachedInputTokens: 8, reasoningTokens: 3).description
                == "TokenUsage(input: 10, cached: 8, output: 5, reasoning: 3, total: 15)"
        )
    }

    @Test("Codable omits unreported breakdowns and decodes payloads written before they existed")
    func codableIsBackwardCompatible() throws {
        let legacy = Data(#"{"inputTokens":7,"outputTokens":3}"#.utf8)
        let decoded = try JSONDecoder().decode(TokenUsage.self, from: legacy)
        #expect(decoded == TokenUsage(inputTokens: 7, outputTokens: 3))

        let encoded = try JSONEncoder().encode(TokenUsage(inputTokens: 7, outputTokens: 3))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["cachedInputTokens"] == nil)
        #expect(object["reasoningTokens"] == nil)

        let full = TokenUsage(inputTokens: 7, outputTokens: 3, cachedInputTokens: 5, reasoningTokens: 1)
        let roundTripped = try JSONDecoder().decode(TokenUsage.self, from: JSONEncoder().encode(full))
        #expect(roundTripped == full)
    }
}
