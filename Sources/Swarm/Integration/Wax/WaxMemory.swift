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

    public var count: Int { messages.count }
    public var isEmpty: Bool { messages.isEmpty }

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

        var waxConfig = Wax.Memory.Config.default
        waxConfig.enableVectorSearch = embedder != nil && configuration.enableVectorSearch

        if let embedder {
            self.store = try await Wax.Memory(at: url, config: waxConfig, embedding: embedder)
        } else {
            self.store = try await Wax.Memory(at: url, config: waxConfig)
        }

        self.memoryPromptTitle = configuration.promptTitle
        self.memoryPromptGuidance = configuration.promptGuidance
    }

    public func add(_ message: MemoryMessage) async {
        var metadata = message.metadata
        metadata["role"] = message.role.rawValue
        metadata["timestamp"] = isoFormatter.string(from: message.timestamp)
        metadata["message_id"] = message.id.uuidString

        do {
            try await store.save(message.content, metadata: metadata)
            messages.append(message)
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
        messages
    }

    public func clear() async {
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
            messages.removeAll()
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
    private var messages: [MemoryMessage] = []
    private let isoFormatter = ISO8601DateFormatter()

    private func removePersistedStoreIfPresent() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
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

            if usedTokens + tokens > tokenLimit { break }
            usedTokens += tokens
            lines.append(candidate)
        }

        return lines.joined(separator: "\n")
    }
}
