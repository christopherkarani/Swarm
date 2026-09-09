import Foundation
import Testing
@testable import Swarm

@Suite("StoreBackedComposition Job")
struct StoreBackedCompositionJobTests {
    @Test("Job fan-out gives each child an isolated notes window")
    func jobFanOutGivesEachChildAnIsolatedWindow() async throws {
        let writerA = CapturingAgentRuntime(response: "section-a")
        let writerB = CapturingAgentRuntime(response: "section-b")

        let results = try await Job().run("topic") { session in
            #expect(session.input == "topic")
            await session.ingest(JobRecord(kind: "note", text: "alpha body"))
            await session.ingest(JobRecord(kind: "note", text: "beta body"))
            let alpha = await session.window(query: "alpha", tokenLimit: 400)
            let beta = await session.window(query: "beta", tokenLimit: 400)
            return try await session.fanOut([
                JobChild(name: "alpha", agent: writerA, brief: alpha),
                JobChild(name: "beta", agent: writerB, brief: beta),
            ])
        }

        let inputA = try #require(await writerA.inputs.first)
        let inputB = try #require(await writerB.inputs.first)
        #expect(inputA.contains("alpha body"))
        #expect(inputA.contains("beta body") == false)
        #expect(inputB.contains("beta body"))
        #expect(inputB.contains("alpha body") == false)
        #expect(results.map(\.name) == ["alpha", "beta"])
        #expect(results.map(\.result.output) == ["section-a", "section-b"])
    }

    @Test("duplicate child names fail")
    func duplicateChildNameFails() async {
        let agent = MockAgentRuntime(response: "ok")
        do {
            _ = try await Job().run("topic") { session in
                try await session.fanOut([
                    JobChild(name: "alpha", agent: agent, brief: "a"),
                    JobChild(name: " alpha ", agent: agent, brief: "b"),
                ])
            }
            Issue.record("expected duplicateChildName")
        } catch let error as JobError {
            #expect(error == .duplicateChildName("alpha"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("empty child list fails")
    func emptyFanOutFails() async {
        do {
            _ = try await Job().run("topic") { session in
                try await session.fanOut([])
            }
            Issue.record("expected emptyFanOut")
        } catch let error as JobError {
            #expect(error == .emptyFanOut)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("empty child name fails")
    func emptyChildNameFails() async {
        let agent = MockAgentRuntime(response: "ok")
        do {
            _ = try await Job().run("topic") { session in
                try await session.fanOut([
                    JobChild(name: "  ", agent: agent, brief: "a"),
                ])
            }
            Issue.record("expected emptyChildName")
        } catch let error as JobError {
            #expect(error == .emptyChildName)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("empty or missed search returns empty text")
    func emptySearchReturnsEmptyText() async throws {
        try await Job().run("topic") { session in
            await session.ingest(JobRecord(kind: "note", text: "alpha body"))
            let emptyQuery = await session.window(query: "", tokenLimit: 100)
            let miss = await session.window(query: "zzz", tokenLimit: 100)
            #expect(emptyQuery == "")
            #expect(miss == "")
        }
    }

    @Test("one child failure cancels siblings")
    func childFailureCancelsSiblings() async {
        let failing = FailingAgentRuntime()
        let delayed = MockAgentRuntime(response: "late", delay: .seconds(2))

        do {
            _ = try await Job().run("topic") { session in
                try await session.fanOut([
                    JobChild(name: "slow", agent: delayed, brief: "wait"),
                    JobChild(name: "boom", agent: failing, brief: "fail"),
                ])
            }
            Issue.record("expected child failure")
        } catch let error as AgentError {
            #expect(error == .generationFailed(reason: "child failed"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("results are sorted by name even if completion order differs")
    func resultsSortedByNameDespiteCompletionOrder() async throws {
        let beta = MockAgentRuntime(response: "b", delay: .zero)
        let alpha = MockAgentRuntime(response: "a", delay: .milliseconds(40))

        let results = try await Job().run("topic") { session in
            try await session.fanOut([
                JobChild(name: "beta", agent: beta, brief: "b"),
                JobChild(name: "alpha", agent: alpha, brief: "a"),
            ])
        }

        #expect(results.map(\.name) == ["alpha", "beta"])
        #expect(results.map(\.result.output) == ["a", "b"])
    }

    @Test("custom JobStore is used")
    func customStoreIsUsed() async throws {
        let store = RecordingJobStore()
        try await Job(store: store).run("topic") { session in
            await session.ingest(JobRecord(kind: "note", text: "hello"))
            let notes = await session.records(kind: "note")
            #expect(notes == [JobRecord(kind: "note", text: "hello")])
        }
        #expect(await store.ingested == [JobRecord(kind: "note", text: "hello")])
        #expect(await store.records() == [JobRecord(kind: "note", text: "hello")])
    }

    @Test("records-only store still truncates windows through JobSession")
    func recordsOnlyStoreTruncatesWindowsThroughSession() async throws {
        let store = RecordingJobStore()
        try await Job(store: store).run("topic") { session in
            await session.ingest(JobRecord(kind: "note", text: "alpha body"))
            await session.ingest(JobRecord(kind: "note", text: "beta body"))
            let truncated = await session.window(query: "alpha", tokenLimit: 1)
            let full = await session.window(query: "alpha", tokenLimit: 100)
            #expect(truncated == "note")
            #expect(full == "note: alpha body")
            #expect(full.contains("beta body") == false)
        }
        #expect(await store.records().map(\.text) == ["alpha body", "beta body"])
    }

    @Test("a later step sees the helper result list")
    func stepAfterFanOutSeesChildResults() async throws {
        let writer = MockAgentRuntime(response: "section")
        let outputs = try await Job().run("topic") { session in
            let children = try await session.fanOut([
                JobChild(name: "alpha", agent: writer, brief: "a"),
            ])
            return children.map(\.result.output)
        }
        #expect(outputs == ["section"])
    }

    @Test("second fan-out fails")
    func secondFanOutFails() async {
        let agent = MockAgentRuntime(response: "ok")
        do {
            _ = try await Job().run("topic") { session in
                _ = try await session.fanOut([
                    JobChild(name: "alpha", agent: agent, brief: "a"),
                ])
                return try await session.fanOut([
                    JobChild(name: "beta", agent: agent, brief: "b"),
                ])
            }
            Issue.record("expected fanOutAlreadyUsed")
        } catch let error as JobError {
            #expect(error == .fanOutAlreadyUsed)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("helper output is not auto-ingested")
    func helperOutputIsNotAutoIngested() async throws {
        let writer = MockAgentRuntime(response: "section")
        try await Job().run("topic") { session in
            await session.ingest(JobRecord(kind: "note", text: "alpha body"))
            _ = try await session.fanOut([
                JobChild(name: "alpha", agent: writer, brief: "a"),
            ])
            let notes = await session.records(kind: "note")
            #expect(notes == [JobRecord(kind: "note", text: "alpha body")])
            #expect(await session.records(kind: "section").isEmpty)
        }
    }
}

actor FailingAgentRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "fail"
    nonisolated let configuration: AgentConfiguration = .default

    func run(
        _: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) async throws -> AgentResult {
        throw AgentError.generationFailed(reason: "child failed")
    }

    nonisolated func stream(
        _: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.finish(throwing: AgentError.generationFailed(reason: "child failed"))
        }
    }

    func cancel() async {}
}

/// Records-only `JobStore`. No `window` — truncation lives on `JobSession`.
actor RecordingJobStore: JobStore {
    private(set) var ingested: [JobRecord] = []

    func ingest(_ record: JobRecord) async {
        ingested.append(record)
    }

    func records() async -> [JobRecord] {
        ingested
    }

    func records(kind: String) async -> [JobRecord] {
        ingested.filter { $0.kind == kind }
    }
}
