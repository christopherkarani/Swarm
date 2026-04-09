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
public actor DefaultAgentMemory: Memory, MemoryPromptDescriptor, MemorySessionLifecycle, MemorySessionImportPolicy, MemorySessionReplayAware, MemoryRetrievalPolicyAware, WebSearchEvidenceMemory {
    public struct Configuration: Sendable {
        public static var `default`: Self {
            Configuration()
        }

        public var contextCoreConfiguration: ContextCoreMemoryConfiguration
        public var waxStoreURL: URL
        public var webEvidenceStoreURL: URL
        public var waxConfiguration: WaxMemory.Configuration

        public init(
            contextCoreConfiguration: ContextCoreMemoryConfiguration = .default,
            waxStoreURL: URL = WaxMemory.defaultStoreURL,
            webEvidenceStoreURL: URL = Configuration.defaultWebEvidenceStoreURL,
            waxConfiguration: WaxMemory.Configuration = WaxMemory.Configuration(
                promptTitle: "Wax Memory Context (secondary)",
                promptGuidance: "Use Wax memory as durable long-term context. Prefer current-session context first."
            )
        ) {
            self.contextCoreConfiguration = contextCoreConfiguration
            self.waxStoreURL = waxStoreURL
            self.webEvidenceStoreURL = webEvidenceStoreURL
            self.waxConfiguration = waxConfiguration
        }

        public static var defaultWebEvidenceStoreURL: URL {
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?
            .appendingPathComponent("Swarm", isDirectory: true)
            .appendingPathComponent("WebSearchEvidence", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("SwarmWebSearchEvidence", isDirectory: true)
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

        return await context(
            for: MemoryQuery(
                text: query,
                tokenLimit: tokenLimit,
                maxItems: 6,
                maxItemTokens: max(80, tokenLimit / 3)
            )
        )
    }

    public func context(for query: MemoryQuery) async -> String {
        guard query.tokenLimit > 0 else {
            return ""
        }

        let overfetchBudget = max(query.tokenLimit, query.tokenLimit * 2)
        async let primaryContext = contextMemory.context(for: query.text, tokenLimit: overfetchBudget)
        async let secondaryContext = waxContext(for: query.text, tokenLimit: overfetchBudget)
        async let evidenceContext = webEvidenceContext(for: query)

        let boundedPrimary = await boundContextItems(
            in: (await primaryContext).trimmingCharacters(in: .whitespacesAndNewlines),
            maxItems: max(1, query.maxItems),
            maxItemTokens: query.maxItemTokens
        )
        let boundedSecondary = await boundContextItems(
            in: (await secondaryContext).trimmingCharacters(in: .whitespacesAndNewlines),
            maxItems: max(1, query.maxItems),
            maxItemTokens: query.maxItemTokens
        )
        let boundedEvidence = await boundContextItems(
            in: (await evidenceContext).trimmingCharacters(in: .whitespacesAndNewlines),
            maxItems: max(1, query.maxItems),
            maxItemTokens: query.maxItemTokens
        )

        return await formatContext(
            query: query.text,
            sources: [
                ContextSourceSlice(
                    title: contextMemory.memoryPromptTitle,
                    body: boundedPrimary,
                    kind: .working
                ),
                ContextSourceSlice(
                    title: "Web Search Evidence (curated)",
                    body: boundedEvidence,
                    kind: .evidence
                ),
                ContextSourceSlice(
                    title: configuration.waxConfiguration.promptTitle,
                    body: boundedSecondary,
                    kind: .durable
                ),
            ],
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
        if let webEvidenceStore {
            try? await webEvidenceStore.clear()
        } else {
            try? FileManager.default.removeItem(at: configuration.webEvidenceStoreURL)
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
    private var webEvidenceStore: WebSearchEvidenceStore?

    private enum ContextSourceKind {
        case working
        case evidence
        case durable
    }

    private struct ContextSourceSlice {
        let title: String
        let body: String
        let kind: ContextSourceKind
    }

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

    public func addWebSearchResult(rawPayload: String, evidence: WebSearchEvidenceRecord) async {
        do {
            let store = try await ensureWebEvidenceStore()
            try await store.save(
                rawPayload: rawPayload,
                record: evidence,
                searchableText: WebSearchEvidenceCompiler.searchableText(for: evidence)
            )
        } catch {
            Log.memory.warning("DefaultAgentMemory: Failed to persist websearch evidence: \(error.localizedDescription)")
        }
    }

    private func ensureWebEvidenceStore() async throws -> WebSearchEvidenceStore {
        if let webEvidenceStore {
            return webEvidenceStore
        }

        let store = try await WebSearchEvidenceStore(rootURL: configuration.webEvidenceStoreURL)
        webEvidenceStore = store
        return store
    }

    private func webEvidenceContext(for query: MemoryQuery) async -> String {
        guard query.tokenLimit > 0 else {
            return ""
        }

        do {
            let store = try await ensureWebEvidenceStore()
            let records = try await store.search(
                query: query.text,
                topK: max(1, min(query.maxItems, 6))
            )
            guard !records.isEmpty else {
                return ""
            }

            let rendered = records.prefix(query.maxItems).map { record in
                WebSearchEvidenceCompiler.compactTranscript(for: record)
            }
            return rendered.joined(separator: "\n\n")
        } catch {
            Log.memory.warning("DefaultAgentMemory: Failed to retrieve web evidence context: \(error.localizedDescription)")
            return ""
        }
    }

    private func formatContext(
        query: String,
        sources: [ContextSourceSlice],
        tokenLimit: Int
    ) async -> String {
        let nonEmptySources = sources.filter { !$0.body.isEmpty }
        guard !nonEmptySources.isEmpty else {
            return ""
        }

        let orderedSources = nonEmptySources.sorted { lhs, rhs in
            sourcePriority(for: lhs, query: query) > sourcePriority(for: rhs, query: query)
        }

        let allocations = await allocateBudgets(for: orderedSources, query: query, tokenLimit: tokenLimit)
        let separator = "\n\n"
        let separatorTokens = await tokenCount(for: separator)

        var renderedSections: [String] = []
        var previousBody = ""
        var remaining = tokenLimit

        for source in orderedSources {
            let allocated = allocations[source.title, default: 0]
            guard allocated > 0, remaining > 0 else {
                continue
            }

            let deduplicatedBody = removeOverlap(primary: previousBody, secondary: source.body)
            guard !deduplicatedBody.isEmpty else {
                continue
            }

            let section = makeSection(title: source.title, body: deduplicatedBody)
            let trimmed = await trimSection(section, tokenLimit: min(allocated, remaining))
            guard !trimmed.isEmpty else {
                continue
            }

            let tokens = await tokenCount(for: trimmed)
            let cost = renderedSections.isEmpty ? tokens : tokens + separatorTokens
            guard cost <= remaining else {
                continue
            }

            renderedSections.append(trimmed)
            previousBody = previousBody.isEmpty ? deduplicatedBody : previousBody + "\n" + deduplicatedBody
            remaining -= cost
        }

        let combined = renderedSections.joined(separator: separator)
        guard await tokenCount(for: combined) > tokenLimit else {
            return combined
        }
        return await trimToTokenLimit(combined, tokenLimit: tokenLimit)
    }

    private func sourcePriority(for source: ContextSourceSlice, query: String) -> Double {
        let lexical = lexicalScore(for: source.body, query: query)
        let base: Double = switch source.kind {
        case .working:
            1.0
        case .evidence:
            0.95
        case .durable:
            0.65
        }
        let urlBoost = source.body.contains("http") ? 0.15 : 0
        return base + lexical + urlBoost
    }

    private func allocateBudgets(
        for sources: [ContextSourceSlice],
        query: String,
        tokenLimit: Int
    ) async -> [String: Int] {
        guard !sources.isEmpty else {
            return [:]
        }

        let separatorTokens = await tokenCount(for: "\n\n")
        let usableBudget = max(1, tokenLimit - (separatorTokens * max(0, sources.count - 1)))
        let weighted = sources.map { source in
            (
                source.title,
                max(0.1, sourcePriority(for: source, query: query))
            )
        }
        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        let minimumFloor = min(120, max(40, usableBudget / max(1, sources.count * 2)))
        var allocations: [String: Int] = [:]
        var remaining = usableBudget

        for (index, entry) in weighted.enumerated() {
            let isLast = index == weighted.count - 1
            let proportional = Int((entry.1 / totalWeight) * Double(usableBudget))
            let floor = min(minimumFloor, remaining)
            let allocation = isLast ? remaining : max(floor, proportional)
            allocations[entry.0] = allocation
            remaining = max(0, remaining - allocation)
        }

        return allocations
    }

    private func lexicalScore(for text: String, query: String) -> Double {
        let haystack = text.lowercased()
        let tokens = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !tokens.isEmpty else {
            return 0
        }

        let hits = tokens.reduce(into: 0) { partial, token in
            if haystack.contains(token) {
                partial += 1
            }
        }
        return Double(hits) / Double(tokens.count)
    }

    private func makeSection(title: String, body: String) -> String {
        guard !body.isEmpty else { return "" }
        return """
        [\(title)]
        \(body)
        """
    }

    private func removeOverlap(primary: String, secondary: String) -> String {
        guard !primary.isEmpty, !secondary.isEmpty else {
            return secondary
        }

        let primaryLineKeys = Set(
            primary
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { normalizeOverlapLine(String($0)) }
                .filter { !$0.isEmpty }
        )

        guard !primaryLineKeys.isEmpty else {
            return secondary
        }

        let filteredLines = secondary
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let normalized = normalizeOverlapLine(String(line))
                return normalized.isEmpty || !primaryLineKeys.contains(normalized)
            }

        return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeOverlapLine(_ line: String) -> String {
        var normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.hasPrefix("["),
           let closingBracket = normalized.firstIndex(of: "]") {
            let afterBracket = normalized.index(after: closingBracket)
            normalized = normalized[afterBracket...].trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.hasPrefix(":") {
                normalized.removeFirst()
                normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return normalized
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

    private func boundContextItems(
        in text: String,
        maxItems: Int,
        maxItemTokens: Int
    ) async -> String {
        guard !text.isEmpty, maxItems > 0, maxItemTokens > 0 else {
            return ""
        }

        let blocks = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !blocks.isEmpty else {
            return ""
        }

        var kept: [String] = []
        kept.reserveCapacity(min(maxItems, blocks.count))

        for block in blocks.prefix(maxItems) {
            let trimmed = await trimToTokenLimit(block, tokenLimit: maxItemTokens)
            guard !trimmed.isEmpty else {
                continue
            }
            kept.append(trimmed)
        }

        return kept.joined(separator: "\n\n")
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
