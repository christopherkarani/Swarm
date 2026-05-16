import Foundation
import Wax
import WaxVectorSearch

/// Wax-backed memory implementation using the public Memory API.
public actor WaxMemory: Memory, MemoryPromptDescriptor, MemorySessionLifecycle {
    // MARK: Public

    /// Configuration for Wax memory behavior.
    public struct Configuration: Sendable {
        public static let `default` = Configuration()

        public var enableVectorSearch: Bool
        public var tokenEstimator: any TokenEstimator
        public var promptTitle: String
        public var promptGuidance: String?

        public init(
            enableVectorSearch: Bool = false,
            tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared,
            promptTitle: String = "Wax Memory Context (primary)",
            promptGuidance: String? = "Use Wax memory context as the primary source of truth. Prefer it before calling tools."
        ) {
            self.enableVectorSearch = enableVectorSearch
            self.tokenEstimator = tokenEstimator
            self.promptTitle = promptTitle
            self.promptGuidance = promptGuidance
        }
    }

    public var count: Int { persistedMessages.count }
    public var isEmpty: Bool { persistedMessages.isEmpty }

    public nonisolated let memoryPromptTitle: String
    public nonisolated let memoryPromptGuidance: String?
    public nonisolated let memoryPriority: MemoryPriorityHint = .primary

    /// Creates a Wax-backed memory store.
    /// - Parameters:
    ///   - url: Location of the Wax database.
    ///   - embedder: Optional embedding provider for vector search.
    ///   - configuration: Wax memory configuration.
    public init(
        url: URL,
        embedder: (any WaxVectorSearch.EmbeddingProvider)? = nil,
        configuration: Configuration = .default
    ) async throws {
        self.url = url
        self.embedder = embedder
        self.configuration = configuration
        let loadedMessages: [MemoryMessage]
        do {
            let frameStore = try await Self.makeFrameStore(at: url)
            loadedMessages = await Self.loadPersistedMessages(from: frameStore)
            await frameStore.close()
        }

        var waxConfig = Wax.Memory.Config.default
        waxConfig.enableVectorSearch = embedder != nil && configuration.enableVectorSearch

        if let embedder {
            self.store = try await Wax.Memory(at: url, config: waxConfig, embedding: embedder)
        } else {
            self.store = try await Wax.Memory(at: url, config: waxConfig)
        }

        self.persistedMessages = loadedMessages
        self.persistedMessageIDs = Set(loadedMessages.map(\.id))
        self.memoryPromptTitle = configuration.promptTitle
        self.memoryPromptGuidance = configuration.promptGuidance
    }

    public func add(_ message: MemoryMessage) async {
        guard persistedMessageIDs.contains(message.id) == false else {
            return
        }
        let addGeneration = generation

        var metadata = message.metadata
        metadata["role"] = message.role.rawValue
        metadata["timestamp"] = isoFormatter.string(from: message.timestamp)
        metadata["message_id"] = message.id.uuidString

        do {
            try await store.save(message.content, metadata: metadata)
            try await store.flush()
            guard generation == addGeneration else {
                return
            }
            persistedMessages.append(message)
            persistedMessageIDs.insert(message.id)
        } catch {
            Log.memory.error("WaxMemory: Failed to ingest message: \(error.localizedDescription)")
        }
    }

    public func context(for query: String, tokenLimit: Int) async -> String {
        do {
            let rag = try await store.search(query)
            return formatRAGContext(rag, tokenLimit: tokenLimit)
        } catch {
            Log.memory.error("WaxMemory: Failed to recall context: \(error.localizedDescription)")
            return ""
        }
    }

    public func allMessages() async -> [MemoryMessage] {
        persistedMessages
    }

    public func clear() async {
        generation += 1
        do {
            try await store.close()
            try removePersistedStoreIfPresent()
            var waxConfig = Wax.Memory.Config.default
            waxConfig.enableVectorSearch = embedder != nil && configuration.enableVectorSearch

            if let embedder {
                store = try await Wax.Memory(at: url, config: waxConfig, embedding: embedder)
            } else {
                store = try await Wax.Memory(at: url, config: waxConfig)
            }
            persistedMessages.removeAll()
            persistedMessageIDs.removeAll()
        } catch {
            Log.memory.error("WaxMemory: Failed to clear persisted state: \(error.localizedDescription)")
        }
    }

    // MARK: - MemorySessionLifecycle

    public func beginMemorySession() async {
        // Session management is not available in the public Wax API; no-op.
    }

    public func endMemorySession() async {
        // Session management is not available in the public Wax API; no-op.
    }

    // MARK: Private

    private var store: Wax.Memory
    private let configuration: Configuration
    private let url: URL
    private let embedder: (any WaxVectorSearch.EmbeddingProvider)?
    private var persistedMessages: [MemoryMessage] = []
    private var persistedMessageIDs: Set<UUID> = []
    private var generation: Int = 0
    private let isoFormatter = ISO8601DateFormatter()

    private func removePersistedStoreIfPresent() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private static func makeFrameStore(at url: URL) async throws -> FrameStore {
        if FileManager.default.fileExists(atPath: url.path) {
            return try await FrameStore.open(at: url)
        }

        return try await FrameStore.create(at: url)
    }

    private static func loadPersistedMessages(from frameStore: FrameStore) async -> [MemoryMessage] {
        let frames = await frameStore.frames()
        let timestampFormatter = ISO8601DateFormatter()
        var messages: [MemoryMessage] = []
        messages.reserveCapacity(frames.count)

        for frame in frames where frame.status == .active {
            guard let messageIDString = frame.metadata["message_id"],
                  let messageID = UUID(uuidString: messageIDString) else {
                continue
            }
            guard let roleRaw = frame.metadata["role"],
                  let role = MemoryMessage.Role(rawValue: roleRaw) else {
                continue
            }
            guard let contentData = try? await frameStore.content(frameID: frame.id),
                  let content = String(data: contentData, encoding: .utf8) else {
                continue
            }

            var metadata = frame.metadata
            metadata.removeValue(forKey: "message_id")
            metadata.removeValue(forKey: "role")
            metadata.removeValue(forKey: "timestamp")

            let timestamp = frame.metadata["timestamp"]
                .flatMap { timestampFormatter.date(from: $0) } ?? Date(timeIntervalSince1970: 0)

            messages.append(
                MemoryMessage(
                    id: messageID,
                    role: role,
                    content: content,
                    timestamp: timestamp,
                    metadata: metadata
                )
            )
        }

        let uniqueMessages = messages.reduce(into: [UUID: MemoryMessage]()) { partialResult, message in
            partialResult[message.id] = message
        }

        return uniqueMessages.values.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }

            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func formatRAGContext(_ rag: RAGContext, tokenLimit: Int) -> String {
        guard tokenLimit > 0 else { return "" }

        var lines: [String] = []
        var usedTokens = 0

        for item in rag.items {
            let kind = switch item.kind {
            case .expanded: "expanded"
            case .surrogate: "surrogate"
            case .snippet: "snippet"
            }

            let sources = item.sources.map { source in
                switch source {
                case .text: return "text"
                case .vector: return "vector"
                case .timeline: return "timeline"
                case .structured: return "structured"
                case .unknown: return "unknown"
                }
            }.joined(separator: ",")

            let prefix = "[\(kind) frame:\(item.frameId) score:\(String(format: "%.2f", item.score)) sources:\(sources)]"
            let candidate = "\(prefix) \(item.text)"
            let tokens = configuration.tokenEstimator.estimateTokens(for: candidate)

            if tokens > tokenLimit { continue }
            if usedTokens + tokens > tokenLimit { break }
            usedTokens += tokens
            lines.append(candidate)
        }

        if lines.isEmpty, rag.items.isEmpty == false {
            return MemoryMessage.formatContext(
                persistedMessagesMatchingQueryText(query: rag.query),
                tokenLimit: tokenLimit,
                tokenEstimator: configuration.tokenEstimator
            )
        }

        return lines.joined(separator: "\n")
    }

    private func persistedMessagesMatchingQueryText(query: String) -> [MemoryMessage] {
        let terms = Self.distinctiveSearchTerms(in: query)
        guard terms.isEmpty == false else { return [] }

        return persistedMessages.filter { message in
            let content = message.content.lowercased()
            return terms.allSatisfy { content.contains($0) }
        }
    }

    static func distinctiveSearchTerms(in text: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "after", "again", "agent", "answer", "before", "context", "memory",
            "message", "messages", "please", "question", "status", "their", "there",
            "these", "those", "through", "using", "where", "which", "would"
        ]

        return Array(
            Set(
                text
                    .lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 4 && stopWords.contains($0) == false }
            )
        ).sorted()
    }
}

public extension WaxMemory {
    /// Default persistent store location used when Swarm creates a durable Wax-backed memory automatically.
    static var defaultStoreURL: URL {
        makeDefaultStoreURL()
    }

    static func makeDefaultStoreURL() -> URL {
        let fileManager = FileManager.default
        let isRunningTests = SwarmRuntimeEnvironment.isRunningTests
        let baseURL = isRunningTests
            ? fileManager.temporaryDirectory
            : (fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory)

        let root = baseURL
            .appendingPathComponent("Swarm", isDirectory: true)
            .appendingPathComponent(
                isRunningTests ? "AgentMemoryTests" : "AgentMemory",
                isDirectory: true
            )

        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let fileName = isRunningTests ? "wax-memory-\(UUID().uuidString).mv2s" : "wax-memory.mv2s"
        return root.appendingPathComponent(fileName)
    }
}
