import Foundation
import ContextCore
import MembraneCore

public actor MembraneContextCoreBackend: MembraneContextBackend {
    public let backendID = "contextcore"

    private let configuration: ContextConfiguration
    private let fileManager: FileManager
    private var lastSnapshot: ContextSnapshot?

    public init(
        configuration: ContextConfiguration = .default,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func prepare(
        request: ContextRequest,
        budget: ContextBudget,
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

    public func restore(snapshot: ContextSnapshot?) async throws {
        lastSnapshot = snapshot?.normalized()
    }

    public func snapshot() async throws -> ContextSnapshot? {
        lastSnapshot
    }

    private func makeContext(from request: ContextRequest) async throws -> AgentContext {
        let context = try AgentContext(configuration: configuration)
        let sessionID = UUID(uuidString: request.metadata.sessionID) ?? UUID()
        try await context.beginSession(id: sessionID, systemPrompt: request.systemPrompt)

        let slices = request.memories + request.retrieval
        for slice in slices {
            try await context.append(
                turn: Turn(
                    role: .assistant,
                    content: slice.content,
                    timestamp: Date(),
                    tokenCount: max(1, slice.tokenCount)
                )
            )
        }

        return context
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

    private func checkpointData(for context: AgentContext) async throws -> Data {
        let url = temporaryCheckpointURL()
        try await context.checkpoint(to: url)
        defer { try? fileManager.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    private func temporaryCheckpointURL() -> URL {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("membrane-contextcore", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}
