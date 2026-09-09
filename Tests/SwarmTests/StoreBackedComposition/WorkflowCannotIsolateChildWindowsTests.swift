import Foundation
import Testing
@testable import Swarm

/// Gap evidence for store-backed composition.
///
/// Today's `Workflow` is a string cursor: each step's output becomes the next
/// input, and `parallel` gives every child the same `inputSnapshot`.
/// A Swarmy-shaped run needs per-child retrieved windows. This suite records
/// that `Workflow` cannot express that. It does not add a public type.
@Suite("StoreBackedComposition Workflow cannot isolate child windows")
struct StoreBackedCompositionWorkflowCannotIsolateChildWindowsTests {
    @Test("Workflow.parallel feeds every child the previous step's full output")
    func workflowParallelSharesOneInputSnapshot() async throws {
        let researcherDump = "notes:\nalpha body\nbeta body"
        let researcher = MockAgentRuntime(response: researcherDump)
        let writerA = CapturingAgentRuntime(response: "section-a")
        let writerB = CapturingAgentRuntime(response: "section-b")

        _ = try await Workflow()
            .step(researcher)
            .parallel([writerA, writerB], merge: .indexed)
            .run("topic")

        let inputA = try #require(await writerA.inputs.first)
        let inputB = try #require(await writerB.inputs.first)

        #expect(inputA == researcherDump)
        #expect(inputB == researcherDump)
        #expect(inputA == inputB)

        let writerAReceivedIsolatedAlphaWindow =
            inputA.contains("alpha body") && inputA.contains("beta body") == false
        let writerBReceivedIsolatedBetaWindow =
            inputB.contains("beta body") && inputB.contains("alpha body") == false
        #expect(writerAReceivedIsolatedAlphaWindow == false)
        #expect(writerBReceivedIsolatedBetaWindow == false)
    }
}

/// Test double that records each `run` input.
actor CapturingAgentRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String
    nonisolated let configuration: AgentConfiguration
    private let response: String
    private var receivedInputs: [String] = []

    init(response: String, instructions: String = "Capturing agent") {
        self.response = response
        self.instructions = instructions
        self.configuration = .default
    }

    var inputs: [String] {
        receivedInputs
    }

    func run(
        _ input: String,
        session _: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        receivedInputs.append(input)
        await observer?.onAgentStart(context: nil, agent: self, input: input)
        let result = AgentResult(output: response)
        await observer?.onAgentEnd(context: nil, agent: self, result: result)
        return result
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: self.response))))
            continuation.finish()
        }
    }

    func cancel() async {}
}
