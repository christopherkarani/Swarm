import Foundation

/// Enforces context-envelope limits for provider prompts.
enum PromptEnvelope {
    /// Drops oldest non-system messages until the conversation fits the profile budget.
    /// Roles stay. The latest message is always kept. A leading `.system` message is
    /// never dropped; if system + last still overflow, last (and if needed system
    /// text) is truncated so a non-empty system remains.
    static func enforce(messages: [InferenceMessage], profile: ContextProfile) async -> [InferenceMessage] {
        guard profile.preset == .strict4k, !messages.isEmpty else {
            return messages
        }

        let maxTokens = profile.budget.maxInputTokens
        if await tokenCount(of: messages) <= maxTokens {
            return messages
        }

        let lastIndex = messages.count - 1
        let last = messages[lastIndex]
        let hasProtectedSystem = messages[0].role == .system
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
            if await tokenCount(of: next) <= maxTokens {
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
        if await tokenCount(of: windowed) <= maxTokens {
            return windowed
        }

        return await fitProtectedSystemAndLast(
            protectedSystem,
            last: last,
            lastIsProtectedSystem: lastIsProtectedSystem,
            maxTokens: maxTokens
        )
    }

    private static func tokenCount(of messages: [InferenceMessage]) async -> Int {
        await PromptTokenBudgeting.countTokens(in: InferenceMessage.flattenPrompt(messages))
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
        maxTokens: Int
    ) async -> [InferenceMessage] {
        if lastIsProtectedSystem, let system = protectedSystem {
            return [await truncatedMessage(system, prefixedBy: [], maxTokens: maxTokens, keepNonEmpty: true)]
        }

        if let system = protectedSystem {
            let clippedLast = await truncatedMessage(
                last,
                prefixedBy: [system],
                maxTokens: maxTokens,
                keepNonEmpty: false
            )
            let withFullSystem = [system, clippedLast]
            if await tokenCount(of: withFullSystem) <= maxTokens {
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
                keepNonEmpty: true
            )
            let fittedLast = await truncatedMessage(
                last,
                prefixedBy: [clippedSystem],
                maxTokens: maxTokens,
                keepNonEmpty: false
            )
            return [clippedSystem, fittedLast]
        }

        return [await truncatedMessage(last, prefixedBy: [], maxTokens: maxTokens, keepNonEmpty: false)]
    }

    private static func truncatedMessage(
        _ message: InferenceMessage,
        prefixedBy prefix: [InferenceMessage],
        maxTokens: Int,
        keepNonEmpty: Bool
    ) async -> InferenceMessage {
        let minimum = keepNonEmpty && !message.content.isEmpty
            ? String(message.content.prefix(1))
            : ""
        var lower = minimum.count
        var upper = message.content.count
        var best = minimum

        while lower <= upper {
            let mid = (lower + upper) / 2
            let candidate = String(message.content.prefix(mid))
            let next = prefix + [replacingContent(of: message, with: candidate)]
            if await tokenCount(of: next) <= maxTokens {
                best = candidate
                lower = mid + 1
            } else {
                upper = mid - 1
            }
        }

        return replacingContent(of: message, with: best)
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
