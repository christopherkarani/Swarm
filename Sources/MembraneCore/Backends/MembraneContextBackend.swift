public struct MembraneBackendPreparation: Sendable {
    public let plan: ContextPlan
    public let snapshot: ContextSnapshot?

    public init(plan: ContextPlan, snapshot: ContextSnapshot? = nil) {
        self.plan = plan
        self.snapshot = snapshot
    }
}

public protocol MembraneContextBackend: Sendable {
    var backendID: String { get }

    func prepare(
        request: ContextRequest,
        budget: ContextBudget,
        snapshot: ContextSnapshot?
    ) async throws -> MembraneBackendPreparation

    func restore(snapshot: ContextSnapshot?) async throws
    func snapshot() async throws -> ContextSnapshot?
}
