import Foundation

/// Package-internal context-window decisions shared by ``PromptEnvelope`` and
/// ``SlidingWindowMemory``.
///
/// Callers inject a token counter so the same fit/truncate policy can run
/// against a provider counter, ``EstimatedPromptTokenCounter``, or a test fake.
/// Roles stay; this is windowing, not flattening to a single user string.
enum ContextWindow {
    struct Policy: Equatable, Sendable {
        var maxTokens: Int
        var protectLeadingSystem: Bool
        var alwaysKeepLast: Bool

        static func strict4k(_ profile: ContextProfile) -> Policy {
            Policy(
                maxTokens: profile.budget.maxInputTokens,
                protectLeadingSystem: true,
                alwaysKeepLast: true
            )
        }
    }

    /// Drops oldest unprotected messages until the conversation fits `policy.maxTokens`.
    /// The latest message is kept when `alwaysKeepLast` is true. A leading `.system`
    /// message is kept when `protectLeadingSystem` is true; if system + last still
    /// overflow, last (and if needed system text) is truncated so a non-empty system
    /// remains.
    static func fit(
        messages: [InferenceMessage],
        policy: Policy,
        countTokens: @Sendable (String) async -> Int
    ) async -> [InferenceMessage] {
        guard !messages.isEmpty else {
            return messages
        }

        let maxTokens = policy.maxTokens
        if await tokenCount(of: messages, countTokens: countTokens) <= maxTokens {
            return messages
        }

        if !policy.alwaysKeepLast {
            return await dropOldest(
                messages,
                maxTokens: maxTokens,
                protectLeadingSystem: policy.protectLeadingSystem,
                countTokens: countTokens
            )
        }

        let lastIndex = messages.count - 1
        let last = messages[lastIndex]
        let hasProtectedSystem = policy.protectLeadingSystem && messages[0].role == .system
        let protectedSystem = hasProtectedSystem ? messages[0] : nil
        let lastIsProtectedSystem = lastIndex == 0 && hasProtectedSystem

        var droppable = Array(messages.dropLast())
        if hasProtectedSystem, !droppable.isEmpty {
            droppable.removeFirst()
        }

        var kept: [InferenceMessage] = []
        while let candidate = droppable.popLast() {
            let next = assemble(
                protectedSystem: protectedSystem,
                older: [candidate] + kept,
                last: last,
                lastIsProtectedSystem: lastIsProtectedSystem
            )
            if await tokenCount(of: next, countTokens: countTokens) <= maxTokens {
                kept.insert(candidate, at: 0)
            } else {
                break
            }
        }

        let windowed = assemble(
            protectedSystem: protectedSystem,
            older: kept,
            last: last,
            lastIsProtectedSystem: lastIsProtectedSystem
        )
        if await tokenCount(of: windowed, countTokens: countTokens) <= maxTokens {
            return windowed
        }

        return await fitProtectedSystemAndLast(
            protectedSystem,
            last: last,
            lastIsProtectedSystem: lastIsProtectedSystem,
            maxTokens: maxTokens,
            countTokens: countTokens
        )
    }

    /// Longest character prefix of `text` whose token count is within `maxTokens`.
    ///
    /// If even `minimum` overflows, `minimum` is returned so callers can keep a
    /// non-empty protected system head.
    static func longestPrefix(
        of text: String,
        maxTokens: Int,
        minimum: String = "",
        countTokens: @Sendable (String) async -> Int
    ) async -> String {
        guard maxTokens > 0 else {
            return minimum
        }

        if await countTokens(text) <= maxTokens {
            return text
        }

        var lower = minimum.count
        var upper = text.count
        var best = minimum

        while lower <= upper {
            let mid = (lower + upper) / 2
            let candidate = String(text.prefix(mid))
            if await countTokens(candidate) <= maxTokens {
                best = candidate
                lower = mid + 1
            } else {
                upper = mid - 1
            }
        }

        return best
    }

    /// Keep-newest eviction: drop oldest messages until the additive token sum
    /// fits, always leaving at least one message.
    static func evictOldest<Message: Sendable>(
        from messages: [Message],
        maxTokens: Int,
        tokensOf: @Sendable (Message) async -> Int
    ) async -> [Message] {
        guard !messages.isEmpty else {
            return messages
        }

        var remaining = messages
        var total = 0
        for message in remaining {
            total += await tokensOf(message)
        }

        while total > maxTokens, remaining.count > 1 {
            let removed = remaining.removeFirst()
            total -= await tokensOf(removed)
        }

        return remaining
    }

    private static func dropOldest(
        _ messages: [InferenceMessage],
        maxTokens: Int,
        protectLeadingSystem: Bool,
        countTokens: @Sendable (String) async -> Int
    ) async -> [InferenceMessage] {
        var remaining = messages
        let protectedCount = (protectLeadingSystem && remaining.first?.role == .system) ? 1 : 0
        while remaining.count > protectedCount,
            await tokenCount(of: remaining, countTokens: countTokens) > maxTokens
        {
            remaining.remove(at: protectedCount)
        }
        return remaining
    }

    private static func tokenCount(
        of messages: [InferenceMessage],
        countTokens: @Sendable (String) async -> Int
    ) async -> Int {
        await countTokens(InferenceMessage.flattenPrompt(messages))
    }

    private static func assemble(
        protectedSystem: InferenceMessage?,
        older: [InferenceMessage],
        last: InferenceMessage,
        lastIsProtectedSystem: Bool
    ) -> [InferenceMessage] {
        if lastIsProtectedSystem {
            return protectedSystem.map { [$0] } ?? [last]
        }
        if let protectedSystem {
            return [protectedSystem] + older + [last]
        }
        return older + [last]
    }

    /// Fits a protected leading system and the latest turn under `maxTokens`.
    /// Prefers a full system + truncated last (head-preserving). Only clips
    /// system text when the system message itself cannot share the budget.
    private static func fitProtectedSystemAndLast(
        _ protectedSystem: InferenceMessage?,
        last: InferenceMessage,
        lastIsProtectedSystem: Bool,
        maxTokens: Int,
        countTokens: @Sendable (String) async -> Int
    ) async -> [InferenceMessage] {
        if lastIsProtectedSystem, let system = protectedSystem {
            return [await truncatedMessage(
                system,
                prefixedBy: [],
                maxTokens: maxTokens,
                keepNonEmpty: true,
                countTokens: countTokens
            )]
        }

        if let system = protectedSystem {
            let clippedLast = await truncatedMessage(
                last,
                prefixedBy: [system],
                maxTokens: maxTokens,
                keepNonEmpty: false,
                countTokens: countTokens
            )
            let withFullSystem = [system, clippedLast]
            if await tokenCount(of: withFullSystem, countTokens: countTokens) <= maxTokens {
                return withFullSystem
            }

            // System itself overflows even with an empty last. Keep a non-empty
            // system head and a last-turn tail, matching the flattened-prompt contract.
            let tailShare = max(16, maxTokens / 3)
            let headShare = max(16, maxTokens - tailShare)
            let clippedSystem = await truncatedMessage(
                system,
                prefixedBy: [],
                maxTokens: headShare,
                keepNonEmpty: true,
                countTokens: countTokens
            )
            let fittedLast = await truncatedMessage(
                last,
                prefixedBy: [clippedSystem],
                maxTokens: maxTokens,
                keepNonEmpty: false,
                countTokens: countTokens
            )
            return [clippedSystem, fittedLast]
        }

        return [await truncatedMessage(
            last,
            prefixedBy: [],
            maxTokens: maxTokens,
            keepNonEmpty: false,
            countTokens: countTokens
        )]
    }

    private static func truncatedMessage(
        _ message: InferenceMessage,
        prefixedBy prefix: [InferenceMessage],
        maxTokens: Int,
        keepNonEmpty: Bool,
        countTokens: @Sendable (String) async -> Int
    ) async -> InferenceMessage {
        let minimum = keepNonEmpty && !message.content.isEmpty
            ? String(message.content.prefix(1))
            : ""
        let clipped = await longestPrefix(
            of: message.content,
            maxTokens: maxTokens,
            minimum: minimum,
            countTokens: { candidate in
                let next = prefix + [replacingContent(of: message, with: candidate)]
                return await countTokens(InferenceMessage.flattenPrompt(next))
            }
        )
        return replacingContent(of: message, with: clipped)
    }

    private static func replacingContent(of message: InferenceMessage, with content: String) -> InferenceMessage {
        InferenceMessage(
            role: message.role,
            content: content,
            name: message.name,
            toolCallID: message.toolCallID,
            toolCalls: message.toolCalls
        )
    }
}

/// Enforces context-envelope limits for provider prompts.
enum PromptEnvelope {
    /// Drops oldest non-system messages until the conversation fits the profile budget.
    /// Roles stay. The latest message is always kept. A leading `.system` message is
    /// never dropped; if system + last still overflow, last (and if needed system
    /// text) is truncated so a non-empty system remains.
    ///
    /// Non-``.strict4k`` presets are a no-op. The shared ``ContextWindow`` core is
    /// still callable with an explicit budget independent of this gate.
    static func enforce(messages: [InferenceMessage], profile: ContextProfile) async -> [InferenceMessage] {
        guard profile.preset == .strict4k, !messages.isEmpty else {
            return messages
        }

        return await ContextWindow.fit(
            messages: messages,
            policy: .strict4k(profile),
            countTokens: { await PromptTokenBudgeting.countTokens(in: $0) }
        )
    }
}
