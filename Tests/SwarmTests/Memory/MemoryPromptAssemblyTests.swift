// MemoryPromptAssemblyTests.swift
// SwarmTests
//
// Item budgets for default memory prompts. A chunk stays one item even when
// its text contains role or frame header lines.

import Foundation
@testable import Swarm
import Testing

private func countCharacters(_ text: String) async -> Int {
    text.count
}

struct MemoryPromptAssemblyTests {
    @Test("An embedded role header stays inside the single capped item")
    func embeddedRoleHeaderStaysInsideCappedItem() async {
        let items = [
            MemoryPromptItem(text: "[user]: alpha\n[assistant]: inside"),
            MemoryPromptItem(text: "[assistant]: beta"),
        ]

        let kept = await MemoryPromptAssembly.limit(
            items,
            maxItems: 1,
            maxItemTokens: 500,
            tokenLimit: 500,
            estimate: countCharacters
        )

        #expect(kept == [MemoryPromptItem(text: "[user]: alpha\n[assistant]: inside")])
    }

    @Test("maxItems keeps the first of three short items")
    func maxItemsKeepsTheFirstShortItem() async {
        let items = [
            MemoryPromptItem(text: "one"),
            MemoryPromptItem(text: "two"),
            MemoryPromptItem(text: "three"),
        ]

        let kept = await MemoryPromptAssembly.limit(
            items,
            maxItems: 1,
            maxItemTokens: 100,
            tokenLimit: 100,
            estimate: countCharacters
        )

        #expect(kept.count == 1)
        #expect(kept == [MemoryPromptItem(text: "one")])
    }

    @Test("A per-item token cap drops the character suffix past maxItemTokens")
    func perItemTokenCapDropsCutSuffix() async throws {
        let kept = await MemoryPromptAssembly.limit(
            [MemoryPromptItem(text: "KEEP-this-prefix SUFFIX-cut-away")],
            maxItems: 1,
            maxItemTokens: 16,
            tokenLimit: 500,
            estimate: countCharacters
        )

        let keptText = try #require(kept.first).text
        #expect(kept.count == 1)
        #expect(keptText == "KEEP-this-prefix")
        #expect(keptText.contains("SUFFIX-cut-away") == false)
    }

    @Test("The newline join counts against the running token budget")
    func newlineJoinCountsAgainstTokenBudget() async {
        let kept = await MemoryPromptAssembly.limit(
            [
                MemoryPromptItem(text: "aaaa"),
                MemoryPromptItem(text: "bbbb"),
            ],
            maxItems: 2,
            maxItemTokens: 100,
            tokenLimit: 9,
            estimate: countCharacters
        )

        #expect(kept == [MemoryPromptItem(text: "aaaa")])
    }

    @Test("Non-positive budgets and empty input keep nothing")
    func nonPositiveBudgetsKeepNothing() async {
        let item = [MemoryPromptItem(text: "kept")]

        let noItems = await MemoryPromptAssembly.limit(
            [],
            maxItems: 3,
            maxItemTokens: 10,
            tokenLimit: 10,
            estimate: countCharacters
        )
        let noItemCap = await MemoryPromptAssembly.limit(
            item,
            maxItems: 0,
            maxItemTokens: 10,
            tokenLimit: 10,
            estimate: countCharacters
        )
        let noTokenBudget = await MemoryPromptAssembly.limit(
            item,
            maxItems: 1,
            maxItemTokens: 10,
            tokenLimit: 0,
            estimate: countCharacters
        )

        #expect(noItems.isEmpty)
        #expect(noItemCap.isEmpty)
        #expect(noTokenBudget.isEmpty)
    }

    @Test("A whitespace-only trim is skipped so the next item can be kept")
    func whitespaceOnlyTrimIsSkipped() async {
        let kept = await MemoryPromptAssembly.limit(
            [
                MemoryPromptItem(text: "   "),
                MemoryPromptItem(text: "kept"),
            ],
            maxItems: 2,
            maxItemTokens: 10,
            tokenLimit: 10,
            estimate: countCharacters
        )

        #expect(kept == [MemoryPromptItem(text: "kept")])
    }

    @Test("Window-build fallback items are newest-first so the prefix keeps recent messages")
    func windowBuildFallbackItemsAreNewestFirst() async {
        let messages = [
            MemoryMessage.user("older"),
            MemoryMessage.assistant("middle"),
            MemoryMessage.system("newer"),
        ]

        let items = MemoryPromptAssembly.fallbackItems(from: messages)

        #expect(items.map(\.text) == [
            "[system]: newer",
            "[assistant]: middle",
            "[user]: older",
        ])

        let kept = await MemoryPromptAssembly.limit(
            items,
            maxItems: 1,
            maxItemTokens: 100,
            tokenLimit: 100,
            estimate: countCharacters
        )

        #expect(kept == [MemoryPromptItem(text: "[system]: newer")])
    }

    @Test("An embedded frame header stays inside the single capped item")
    func embeddedFrameHeaderStaysInsideCappedItem() async {
        let items = [
            MemoryPromptItem(text: "[user]: alpha\n[expanded frame: inside"),
            MemoryPromptItem(text: "[assistant]: beta"),
        ]

        let kept = await MemoryPromptAssembly.limit(
            items,
            maxItems: 1,
            maxItemTokens: 500,
            tokenLimit: 500,
            estimate: countCharacters
        )

        #expect(kept == [MemoryPromptItem(text: "[user]: alpha\n[expanded frame: inside")])
    }

    @Test("An exact-fit candidate fills the token budget")
    func exactFitCandidateFillsBudget() async {
        let kept = await MemoryPromptAssembly.limit(
            [
                MemoryPromptItem(text: "aaaa"),
                MemoryPromptItem(text: "bb"),
            ],
            maxItems: 2,
            maxItemTokens: 100,
            tokenLimit: 8,
            estimate: countCharacters
        )

        // "aaaa" (4) + "\n\n" (2) + "bb" (2) == tokenLimit.
        #expect(kept.map(\.text) == ["aaaa", "bb"])
    }

    @Test("A zero per-item token cap keeps nothing")
    func zeroPerItemTokenCapKeepsNothing() async {
        let kept = await MemoryPromptAssembly.limit(
            [MemoryPromptItem(text: "kept")],
            maxItems: 1,
            maxItemTokens: 0,
            tokenLimit: 100,
            estimate: countCharacters
        )

        #expect(kept.isEmpty)
    }

    @Test("Limited fallback items select newest but render chronological")
    func limitedFallbackItemsRenderChronological() async {
        let messages = [
            MemoryMessage.user("older"),
            MemoryMessage.assistant("middle"),
            MemoryMessage.system("newer"),
        ]

        let kept = await MemoryPromptAssembly.limitedFallbackItems(
            from: messages,
            maxItems: 2,
            maxItemTokens: 100,
            tokenLimit: 100,
            estimate: countCharacters
        )

        // Newest two win selection; render stays oldest-first like formatContext.
        #expect(kept.map(\.text) == ["[assistant]: middle", "[system]: newer"])
    }
}
