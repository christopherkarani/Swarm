import Testing
@testable import Swarm

@Suite("FallbackChain StepError Equality")
struct FallbackChainStepErrorEqualityTests {
    private struct LocalizedLookalike: Error {
        let id: String
        var localizedDescription: String { "same text" }
    }

    @Test("distinct errors sharing only localizedDescription compare unequal")
    func distinctErrorsAreNotEqual() {
        let lhs = StepError(stepName: "s", stepIndex: 0, error: LocalizedLookalike(id: "a"))
        let rhs = StepError(stepName: "s", stepIndex: 0, error: LocalizedLookalike(id: "b"))

        #expect(lhs.error.localizedDescription == rhs.error.localizedDescription)
        #expect(lhs != rhs)
    }

    @Test("errors of the same type and description compare equal")
    func identicalErrorsAreEqual() {
        let error = LocalizedLookalike(id: "a")
        let lhs = StepError(stepName: "s", stepIndex: 1, error: error)
        let rhs = StepError(stepName: "s", stepIndex: 1, error: error)

        #expect(lhs == rhs)
    }
}
