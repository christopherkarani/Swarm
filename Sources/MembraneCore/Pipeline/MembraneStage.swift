/// Pipeline stage contract.
///
/// Budget authority is the standalone `budget` parameter. Wrapper types carry
/// snapshots for convenience, but each stage must apply decisions using the
/// explicit budget passed into `process`.
public protocol MembraneStage: Actor, Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func process(_ input: Input, budget: ContextBudget) async throws -> Output
}
