import Foundation
@testable import Swarm
import Testing

@Suite("Workflow signatures")
struct WorkflowSignatureTests {
    @Test("shifted line numbers produce the same signature")
    func shiftedLineNumbersProduceTheSameSignature() {
        let first = Workflow()
            .step(namedAgent("Writer"))
            .route({ _ in namedAgent("Router") }, fileID: "First.swift", line: 10)
            .repeatUntil(maxIterations: 2, { _ in true }, fileID: "First.swift", line: 20)
            .parallel(
                [namedAgent("Branch")],
                merge: .custom { $0.map(\.output).joined() },
                fileID: "First.swift",
                line: 30
            )

        let second = Workflow()
            .step(namedAgent("Writer"))
            .route({ _ in namedAgent("Router") }, fileID: "Second.swift", line: 410)
            .repeatUntil(maxIterations: 2, { _ in true }, fileID: "Second.swift", line: 880)
            .parallel(
                [namedAgent("Branch")],
                merge: .custom { $0.map(\.output).joined() },
                fileID: "Second.swift",
                line: 990
            )

        #expect(first.workflowSignature == second.workflowSignature)
        #expect(first.workflowSignature.contains("stable:"))
        #expect(!first.workflowSignature.contains("source:"))
    }

    @Test("different workflows produce different signatures")
    func differentWorkflowsProduceDifferentSignatures() {
        let sequential = Workflow()
            .step(namedAgent("Alpha"))
        let routed = Workflow()
            .route { _ in namedAgent("Alpha") }
        let otherAgent = Workflow()
            .step(namedAgent("Beta"))
        let extraStep = Workflow()
            .step(namedAgent("Alpha"))
            .step(namedAgent("Beta"))

        #expect(sequential.workflowSignature != routed.workflowSignature)
        #expect(sequential.workflowSignature != otherAgent.workflowSignature)
        #expect(sequential.workflowSignature != extraStep.workflowSignature)
    }

    @Test("explicit signature is used unchanged and still distinguishes behavior")
    func explicitSignatureIsUsedUnchanged() {
        let first = Workflow()
            .route({ _ in namedAgent("Router") }, signature: "route-v1", fileID: "A.swift", line: 1)
        let second = Workflow()
            .route({ _ in namedAgent("Router") }, signature: "route-v2", fileID: "A.swift", line: 1)
        let same = Workflow()
            .route({ _ in namedAgent("Router") }, signature: "route-v1", fileID: "B.swift", line: 99)

        #expect(first.workflowSignature != second.workflowSignature)
        #expect(first.workflowSignature == same.workflowSignature)
        #expect(first.workflowSignature.contains("explicit:"))
        #expect(!first.usesImplicitOpaqueIdentity)
        #expect(Workflow().route { _ in namedAgent("Router") }.usesImplicitOpaqueIdentity)
    }

    @Test("legacy fileID:line checkpoints fail with a dedicated resume message")
    func legacySourceIdentityFailsWithClearMessage() {
        let current = Workflow()
            .route { _ in namedAgent("Router") }
            .workflowSignature
        let legacy = current.replacingOccurrences(of: ":stable:", with: ":source:")
        #expect(legacy.contains(":source:"))
        #expect(legacy != current)

        let error = workflowDurableSignatureMismatch(
            checkpointSignature: legacy,
            currentSignature: current
        )

        guard let error else {
            Issue.record("expected a resume mismatch for legacy source identity")
            return
        }
        #expect(error == .resumeDefinitionMismatch(
            reason: """
            Checkpoint uses the legacy fileID:line workflow identity. Re-run this \
            workflow from the start; Swarm now identifies steps by kind, position, \
            and explicit signature: values, not source locations.
            """
        ))
    }

    @Test("legacy first merge signatures resume after firstCompleted rename")
    func legacyFirstMergeSignatureResumesAfterRename() {
        let current = Workflow()
            .parallel([namedAgent("Branch")], merge: .firstCompleted)
            .workflowSignature
        let legacy = current.replacingOccurrences(of: ":firstCompleted", with: ":first")

        #expect(legacy != current)
        #expect(
            workflowDurableSignatureMismatch(
                checkpointSignature: legacy,
                currentSignature: current
            ) == nil
        )
    }

    @Test("matching signatures produce no mismatch")
    func matchingSignaturesProduceNoMismatch() {
        let signature = Workflow().step(namedAgent("Solo")).workflowSignature
        #expect(
            workflowDurableSignatureMismatch(
                checkpointSignature: signature,
                currentSignature: signature
            ) == nil
        )
    }
}

private func namedAgent(_ name: String) -> MockAgentRuntime {
    MockAgentRuntime(
        response: name,
        configuration: AgentConfiguration(name: name)
    )
}
