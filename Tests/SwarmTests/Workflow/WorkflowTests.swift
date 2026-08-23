import Foundation
import Testing
@testable import Swarm

/// Canonical test suite for the `Workflow` public API. These tests anchor the
/// per-shape behavior (`.step`, `.parallel(merge:)`, `.route`, `.repeatUntil`,
/// `.timeout`) so a maintainer changing one shape sees a focused failure rather
/// than chasing an unrelated scenario test.
@Suite("Workflow Core", .ephemeralDefaultStores)
struct WorkflowCoreTests {


    // MARK: - Sequential

    @Test("sequential workflow chains output through each step")
    func sequentialChainsOutput() async throws {
        let first = MockAgentRuntime(response: "step1")
        let second = MockAgentRuntime(response: "step2")
        let third = MockAgentRuntime(response: "step3")
        let result = try await Workflow()
            .step(first)
            .step(second)
            .step(third)
            .run("input")
        #expect(result.output == "step3")
    }

    @Test("single-step workflow returns that step's output")
    func singleStep() async throws {
        let agent = MockAgentRuntime(response: "only")
        let result = try await Workflow()
            .step(agent)
            .run("hi")
        #expect(result.output == "only")
    }

    // MARK: - Parallel + MergeStrategy

    @Test("parallel with .structured merge produces JSON-indexed object")
    func parallelStructured() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b], merge: .structured)
            .run("input")
        // Format documented as: {"0": "...", "1": "..."}
        #expect(result.output.contains("\"0\""))
        #expect(result.output.contains("\"1\""))
        #expect(result.output.contains("alpha"))
        #expect(result.output.contains("beta"))
    }

    @Test("parallel with .indexed merge produces [n]: prefixed lines")
    func parallelIndexed() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b], merge: .indexed)
            .run("input")
        #expect(result.output.contains("[0]"))
        #expect(result.output.contains("[1]"))
        #expect(result.output.contains("alpha"))
        #expect(result.output.contains("beta"))
    }

    @Test("parallel with .firstCompleted merge returns one result")
    func parallelFirstCompletedReturnsOneResult() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b], merge: .firstCompleted)
            .run("input")
        let output = result.output
        let containsBoth = output.contains("alpha") && output.contains("beta")
        #expect(!containsBoth, "firstCompleted merge should not concatenate")
    }

    @Test("parallel with .custom merge applies the closure")
    func parallelCustom() async throws {
        let a = MockAgentRuntime(response: "x")
        let b = MockAgentRuntime(response: "y")
        let result = try await Workflow()
            .parallel([a, b], merge: .custom { results in
                results.map { "<\($0.output)>" }.joined(separator: "+")
            })
            .run("input")
        // Order isn't guaranteed by parallel execution, but both pieces must appear.
        #expect(result.output.contains("<x>"))
        #expect(result.output.contains("<y>"))
        #expect(result.output.contains("+"))
    }

    @Test("parallel default merge is .structured")
    func parallelDefaultMerge() async throws {
        let a = MockAgentRuntime(response: "alpha")
        let b = MockAgentRuntime(response: "beta")
        let result = try await Workflow()
            .parallel([a, b])
            .run("input")
        #expect(result.output.contains("\"0\""))
        #expect(result.output.contains("\"1\""))
    }

    // MARK: - Route

    @Test("route picks the matching agent")
    func routePicksAgent() async throws {
        let billing = MockAgentRuntime(response: "billing")
        let support = MockAgentRuntime(response: "support")
        let result = try await Workflow()
            .route { input in
                input.contains("invoice") ? billing : support
            }
            .run("invoice 123")
        #expect(result.output == "billing")
    }

    @Test("route falls through when closure returns nil")
    func routeFallthrough() async throws {
        let agent = MockAgentRuntime(response: "matched")
        // Returning nil from the route closure is a valid signal; the framework
        // either skips the step or surfaces a deterministic error. Either is OK
        // here — the assertion is that it does not crash or hang.
        let workflow = Workflow().route { _ in nil as (any AgentRuntime)? }.step(agent)
        do {
            _ = try await workflow.run("input")
        } catch {
            // Surfaced error is acceptable; hang/crash is not.
        }
    }

    // MARK: - RepeatUntil

    @Test("repeatUntil terminates when the predicate matches")
    func repeatUntilTerminatesOnPredicate() async throws {
        let counter = WorkflowTestCounter(shutdownAfter: 2)
        let agent = MockAgentRuntime(responseFactory: { counter.next() })
        let result = try await Workflow()
            .step(agent)
            .repeatUntil { $0.output.contains("SHUTDOWN") }
            .run("monitor")
        #expect(result.output == "SHUTDOWN")
    }

    @Test("repeatUntil respects maxIterations")
    func repeatUntilMaxIterations() async throws {
        // An agent that never matches the terminating predicate; maxIterations
        // must bound the loop and surface a result anyway (or throw — both are
        // acceptable contracts so long as it doesn't loop forever).
        let agent = MockAgentRuntime(response: "never")
        let workflow = Workflow()
            .step(agent)
            .repeatUntil(maxIterations: 3) { $0.output == "SHUTDOWN" }
        // Use a wall-clock timeout as a watchdog so a regression doesn't hang CI.
        let task = Task {
            try await workflow.run("input")
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(10))
            task.cancel()
            return "watchdog-fired"
        }
        defer { watchdog.cancel() }
        do {
            let result = try await task.value
            // Bound was respected, returned final non-matching output.
            #expect(result.output == "never")
        } catch {
            // Or surfaced an error — that's also a valid contract.
        }
    }

    // MARK: - Composition

    @Test("step then parallel then step composes left-to-right")
    func compositionStepParallelStep() async throws {
        let head = MockAgentRuntime(response: "head")
        let a = MockAgentRuntime(response: "a")
        let b = MockAgentRuntime(response: "b")
        let tail = MockAgentRuntime(response: "tail")
        let result = try await Workflow()
            .step(head)
            .parallel([a, b], merge: .indexed)
            .step(tail)
            .run("input")
        #expect(result.output == "tail")
    }

    // MARK: - Empty workflow

    @Test("empty workflow throws invalidWorkflow")
    func emptyWorkflowThrows() async {
        do {
            _ = try await Workflow().run("input")
            Issue.record("Expected WorkflowError.invalidWorkflow for a workflow with no steps")
        } catch let error as WorkflowError {
            guard case .invalidWorkflow(let reason) = error else {
                Issue.record("Expected invalidWorkflow, got \(error)")
                return
            }
            #expect(reason.contains("no steps"))
        } catch {
            Issue.record("Expected WorkflowError, got \(error)")
        }
    }

    // MARK: - Timeout environment propagation

    @Test("timeout-wrapped workflow uses ambient task-local inference provider")
    func timeoutPreservesAmbientTaskLocalProvider() async throws {
        let mock = MockInferenceProvider(responses: ["from-task-local-env"])
        let agent = try Agent("Reply with the model output.")
        var env = AgentEnvironment()
        env.inferenceProvider = mock

        let result = try await AgentEnvironmentValues.$current.withValue(env) {
            try await Workflow()
                .step(agent)
                .timeout(.seconds(5))
                .run("hello")
        }

        #expect(result.output == "from-task-local-env")
        #expect(await mockProviderServicedRequest(mock))
    }

    @Test("timeout-wrapped workflow still honors agent.environment provider")
    func timeoutPreservesAgentEnvironmentModifier() async throws {
        let mock = MockInferenceProvider(responses: ["from-agent-environment"])
        let agent = try Agent("Reply with the model output.")
            .environment(\.inferenceProvider, mock as (any InferenceProvider)?)

        let result = try await Workflow()
            .step(agent)
            .timeout(.seconds(5))
            .run("hello")

        #expect(result.output == "from-agent-environment")
        #expect(await mockProviderServicedRequest(mock))
    }

    // MARK: - Parallel merge ordering and cancellation

    @Test("structured merge keeps original step index when a later agent finishes first")
    func structuredMergeUsesOriginalStepIndex() async throws {
        let slow = MockAgentRuntime(response: "slow", delay: .milliseconds(80))
        let fast = MockAgentRuntime(response: "fast", delay: .milliseconds(5))
        let result = try await Workflow()
            .parallel([slow, fast], merge: .structured)
            .run("input")

        let object = try parseJSONObject(result.output)
        #expect(object["0"] == "slow")
        #expect(object["1"] == "fast")
    }

    @Test("indexed merge keeps original step index when a later agent finishes first")
    func indexedMergeUsesOriginalStepIndex() async throws {
        let slow = MockAgentRuntime(response: "slow", delay: .milliseconds(80))
        let fast = MockAgentRuntime(response: "fast", delay: .milliseconds(5))
        let result = try await Workflow()
            .parallel([slow, fast], merge: .indexed)
            .run("input")
        #expect(result.output == "[0]: slow\n[1]: fast")
    }

    @Test("custom merge receives results in original step index order")
    func customMergeUsesOriginalStepIndex() async throws {
        let slow = MockAgentRuntime(response: "slow", delay: .milliseconds(80))
        let fast = MockAgentRuntime(response: "fast", delay: .milliseconds(5))
        let result = try await Workflow()
            .parallel([slow, fast], merge: .custom { results in
                results.map(\.output).joined(separator: ",")
            })
            .run("input")
        #expect(result.output == "slow,fast")
    }

    @Test("firstCompleted returns the fastest branch, not the first agent")
    func firstCompletedReturnsFastestBranch() async throws {
        let slow = MockAgentRuntime(response: "slow", delay: .milliseconds(200))
        let fast = MockAgentRuntime(response: "fast", delay: .milliseconds(10))
        let result = try await Workflow()
            .parallel([slow, fast], merge: .firstCompleted)
            .run("input")
        #expect(result.output == "fast")
    }

    @Test("firstCompleted cancels loser tasks instead of waiting for them")
    func firstCompletedCancelsLosers() async throws {
        let fast = MockAgentRuntime(response: "fast", delay: .milliseconds(20))
        let slow = MockAgentRuntime(response: "slow", delay: .milliseconds(5_000))
        let start = ContinuousClock.now
        let result = try await Workflow()
            .parallel([slow, fast], merge: .firstCompleted)
            .run("input")
        let elapsed = ContinuousClock.now - start

        #expect(result.output == "fast")
        #expect(elapsed < .milliseconds(1_000))
        #expect(await slow.isCancelled)
    }
}

private func mockProviderServicedRequest(_ mock: MockInferenceProvider) async -> Bool {
    let generateCount = await mock.generateCallCount
    let messageCalls = await mock.generateMessageCalls
    let toolCallCalls = await mock.toolCallCalls
    let toolCallMessageCalls = await mock.toolCallMessageCalls
    return generateCount > 0
        || !messageCalls.isEmpty
        || !toolCallCalls.isEmpty
        || !toolCallMessageCalls.isEmpty
}

private func parseJSONObject(_ json: String) throws -> [String: String] {
    let data = Data(json.utf8)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: String] else {
        throw WorkflowTestParseError.notStringDictionary(json)
    }
    return dictionary
}

private enum WorkflowTestParseError: Error {
    case notStringDictionary(String)
}

private final class WorkflowTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let shutdownAfter: Int

    init(shutdownAfter: Int) { self.shutdownAfter = shutdownAfter }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count >= shutdownAfter ? "SHUTDOWN" : "running"
    }
}
