import Foundation

/// A memory implementation that fans writes out to multiple memory layers and
/// combines retrieved context from each layer.
actor CompositeMemory: Memory {
    nonisolated let memoryPromptTitle: String
    nonisolated let memoryPromptGuidance: String?
    nonisolated let memoryPriority: MemoryPriorityHint
    nonisolated let allowsAutomaticSessionSeeding: Bool
    nonisolated let trackedSessionMemory: (any Memory)?

    private let memories: [any Memory]
    private let tokenEstimator: any TokenEstimator

    init(
        _ memories: [any Memory],
        memoryPromptTitle: String = "Layered Memory Context",
        memoryPromptGuidance: String? = "Use earlier memory sections first when context conflicts. Workspace context supplements, but does not replace, working and durable memory.",
        memoryPriority: MemoryPriorityHint = .primary,
        trackedSessionMemory: (any Memory)? = nil,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) {
        self.memories = memories
        self.memoryPromptTitle = memoryPromptTitle
        self.memoryPromptGuidance = memoryPromptGuidance
        self.memoryPriority = memoryPriority
        self.tokenEstimator = tokenEstimator
        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        self.trackedSessionMemory = trackedSessionMemory ?? memories.first { $0 is DefaultAgentMemory }
        #else
        self.trackedSessionMemory = trackedSessionMemory
        #endif
        self.allowsAutomaticSessionSeeding = memories.contains(where: Self.allowsSessionSeeding)
    }

    var count: Int {
        get async {
            var total = 0
            for memory in memories {
                total += await memory.count
            }
            return total
        }
    }

    var isEmpty: Bool {
        get async {
            for memory in memories where await !memory.isEmpty {
                return false
            }
            return true
        }
    }

    func add(_ message: MemoryMessage) async {
        for memory in memories {
            await memory.add(message)
        }
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        await context(for: MemoryQuery(
            text: query,
            tokenLimit: tokenLimit,
            maxItems: max(1, memories.count * 2),
            maxItemTokens: max(1, tokenLimit)
        ))
    }

    func context(for query: MemoryQuery) async -> String {
        guard query.tokenLimit > 0, !memories.isEmpty else {
            return ""
        }

        var layerContexts: [String] = []
        for memory in memories {
            let rawContext = await context(from: memory, query: query, tokenLimit: query.tokenLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawContext.isEmpty else {
                continue
            }
            layerContexts.append(rawContext)
        }

        return combine(layerContexts, tokenLimit: query.tokenLimit)
    }

    func allMessages() async -> [MemoryMessage] {
        var messages: [MemoryMessage] = []
        for memory in memories {
            messages += await memory.allMessages()
        }
        return messages
    }

    func clear() async {
        for memory in memories {
            await memory.clear()
        }
    }

    func beginMemorySession() async {
        for memory in memories {
            await memory.beginMemorySession()
        }
    }

    func endMemorySession() async {
        for memory in memories {
            await memory.endMemorySession()
        }
    }

    private func combine(_ layerContexts: [String], tokenLimit: Int) -> String {
        guard !layerContexts.isEmpty else {
            return ""
        }

        var sections: [String] = []
        var usedTokens = 0
        let separator = "\n\n"
        let separatorTokens = tokenEstimator.estimateTokens(for: separator)

        for (index, rawContext) in layerContexts.enumerated() {
            let separatorBudget = sections.isEmpty ? 0 : separatorTokens
            let availableTokens = tokenLimit - usedTokens - separatorBudget
            guard availableTokens > 0 else {
                break
            }

            let remainingLayers = max(1, layerContexts.count - index)
            let layerLimit = max(1, availableTokens / remainingLayers)
            let sectionTokens = tokenEstimator.estimateTokens(for: rawContext)
            let section = sectionTokens <= layerLimit
                ? rawContext
                : truncate(rawContext, tokenLimit: layerLimit)
            guard !section.isEmpty else {
                continue
            }

            let additionalTokens = tokenEstimator.estimateTokens(for: section) + separatorBudget
            if usedTokens + additionalTokens <= tokenLimit {
                sections.append(section)
                usedTokens += additionalTokens
                continue
            }

            guard sections.isEmpty else {
                break
            }

            let truncated = truncate(rawContext, tokenLimit: availableTokens)
            if !truncated.isEmpty {
                sections.append(truncated)
            }
            break
        }

        return sections.joined(separator: separator)
    }

    func shouldImportSessionHistory() async -> Bool {
        for memory in memories where Self.allowsSessionSeeding(memory) {
            if await memory.isEmpty {
                return true
            }
        }
        return false
    }

    func importSessionHistory(_ messages: [MemoryMessage]) async {
        guard !messages.isEmpty else {
            return
        }

        for memory in memories where Self.allowsSessionSeeding(memory) {
            guard await memory.isEmpty else {
                continue
            }
            if await memory.shouldImportSessionHistory() {
                await memory.importSessionHistory(messages)
            }
        }
    }

    private func context(
        from memory: any Memory,
        query: MemoryQuery,
        tokenLimit: Int
    ) async -> String {
        return await memory.context(for: MemoryQuery(
            text: query.text,
            tokenLimit: tokenLimit,
            maxItems: query.maxItems,
            maxItemTokens: min(query.maxItemTokens, tokenLimit)
        ))
    }

    private func truncate(_ text: String, tokenLimit: Int) -> String {
        guard tokenLimit > 0 else {
            return ""
        }
        guard tokenEstimator.estimateTokens(for: text) > tokenLimit else {
            return text
        }

        var result = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            let candidate = result.isEmpty ? String(word) : "\(result) \(word)"
            if tokenEstimator.estimateTokens(for: candidate) > tokenLimit {
                break
            }
            result = candidate
        }

        if result.isEmpty {
            return String(text.prefix(max(1, tokenLimit * 4)))
        }
        return "\(result)..."
    }

    private static func allowsSessionSeeding(_ memory: any Memory) -> Bool {
        memory.allowsAutomaticSessionSeeding
    }
}
