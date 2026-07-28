#if SWARM_INTEGRATIONS
// DefaultAgentMemory.swift
// Swarm Framework
//
// Default agent memory stack combining ContextCore working context with
// Wax durable recall.

import Foundation

/// Default Swarm memory stack.
///
/// ContextCore remains the primary working-memory layer for multi-turn coding
/// context. Wax is used as the durable long-term layer for persisted recall.
public actor DefaultAgentMemory: Memory, MemoryPromptDescriptor, MemorySessionLifecycle, MemorySessionImportPolicy, MemorySessionReplayAware, MemoryRetrievalPolicyAware {
    public struct Configuration: Sendable {
        public static var `default`: Self {
            Configuration()
        }

        public var contextCoreConfiguration: ContextCoreMemoryConfiguration
        public var waxStoreURL: URL
        public var waxConfiguration: WaxMemory.Configuration

        public init(
            contextCoreConfiguration: ContextCoreMemoryConfiguration = .default,
            waxStoreURL: URL = WaxMemory.defaultStoreURL,
            waxConfiguration: WaxMemory.Configuration = WaxMemory.Configuration(
                promptTitle: "Wax Memory Context (secondary)",
                promptGuidance: "Use Wax memory as durable long-term context. Prefer current-session context first."
            )
        ) {
            self.contextCoreConfiguration = contextCoreConfiguration
            self.waxStoreURL = waxStoreURL
            self.waxConfiguration = waxConfiguration
        }
    }

    public nonisolated let memoryPromptTitle: String
    public nonisolated let memoryPromptGuidance: String?
    public nonisolated let memoryPriority: MemoryPriorityHint = .primary
    public nonisolated let allowsAutomaticSessionSeeding = true

    /// Composite count across the deduplicated working and durable layers.
    public var count: Int {
        get async { await compositeMessages().count }
    }

    /// Whether the deduplicated composite memory is empty.
    public var isEmpty: Bool {
        get async { await compositeMessages().isEmpty }
    }

    public init(configuration: Configuration = .default) throws {
        self.configuration = configuration
        self.contextMemory = try ContextCoreMemory(configuration: configuration.contextCoreConfiguration)
        self.memoryPromptTitle = "ContextCore + Wax Memory Context"
        self.memoryPromptGuidance = "Use the ContextCore section first for current-session context. Use the Wax section only for durable recall that does not conflict."
    }

    public func add(_ message: MemoryMessage) async {
        guard await containsMessage(id: message.id) == false else {
            return
        }

        await persist(message)
    }

    public func context(for query: String, tokenLimit: Int) async -> String {
        guard tokenLimit > 0 else {
            return ""
        }

        async let primaryContextTask = contextMemory.context(
            for: query,
            tokenLimit: max(1, Int(Double(tokenLimit) * 0.7))
        )
        let secondaryContextStr = await waxContext(for: query, tokenLimit: max(1, tokenLimit / 3))
        let primaryContextStr = await primaryContextTask

        let primary = primaryContextStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = secondaryContextStr.trimmingCharacters(in: .whitespacesAndNewlines)
        return await formatContext(primary: primary, secondary: secondary, tokenLimit: tokenLimit)
    }

    public func context(for query: MemoryQuery) async -> String {
        guard query.tokenLimit > 0 else {
            return ""
        }

        let primaryBudget = max(1, Int(Double(query.tokenLimit) * 0.7))
        let secondaryBudget = query.tokenLimit

        async let primaryContextTask = contextMemory.context(
            for: query.text,
            tokenLimit: primaryBudget
        )
        let secondaryContextStr = await waxContext(
            for: MemoryQuery(
                text: query.text,
                tokenLimit: secondaryBudget,
                maxItems: query.maxItems,
                maxItemTokens: query.maxItemTokens
            )
        )
        let primaryContextStr = await primaryContextTask

        let primaryAllowance = query.maxItems == 1 ? 1 : max(1, query.maxItems - 1)
        let primary = await limitContextItems(
            primaryContextStr,
            maxItems: primaryAllowance,
            maxItemTokens: query.maxItemTokens,
            tokenLimit: primaryBudget
        )

        let secondaryAllowance = max(0, query.maxItems - primary.count)
        let secondary = await limitContextItems(
            secondaryContextStr,
            maxItems: secondaryAllowance,
            maxItemTokens: query.maxItemTokens,
            tokenLimit: secondaryBudget
        )

        return await formatContext(
            primary: primary.text.trimmingCharacters(in: .whitespacesAndNewlines),
            secondary: secondary.text.trimmingCharacters(in: .whitespacesAndNewlines),
            tokenLimit: query.tokenLimit
        )
    }

    public func allMessages() async -> [MemoryMessage] {
        await compositeMessages()
    }

    /// Returns the primary working-set messages from ContextCore.
    public func workingMessages() async -> [MemoryMessage] {
        await contextMemory.allMessages()
    }

    /// Returns the durable Wax-backed messages, if the persistent store exists.
    public func durableMessages() async -> [MemoryMessage] {
        if let waxMemory {
            return await waxMemory.allMessages()
        }

        guard FileManager.default.fileExists(atPath: configuration.waxStoreURL.path) else {
            return []
        }

        do {
            let wax = try await ensureWaxMemory()
            return await wax.allMessages()
        } catch {
            Log.memory.warning("DefaultAgentMemory: Failed to inspect Wax messages: \(error.localizedDescription)")
            return []
        }
    }

    public func clear() async {
        await contextMemory.clear()

        if let waxMemory {
            await waxMemory.clear()
        } else {
            try? FileManager.default.removeItem(at: configuration.waxStoreURL)
        }
    }

    public func beginMemorySession() async {
        await contextMemory.beginMemorySession()
        if let waxMemory {
            await waxMemory.beginMemorySession()
        }
    }

    public func endMemorySession() async {
        await contextMemory.endMemorySession()
        if let waxMemory {
            await waxMemory.endMemorySession()
        }
    }

    public func importSessionHistory(_ messages: [MemoryMessage]) async {
        guard !messages.isEmpty else { return }
        var seenIDs = await compositeMessageIDs()
        for message in messages where seenIDs.insert(message.id).inserted {
            await persist(message)
        }
    }

    private let configuration: Configuration
    private let contextMemory: ContextCoreMemory
    private var waxMemory: WaxMemory?

    private func ensureWaxMemory() async throws -> WaxMemory {
        if let waxMemory {
            return waxMemory
        }

        let memory = try await WaxMemory(
            url: configuration.waxStoreURL,
            configuration: configuration.waxConfiguration
        )
        waxMemory = memory
        return memory
    }

    private func waxContext(for query: String, tokenLimit: Int) async -> String {
        guard tokenLimit > 0 else {
            return ""
        }

        do {
            let wax = try await ensureWaxMemory()
            return await wax.context(for: query, tokenLimit: tokenLimit)
        } catch {
            Log.memory.warning("DefaultAgentMemory: Failed to retrieve Wax context: \(error.localizedDescription)")
            return ""
        }
    }

    private func waxContext(for query: MemoryQuery) async -> String {
        guard query.tokenLimit > 0 else {
            return ""
        }

        do {
            let wax = try await ensureWaxMemory()
            return await wax.context(for: query)
        } catch {
            Log.memory.warning("DefaultAgentMemory: Failed to retrieve Wax context: \(error.localizedDescription)")
            return ""
        }
    }

    private func formatContext(primary: String, secondary: String, tokenLimit: Int) async -> String {
        let primarySection = makeSection(
            title: contextMemory.memoryPromptTitle,
            body: primary
        )
        let trimmedPrimary = await trimSection(primarySection, tokenLimit: tokenLimit)
        let primaryTokens = await tokenCount(for: trimmedPrimary)
        let separator = "\n\n"
        let separatorTokens = await tokenCount(for: separator)

        guard !secondary.isEmpty else {
            return trimmedPrimary
        }

        let remainingForSecondary = tokenLimit - primaryTokens - separatorTokens
        guard remainingForSecondary > 0 else {
            return trimmedPrimary
        }

        let secondarySection = makeSection(
            title: configuration.waxConfiguration.promptTitle,
            body: secondary
        )
        let trimmedSecondary = await trimSection(secondarySection, tokenLimit: remainingForSecondary)
        guard !trimmedSecondary.isEmpty else {
            return trimmedPrimary
        }

        let combined = [trimmedPrimary, trimmedSecondary].joined(separator: separator)
        if await tokenCount(for: combined) <= tokenLimit {
            return combined
        }

        return await trimToTokenLimit(combined, tokenLimit: tokenLimit)
    }

    private func makeSection(title: String, body: String) -> String {
        guard !body.isEmpty else { return "" }
        return """
        [\(title)]
        \(body)
        """
    }

    private func trimSection(_ text: String, tokenLimit: Int) async -> String {
        guard tokenLimit > 0 else {
            return ""
        }

        if await tokenCount(for: text) <= tokenLimit {
            return text
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else {
            return await trimToTokenLimit(text, tokenLimit: tokenLimit)
        }

        var rendered: [String] = []
        var current = ""

        for line in lines {
            let candidate = current.isEmpty ? String(line) : "\(current)\n\(line)"
            if await tokenCount(for: candidate) > tokenLimit {
                break
            }
            rendered.append(String(line))
            current = candidate
        }

        if rendered.isEmpty {
            return await trimToTokenLimit(text, tokenLimit: tokenLimit)
        }

        return rendered.joined(separator: "\n")
    }

    private func limitContextItems(
        _ context: String,
        maxItems: Int,
        maxItemTokens: Int,
        tokenLimit: Int
    ) async -> (text: String, count: Int) {
        guard maxItems > 0, tokenLimit > 0 else {
            return ("", 0)
        }

        var rendered: [String] = []
        rendered.reserveCapacity(maxItems)

        for item in contextItems(from: context) {
            guard rendered.count < maxItems else {
                break
            }

            let itemLimit = min(maxItemTokens, tokenLimit)
            let trimmedItem = await trimToTokenLimit(item, tokenLimit: itemLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedItem.isEmpty else {
                continue
            }

            let candidate = (rendered + [trimmedItem]).joined(separator: "\n\n")
            if await tokenCount(for: candidate) <= tokenLimit {
                rendered.append(trimmedItem)
            } else {
                if rendered.isEmpty {
                    let fallback = await trimToTokenLimit(trimmedItem, tokenLimit: tokenLimit)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fallback.isEmpty {
                        rendered.append(fallback)
                    }
                }
                break
            }
        }

        return (rendered.joined(separator: "\n\n"), rendered.count)
    }

    private func contextItems(from context: String) -> [String] {
        var items: [String] = []
        var current: [String] = []

        for line in context.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    current.append(line)
                }
                continue
            }

            if isContextItemHeader(trimmed), !current.isEmpty {
                items.append(current.joined(separator: "\n"))
                current = [line]
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            items.append(current.joined(separator: "\n"))
        }

        return items
    }

    private func isContextItemHeader(_ line: String) -> Bool {
        if line.hasPrefix("[user]:")
            || line.hasPrefix("[assistant]:")
            || line.hasPrefix("[system]:")
            || line.hasPrefix("[tool]:") {
            return true
        }

        return line.hasPrefix("[expanded frame:")
            || line.hasPrefix("[surrogate frame:")
            || line.hasPrefix("[snippet frame:")
    }

    private func trimToTokenLimit(_ text: String, tokenLimit: Int) async -> String {
        guard tokenLimit > 0 else {
            return ""
        }

        if await tokenCount(for: text) <= tokenLimit {
            return text
        }

        var lower = 0
        var upper = text.count
        var best = ""

        while lower <= upper {
            let mid = (lower + upper) / 2
            let candidate = prefix(text, maxCharacters: mid)
            if await tokenCount(for: candidate) <= tokenLimit {
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

    private func tokenCount(for text: String) async -> Int {
        let counter = AgentEnvironmentValues.current.promptTokenCounter
        return await PromptTokenBudgeting.countTokens(in: text, using: counter)
    }

    private func containsMessage(id: UUID) async -> Bool {
        await compositeMessageIDs().contains(id)
    }

    private func compositeMessages() async -> [MemoryMessage] {
        let working = await workingMessages()
        let durable = await durableMessages()
        return Self.uniqueMessages(working + durable)
    }

    private func compositeMessageIDs() async -> Set<UUID> {
        Set(await compositeMessages().map(\.id))
    }

    private func persist(_ message: MemoryMessage) async {
        await contextMemory.add(message)

        do {
            let wax = try await ensureWaxMemory()
            await wax.add(message)
        } catch {
            Log.memory.warning("DefaultAgentMemory: Failed to persist message to Wax: \(error.localizedDescription)")
        }
    }

    private static func uniqueMessages(_ messages: [MemoryMessage]) -> [MemoryMessage] {
        var unique: [UUID: (message: MemoryMessage, firstIndex: Int)] = [:]
        unique.reserveCapacity(messages.count)

        for (index, message) in messages.enumerated() {
            if unique[message.id] == nil {
                unique[message.id] = (message, index)
            }
        }

        return unique.values.sorted {
            if $0.message.timestamp != $1.message.timestamp {
                return $0.message.timestamp < $1.message.timestamp
            }

            return $0.firstIndex < $1.firstIndex
        }.map(\.message)
    }

    private func prefix(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<end])
    }
}
#endif
