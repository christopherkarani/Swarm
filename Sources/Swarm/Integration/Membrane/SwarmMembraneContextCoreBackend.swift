import ContextCore
import Foundation
import MembraneCore

actor SwarmMembraneContextCoreBackend: MembraneContextBackend {
    let backendID = "swarm.contextcore"

    private let configuration: ContextCore.ContextConfiguration
    private let fileManager: FileManager
    private var lastSnapshot: ContextSnapshot?

    init(
        configuration: ContextCore.ContextConfiguration = .default,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func prepare(
        request: ContextRequest,
        budget: MembraneCore.ContextBudget,
        snapshot: ContextSnapshot?
    ) async throws -> MembraneBackendPreparation {
        if let snapshot {
            lastSnapshot = snapshot.normalized()
        }

        let context = try await makeContext(from: request)
        let window = try await context.buildWindow(
            currentTask: request.userInput,
            maxTokens: budget.totalTokens
        )

        let contextualPrompt = makePrompt(
            basePrompt: request.basePrompt.isEmpty ? request.userInput : request.basePrompt,
            supplementalContext: window.formatted(style: .raw)
        )

        let backendState = try await checkpointData(for: context)
        let backendSnapshot = ContextSnapshot(
            budget: snapshot?.budget ?? .init(totalTokens: budget.totalTokens),
            csoSummaries: [],
            pagingCursor: nil,
            toolState: snapshot?.toolState ?? .init(mode: .allowAll, loadedToolNames: [], allowListToolNames: [], usageCounts: []),
            pointerIDs: snapshot?.pointerIDs ?? [],
            backendID: backendID,
            backendState: backendState
        ).normalized()
        lastSnapshot = backendSnapshot

        return MembraneBackendPreparation(
            plan: ContextPlan(
                prompt: contextualPrompt,
                systemPrompt: request.systemPrompt,
                toolPlan: request.toolPlan,
                budget: budget,
                metadata: request.metadata
            ),
            snapshot: backendSnapshot
        )
    }

    func restore(snapshot: ContextSnapshot?) async throws {
        lastSnapshot = snapshot?.normalized()
    }

    func snapshot() async throws -> ContextSnapshot? {
        lastSnapshot
    }

    private func makeContext(from request: ContextRequest) async throws -> ContextCore.AgentContext {
        let context = try ContextCore.AgentContext(configuration: configuration)
        let sessionID = UUID(uuidString: request.metadata.sessionID) ?? UUID()
        try await context.beginSession(id: sessionID, systemPrompt: request.systemPrompt)

        for slice in deduplicatedSlices(from: request) {
            try await context.append(turn: makeTurn(from: slice))
        }

        return context
    }

    private func deduplicatedSlices(from request: ContextRequest) -> [ContextSlice] {
        var ordered: [ContextSlice] = []
        var seen: Set<String> = []

        for slice in request.history + request.memories + request.retrieval {
            let key = slice.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard key.isEmpty == false, seen.insert(key).inserted else {
                continue
            }
            ordered.append(slice)
        }

        return ordered
    }

    private func makeTurn(from slice: ContextSlice) -> ContextCore.Turn {
        let role: ContextCore.TurnRole = switch slice.source {
        case .system:
            .system
        case .tool, .pointer:
            .tool
        case .history:
            if slice.content.hasPrefix("[User]:") {
                .user
            } else if slice.content.hasPrefix("[System]:") {
                .system
            } else {
                .assistant
            }
        case .memory, .retrieval:
            .assistant
        }

        return ContextCore.Turn(
            role: role,
            content: slice.content,
            timestamp: Date(),
            tokenCount: max(1, slice.tokenCount)
        )
    }

    private func makePrompt(basePrompt: String, supplementalContext: String) -> String {
        let trimmedContext = supplementalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContext.isEmpty == false else {
            return basePrompt
        }
        return """
        \(basePrompt)

        Relevant Context:
        \(trimmedContext)
        """
    }

    private func checkpointData(for context: ContextCore.AgentContext) async throws -> Data {
        let url = temporaryCheckpointURL()
        try await context.checkpoint(to: url)
        defer { try? fileManager.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    private func temporaryCheckpointURL() -> URL {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("swarm-membrane-contextcore", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}
