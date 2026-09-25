// MemoryPromptAssembly.swift
// Swarm Framework
//
// Item budgets for default memory prompts. Callers pass one item per chunk
// or frame. This type does not scan role or frame header lines.

import Foundation

struct MemoryPromptItem: Equatable, Sendable {
    var text: String
}

enum MemoryPromptAssembly {
    static func limit(
        _ items: [MemoryPromptItem],
        maxItems: Int,
        maxItemTokens: Int,
        tokenLimit: Int,
        estimate: @Sendable (String) async -> Int
    ) async -> [MemoryPromptItem] {
        guard maxItems > 0, tokenLimit > 0 else {
            return []
        }

        var kept: [MemoryPromptItem] = []
        kept.reserveCapacity(maxItems)

        for item in items {
            guard kept.count < maxItems else {
                break
            }

            let itemLimit = min(maxItemTokens, tokenLimit)
            let trimmedItem = await trim(item.text, tokenLimit: itemLimit, estimate: estimate)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedItem.isEmpty else {
                continue
            }

            let candidate = (kept.map(\.text) + [trimmedItem]).joined(separator: "\n\n")
            if await estimate(candidate) <= tokenLimit {
                kept.append(MemoryPromptItem(text: trimmedItem))
            } else {
                if kept.isEmpty {
                    let fallback = await trim(trimmedItem, tokenLimit: tokenLimit, estimate: estimate)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fallback.isEmpty {
                        kept.append(MemoryPromptItem(text: fallback))
                    }
                }
                break
            }
        }

        return kept
    }

    /// Window-build failure items in selection order, newest first.
    ///
    /// `limit` keeps a prefix, so newest-first input selects recent messages
    /// (like `MemoryMessage.formatContext`). Render order is chronological;
    /// use ``limitedFallbackItems(from:maxItems:maxItemTokens:tokenLimit:estimate:)``
    /// to select and then reverse for rendering.
    static func fallbackItems(from messages: [MemoryMessage]) -> [MemoryPromptItem] {
        messages.reversed().map { message in
            MemoryPromptItem(text: message.formattedContent)
        }
    }

    /// Window-build failure items, selected newest-first and rendered chronological.
    ///
    /// Matches `MemoryMessage.formatContext`: recent messages win selection,
    /// kept items render oldest-first.
    static func limitedFallbackItems(
        from messages: [MemoryMessage],
        maxItems: Int,
        maxItemTokens: Int,
        tokenLimit: Int,
        estimate: @Sendable (String) async -> Int
    ) async -> [MemoryPromptItem] {
        let kept = await limit(
            fallbackItems(from: messages),
            maxItems: maxItems,
            maxItemTokens: maxItemTokens,
            tokenLimit: tokenLimit,
            estimate: estimate
        )
        return Array(kept.reversed())
    }

    private static func trim(
        _ text: String,
        tokenLimit: Int,
        estimate: @Sendable (String) async -> Int
    ) async -> String {
        guard tokenLimit > 0 else {
            return ""
        }

        if await estimate(text) <= tokenLimit {
            return text
        }

        var lower = 0
        var upper = text.count
        var best = ""

        while lower <= upper {
            let mid = (lower + upper) / 2
            let candidate = prefix(text, maxCharacters: mid)
            if await estimate(candidate) <= tokenLimit {
                best = candidate
                lower = mid + 1
            } else {
                upper = mid - 1
            }
        }

        if !best.isEmpty {
            return best
        }

        return prefix(text, maxCharacters: max(1, min(text.count, tokenLimit)))
    }

    private static func prefix(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<end])
    }
}
