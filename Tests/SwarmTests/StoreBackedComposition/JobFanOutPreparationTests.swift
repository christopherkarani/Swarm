import Testing
@testable import Swarm

@Suite("StoreBackedComposition Job fan-out preparation")
struct StoreBackedCompositionJobFanOutPreparationTests {
    @Test("empty child list fails")
    func emptyChildListFails() throws {
        #expect(throws: JobError.emptyFanOut) {
            try JobFanOutPreparation.prepare([])
        }
    }

    @Test("prepare trims names and preserves order")
    func prepareTrimsNamesAndPreservesOrder() throws {
        let agent = MockAgentRuntime(response: "ok")
        let prepared = try JobFanOutPreparation.prepare([
            JobChild(name: " alpha ", agent: agent, brief: "a"),
            JobChild(name: "beta", agent: agent, brief: "b"),
        ])
        #expect(prepared.map(\.name) == ["alpha", "beta"])
    }

    @Test("empty child name fails")
    func prepareEmptyChildNameFails() {
        let agent = MockAgentRuntime(response: "ok")
        #expect(throws: JobError.emptyChildName) {
            try JobFanOutPreparation.prepare([
                JobChild(name: "  ", agent: agent, brief: "a"),
            ])
        }
    }

    @Test("duplicate trimmed names fail")
    func prepareDuplicateTrimmedNamesFail() {
        let agent = MockAgentRuntime(response: "ok")
        #expect(throws: JobError.duplicateChildName("alpha")) {
            try JobFanOutPreparation.prepare([
                JobChild(name: "alpha", agent: agent, brief: "a"),
                JobChild(name: " alpha ", agent: agent, brief: "b"),
            ])
        }
    }
}
