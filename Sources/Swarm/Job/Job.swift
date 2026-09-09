import Foundation

/// One helper in a job fan-out.
///
/// You pick the name and write the brief. Swarm does not stuff leftover
/// notes into the helper.
public struct JobChild: Sendable {
    public let name: String
    public let agent: any AgentRuntime
    public let brief: String

    public init(name: String, agent: some AgentRuntime, brief: String) {
        self.name = name
        self.agent = agent
        self.brief = brief
    }
}

/// One helper's result after fan-out.
public struct JobChildResult: Sendable, Equatable {
    public let name: String
    public let result: AgentResult

    public init(name: String, result: AgentResult) {
        self.name = name
        self.result = result
    }
}

/// Shared-notes job with one fan-out of helpers.
///
/// `Workflow` is the last-answer chain: each agent gets the previous agent's
/// output. `Job` is the other tool: a notes box, sequential app code, then N
/// helpers whose count you may only know after an earlier step. Each helper
/// gets a brief you write.
///
/// ## Example
///
/// ```swift
/// let sections = try await Job().run("Write an essay about rivers") { session in
///     await session.ingest(JobRecord(kind: "note", text: "alpha: source"))
///     await session.ingest(JobRecord(kind: "note", text: "beta: mouth"))
///     let alpha = await session.window(query: "alpha", tokenLimit: 400)
///     let beta = await session.window(query: "beta", tokenLimit: 400)
///     return try await session.fanOut([
///         JobChild(name: "alpha", agent: writerA, brief: alpha),
///         JobChild(name: "beta", agent: writerB, brief: beta),
///     ])
/// }
/// ```
///
/// v1 is in-process. A crash means start over. One fan-out per ``run(_:body:)``.
/// Reusing the same `Job` (or store) shares the notes box across runs.
public struct Job: Sendable {
    private let store: any JobStore

    public init(store: any JobStore = InMemoryJobStore()) {
        self.store = store
    }

    /// Run app-owned steps against this job's notes box.
    public func run<Output: Sendable>(
        _ input: String,
        body: @Sendable (JobSession) async throws -> Output
    ) async throws -> Output {
        try await body(JobSession(input: input, store: store))
    }
}

/// Handle for one `Job.run` body: notes plus a single fan-out.
public struct JobSession: Sendable {
    /// Starting text passed to ``Job/run(_:body:)``.
    public let input: String

    private let store: any JobStore
    private let fanOutGate: JobFanOutGate

    init(input: String, store: any JobStore) {
        self.input = input
        self.store = store
        self.fanOutGate = JobFanOutGate()
    }

    /// Append a note to this job's store.
    public func ingest(_ record: JobRecord) async {
        await store.ingest(record)
    }

    /// Search phrase plus size limit over this job's notes.
    ///
    /// Matching is a case-insensitive substring of ``JobRecord/kind`` or
    /// ``JobRecord/text``, in ingest order. Empty or whitespace-only query,
    /// no matches, and `tokenLimit <= 0` return `""`, not an error. Size is
    /// measured with ``CharacterBasedTokenEstimator`` (~4 characters per
    /// token). Stores do not implement this; the session always renders from
    /// ``JobStore/records()``.
    public func window(query: String, tokenLimit: Int) async -> String {
        JobNotesWindow.render(
            records: await store.records(),
            query: query,
            tokenLimit: tokenLimit
        )
    }

    /// Exact `kind` match, ingest order. Unlike ``window(query:tokenLimit:)``,
    /// this does not substring-search or ignore case.
    public func records(kind: String) async -> [JobRecord] {
        await store.records(kind: kind)
    }

    /// Run helpers concurrently. Returns results sorted by trimmed child name.
    ///
    /// Empty list, empty names, and duplicate names fail before any helper
    /// runs and do not consume the one fan-out. A second call fails with
    /// ``JobError/fanOutAlreadyUsed``. Helper output is not written into the
    /// notes box.
    public func fanOut(_ children: [JobChild]) async throws -> [JobChildResult] {
        let prepared = try JobFanOutPreparation.prepare(children)
        try await fanOutGate.claim()

        let completed = try await withThrowingTaskGroup(
            of: (String, AgentResult).self,
            returning: [(String, AgentResult)].self
        ) { group in
            for item in prepared {
                group.addTask {
                    let result = try await item.child.agent.run(
                        item.child.brief,
                        session: nil,
                        observer: nil
                    )
                    return (item.name, result)
                }
            }

            var collected: [(String, AgentResult)] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        return completed
            .sorted { $0.0 < $1.0 }
            .map { JobChildResult(name: $0.0, result: $0.1) }
    }
}

fileprivate actor JobFanOutGate {
    private var used = false

    func claim() throws {
        if used {
            throw JobError.fanOutAlreadyUsed
        }
        used = true
    }
}
