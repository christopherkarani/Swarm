import Foundation

/// Enforces context-envelope limits for provider prompts.
enum PromptEnvelope {
    private static let truncationMarker = "\n\n[... context truncated for strict4k budget ...]\n\n"

    static func enforce(prompt: String, profile: ContextProfile) async -> String {
        guard profile.preset == .strict4k else {
            return prompt
        }

        let counter = PromptTokenBudgeting.counter()
        let maxTokens = profile.budget.maxInputTokens

        if await PromptTokenBudgeting.countTokens(in: prompt, using: counter) <= maxTokens {
            return prompt
        }

        let marker = truncationMarker
        let markerTokens = await PromptTokenBudgeting.countTokens(in: marker, using: counter)

        if maxTokens <= markerTokens + 16 {
            return await PromptTokenBudgeting.prefix(marker, maxTokens: maxTokens, using: counter)
        }

        // Preserve the beginning (instructions/system context) and the end
        // (latest user/tool context), trimming middle context first.
        let tailTokens = max(16, maxTokens / 3)
        let headTokens = max(16, maxTokens - markerTokens - tailTokens)

        let head = await PromptTokenBudgeting.prefix(prompt, maxTokens: headTokens, using: counter)
        let tail = await PromptTokenBudgeting.suffix(prompt, maxTokens: tailTokens, using: counter)

        var combined = head + marker + tail
        let combinedTokens = await PromptTokenBudgeting.countTokens(in: combined, using: counter)
        if combinedTokens <= maxTokens {
            return combined
        }

        let overflow = combinedTokens - maxTokens
        let adjustedTail = max(0, tailTokens - overflow)
        let adjustedSuffix = await PromptTokenBudgeting.suffix(
            prompt,
            maxTokens: adjustedTail,
            using: counter
        )
        combined = head + marker + adjustedSuffix

        if await PromptTokenBudgeting.countTokens(in: combined, using: counter) <= maxTokens {
            return combined
        }

        let adjustedHead = max(0, maxTokens - markerTokens)
        let fallback = await PromptTokenBudgeting.prefix(prompt, maxTokens: adjustedHead, using: counter) + marker
        if await PromptTokenBudgeting.countTokens(in: fallback, using: counter) <= maxTokens {
            return fallback
        }

        return await PromptTokenBudgeting.prefix(marker, maxTokens: maxTokens, using: counter)
    }

    /// Drops oldest non-system messages until the conversation fits the profile budget.
    /// Roles stay. The latest message is always kept.
    static func enforce(messages: [InferenceMessage], profile: ContextProfile) async -> [InferenceMessage] {
        guard profile.preset == .strict4k, !messages.isEmpty else {
            return messages
        }

        let maxTokens = profile.budget.maxInputTokens
        if await tokenCount(of: messages) <= maxTokens {
            return messages
        }

        let systemCount = messages.prefix(while: { $0.role == .system }).count
        let lastIndex = messages.count - 1
        guard lastIndex > systemCount else {
            var result = messages
            while result.count > 1, await tokenCount(of: result) > maxTokens {
                result.removeFirst()
            }
            return result
        }
        var middle = Array(messages[systemCount ..< lastIndex])
        var keptMiddle: [InferenceMessage] = []

        while let candidate = middle.popLast() {
            let next = Array(messages.prefix(systemCount)) + [candidate] + keptMiddle + [messages[lastIndex]]
            if await tokenCount(of: next) <= maxTokens {
                keptMiddle.insert(candidate, at: 0)
            } else {
                break
            }
        }

        var result = Array(messages.prefix(systemCount)) + keptMiddle + [messages[lastIndex]]
        if result.count > 1, await tokenCount(of: result) > maxTokens, result[0].role == .system {
            result = await truncatedSystemPreservingLast(result, maxTokens: maxTokens)
        }
        while result.count > 1, await tokenCount(of: result) > maxTokens {
            result.removeFirst()
        }
        return result
    }

    private static func tokenCount(of messages: [InferenceMessage]) async -> Int {
        await PromptTokenBudgeting.countTokens(in: InferenceMessage.flattenPrompt(messages))
    }

    private static func truncatedSystemPreservingLast(
        _ messages: [InferenceMessage],
        maxTokens: Int
    ) async -> [InferenceMessage] {
        guard let last = messages.last, messages[0].role == .system else {
            return messages
        }
        let lastTokens = await tokenCount(of: [last])
        // Flattening adds role labels; leave slack so the system role survives.
        let budgetForSystem = max(0, maxTokens - lastTokens - 64)
        let system = messages[0]
        let clipped = await PromptTokenBudgeting.prefix(system.content, maxTokens: budgetForSystem)
        var head = system
        head = InferenceMessage(
            role: .system,
            content: clipped,
            name: system.name,
            toolCallID: system.toolCallID,
            toolCalls: system.toolCalls
        )
        return [head, last]
    }
}
