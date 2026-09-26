/// Portable `MembraneContextBackend` that passes the request prompt through unchanged.
///
/// This is the default backend for `MembraneSession`: it lives in MembraneCore,
/// touches no Apple-only frameworks, and behaves identically on every platform.
/// Clients that want ContextCore-backed windowing inject
/// `MembraneContextCoreBackend` explicitly. With Integrations it links on all
/// platforms (portable CPU/hash backends on Linux, Metal acceleration on Apple).
public actor PassthroughMembraneBackend: MembraneContextBackend {
    public nonisolated let backendID = MembraneBackendID.passthrough.rawValue

    private var lastSnapshot: ContextSnapshot?

    public init() {}

    public func prepare(
        request: ContextRequest,
        budget: ContextBudget,
        snapshot: ContextSnapshot?
    ) async throws -> MembraneBackendPreparation {
        let basePrompt = request.basePrompt.isEmpty ? request.userInput : request.basePrompt
        let backendSnapshot = ContextSnapshot(
            budget: snapshot?.budget ?? .init(totalTokens: budget.totalTokens),
            toolState: snapshot?.toolState ?? .init(
                mode: .allowAll,
                loadedToolNames: [],
                allowListToolNames: [],
                usageCounts: []
            ),
            pointerIDs: snapshot?.pointerIDs ?? [],
            backendID: backendID,
            backendState: nil
        ).normalized()
        lastSnapshot = backendSnapshot

        return MembraneBackendPreparation(
            plan: ContextPlan(
                prompt: basePrompt,
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
}
