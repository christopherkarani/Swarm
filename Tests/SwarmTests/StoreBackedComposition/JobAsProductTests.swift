import Foundation
import Testing
@testable import Swarm

@Suite("Job as Product")
struct JobAsProductTests {
    @Test("JobTask carries name, agent, brief, and expected output")
    func jobTaskCarriesExpectedOutputContract() async throws {
        let agent = MockAgentRuntime(response: "ok")
        let task = JobTask(
            name: "alpha",
            agent: agent,
            brief: "write the section",
            expectedOutput: "one paragraph"
        )
        #expect(task.name == "alpha")
        #expect(task.brief == "write the section")
        #expect(task.expectedOutput == "one paragraph")
    }

    @Test("run(_:tasks:merge:observer:) returns results keyed by task name")
    func runTasksReturnsKeyedResults() async throws {
        let writerA = MockAgentRuntime(response: "section-a")
        let writerB = MockAgentRuntime(response: "section-b")

        let product = try await Job().run(
            "topic",
            tasks: [
                JobTask(name: "beta", agent: writerB, brief: "b", expectedOutput: "text"),
                JobTask(name: "alpha", agent: writerA, brief: "a", expectedOutput: "text"),
            ],
            merge: .indexed
        )

        #expect(product.results["alpha"]?.output == "section-a")
        #expect(product.results["beta"]?.output == "section-b")
        #expect(product.results.count == 2)
    }

    @Test("run(_:tasks:) merges the summary with MergeStrategy")
    func runTasksMergesSummary() async throws {
        let writerA = MockAgentRuntime(response: "section-a")
        let writerB = MockAgentRuntime(response: "section-b")

        let product = try await Job().run(
            "topic",
            tasks: [
                JobTask(name: "beta", agent: writerB, brief: "b"),
                JobTask(name: "alpha", agent: writerA, brief: "a"),
            ],
            merge: .indexed
        )

        #expect(product.summary == "[0]: section-a\n[1]: section-b")
    }

    @Test("expected output reaches the helper brief")
    func expectedOutputReachesHelperBrief() async throws {
        let writer = CapturingAgentRuntime(response: "done")

        _ = try await Job().run(
            "topic",
            tasks: [JobTask(name: "alpha", agent: writer, brief: "write it", expectedOutput: "one paragraph")],
            merge: .indexed
        )

        let input = try #require(await writer.inputs.first)
        #expect(input.contains("write it"))
        #expect(input.contains("one paragraph"))
    }

    @Test("duplicate task names fail before any helper runs")
    func duplicateTaskNamesFail() async {
        let agent = MockAgentRuntime(response: "ok")
        do {
            _ = try await Job().run(
                "topic",
                tasks: [
                    JobTask(name: "alpha", agent: agent, brief: "a"),
                    JobTask(name: " alpha ", agent: agent, brief: "b"),
                ]
            )
            Issue.record("expected duplicateChildName")
        } catch let error as JobError {
            #expect(error == .duplicateChildName("alpha"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("fanOut forwards the observer to child runs")
    func fanOutForwardsObserver() async throws {
        let writer = MockAgentRuntime(response: "section")
        let observer = RecordingJobObserver()

        _ = try await Job().run("topic") { session in
            try await session.fanOut(
                [JobChild(name: "alpha", agent: writer, brief: "a")],
                observer: observer
            )
        }

        #expect(await observer.starts == ["a"])
        #expect(await observer.ends == ["section"])
    }

    @Test("run(_:tasks:) forwards the observer to child runs")
    func runTasksForwardsObserver() async throws {
        let writer = MockAgentRuntime(response: "section")
        let observer = RecordingJobObserver()

        _ = try await Job().run(
            "topic",
            tasks: [JobTask(name: "alpha", agent: writer, brief: "a")],
            observer: observer
        )

        #expect(await observer.starts.count == 1)
        #expect(await observer.ends == ["section"])
    }

    @Test("manager delegation drafts briefs from notes then fans out once")
    func managerDelegationDraftsBriefsThenFansOut() async throws {
        let manager = CapturingAgentRuntime(response: "drafted brief")
        let helper = CapturingAgentRuntime(response: "section")

        let product = try await Job().delegate(
            "topic",
            manager: manager,
            assignments: [
                JobAssignment(name: "alpha", agent: helper, notesQuery: "alpha", expectedOutput: "text"),
            ]
        ) { session in
            await session.ingest(JobRecord(kind: "note", text: "alpha body"))
        }

        let managerInput = try #require(await manager.inputs.first)
        #expect(managerInput.contains("alpha body"))
        let input = try #require(await helper.inputs.first)
        #expect(input.contains("drafted brief"))
        #expect(input.contains("text"))
        #expect(product.results["alpha"]?.output == "section")
    }

    @Test("manager delegation drafts one brief per assignment and runs one fan-out")
    func managerDelegationKeepsOneFanOut() async throws {
        let manager = CapturingAgentRuntime(response: "brief")
        let helperA = CapturingAgentRuntime(response: "section-a")
        let helperB = CapturingAgentRuntime(response: "section-b")

        let product = try await Job().delegate(
            "topic",
            manager: manager,
            assignments: [
                JobAssignment(name: "alpha", agent: helperA, notesQuery: "alpha"),
                JobAssignment(name: "beta", agent: helperB, notesQuery: "beta"),
            ],
            merge: .indexed
        ) { session in
            await session.ingest(JobRecord(kind: "note", text: "alpha body"))
            await session.ingest(JobRecord(kind: "note", text: "beta body"))
        }

        let managerInputs = await manager.inputs
        #expect(managerInputs.count == 2)
        #expect(managerInputs.contains { $0.contains("alpha body") })
        #expect(managerInputs.contains { $0.contains("beta body") })
        #expect(await helperA.inputs.count == 1)
        #expect(await helperB.inputs.count == 1)
        #expect(product.results["alpha"]?.output == "section-a")
        #expect(product.results["beta"]?.output == "section-b")
        #expect(product.results.count == 2)
        #expect(product.summary == "[0]: section-a\n[1]: section-b")
    }
}

actor RecordingJobObserver: AgentObserver {
    private(set) var starts: [String] = []
    private(set) var ends: [String] = []

    func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input: String) async {
        starts.append(input)
    }

    func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async {
        ends.append(result.output)
    }
}
