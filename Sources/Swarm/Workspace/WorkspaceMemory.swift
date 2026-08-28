import Foundation

/// Workspace-backed memory for skill snippets and durable markdown notes.
public actor WorkspaceMemory: Memory, MemoryPromptDescriptor, MemorySessionLifecycle, MemoryRetrievalPolicyAware, MemorySessionImportPolicy {
    @available(*, deprecated, message: "Return memoryPromptMetadata instead.")
    public nonisolated let memoryPromptTitle = "Retrieved Workspace Context"

    @available(*, deprecated, message: "Return memoryPromptMetadata instead.")
    public nonisolated let memoryPromptGuidance: String? = "Use workspace context as helpful secondary context. App instructions and agent specs win on conflicts."

    @available(*, deprecated, message: "Return memoryPromptMetadata instead.")
    public nonisolated let memoryPriority: MemoryPriorityHint = .secondary

    public nonisolated var memoryPromptMetadata: MemoryPromptMetadata? {
        MemoryPromptMetadata(
            title: "Retrieved Workspace Context",
            guidance: "Use workspace context as helpful secondary context. App instructions and agent specs win on conflicts.",
            priority: .secondary
        )
    }
    public nonisolated let allowsAutomaticSessionSeeding = false

    public var count: Int {
        get async {
            let notesCount = (try? workspace.loadMemoryNotes())?.count ?? 0
            return activatedSkills.count + notesCount
        }
    }

    public var isEmpty: Bool {
        get async {
            let notesCount = (try? workspace.loadMemoryNotes())?.count ?? 0
            return activatedSkills.isEmpty && notesCount == 0
        }
    }

    private let workspace: AgentWorkspace
    private let activatedSkills: [WorkspaceSkill]
    private let tokenEstimator: any TokenEstimator

    init(
        workspace: AgentWorkspace,
        activatedSkills: [WorkspaceSkill],
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) {
        self.workspace = workspace
        self.activatedSkills = activatedSkills
        self.tokenEstimator = tokenEstimator
    }

    public func add(_ message: MemoryMessage) async {
        // Workspace memory is durable context, not transcript storage.
        _ = message
    }

    public func context(for query: String, tokenLimit: Int) async -> String {
        await context(
            for: MemoryQuery(
                text: query,
                tokenLimit: tokenLimit,
                maxItems: 3,
                maxItemTokens: max(1, tokenLimit)
            )
        )
    }

    public func context(for query: MemoryQuery) async -> String {
        let notes = (try? workspace.loadMemoryNotes()) ?? []
        let candidates = skillCandidates() + noteCandidates(from: notes)
        guard !candidates.isEmpty else {
            return ""
        }

        let terms = tokenize(query.text)
        let ranked = candidates
            .map { candidate in
                (candidate: candidate, score: lexicalScore(of: candidate.searchText, matching: terms))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.candidate.title < rhs.candidate.title
                }
                return lhs.score > rhs.score
            }

        var rendered: [String] = []
        var usedTokens = 0
        var addedItems = 0

        for entry in ranked {
            if addedItems >= query.maxItems {
                break
            }
            if !terms.isEmpty, entry.score == 0 {
                continue
            }

            let itemText = format(candidate: entry.candidate, maxTokens: query.maxItemTokens)
            guard !itemText.isEmpty else {
                continue
            }

            let itemTokens = tokenEstimator.estimateTokens(for: itemText)
            if usedTokens + itemTokens > query.tokenLimit {
                break
            }

            rendered.append(itemText)
            usedTokens += itemTokens
            addedItems += 1
        }

        if rendered.isEmpty, terms.isEmpty, let first = candidates.first {
            return format(candidate: first, maxTokens: min(query.tokenLimit, query.maxItemTokens))
        }

        return rendered.joined(separator: "\n\n")
    }

    public func allMessages() async -> [MemoryMessage] {
        []
    }

    public func clear() async {}

    public func beginMemorySession() async {}

    public func endMemorySession() async {}
}

private extension WorkspaceMemory {
    struct Candidate: Sendable {
        let title: String
        let searchText: String
        let text: String
        let label: String
    }

    func skillCandidates() -> [Candidate] {
        activatedSkills.map { skill in
            Candidate(
                title: skill.name,
                searchText: "\(skill.name) \(skill.description) \(skill.body)".lowercased(),
                text: skill.body,
                label: "Skill"
            )
        }
    }

    func noteCandidates(from notes: [WorkspaceMemoryNote]) -> [Candidate] {
        notes.map { note in
            Candidate(
                title: note.title,
                searchText: "\(note.title) \(note.tags.joined(separator: " ")) \(note.body)".lowercased(),
                text: note.body,
                label: "Memory"
            )
        }
    }

    func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    func lexicalScore(of text: String, matching terms: [String]) -> Int {
        guard !terms.isEmpty else {
            return 1
        }

        return terms.reduce(into: 0) { partialResult, term in
            guard text.contains(term) else { return }
            partialResult += max(1, text.components(separatedBy: term).count - 1)
        }
    }

    func format(candidate: Candidate, maxTokens: Int) -> String {
        let header = "[\(candidate.label): \(candidate.title)]"
        let bodyBudget = max(1, maxTokens - tokenEstimator.estimateTokens(for: header))
        let snippet = truncate(candidate.text, tokenLimit: bodyBudget)
        guard !snippet.isEmpty else {
            return ""
        }
        return "\(header)\n\(snippet)"
    }

    func truncate(_ text: String, tokenLimit: Int) -> String {
        guard tokenLimit > 0 else { return "" }
        if tokenEstimator.estimateTokens(for: text) <= tokenLimit {
            return text
        }

        let words = text.split(whereSeparator: \.isWhitespace)
        var collected: [Substring] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if tokenEstimator.estimateTokens(for: candidate) > tokenLimit {
                break
            }
            collected.append(word)
            current = candidate
        }

        if collected.isEmpty {
            return String(text.prefix(max(1, tokenLimit * 4)))
        }

        let result = collected.map(String.init).joined(separator: " ")
        return result == text ? result : "\(result)..."
    }
}
