import Foundation

/// One unit of helper work in a job-as-product run.
///
/// You pick the name, the helper agent, and the brief. `expectedOutput` is
/// the output contract: a short description of the shape the helper should
/// return, such as `"one paragraph"` or `"JSON with keys title, body"`.
/// It is appended to the brief the helper receives.
public struct JobTask: Sendable {
    public let name: String
    public let agent: any AgentRuntime
    public let brief: String
    public let expectedOutput: String

    public init(
        name: String,
        agent: some AgentRuntime,
        brief: String,
        expectedOutput: String = ""
    ) {
        self.name = name
        self.agent = agent
        self.brief = brief
        self.expectedOutput = expectedOutput
    }

    /// The brief plus the expected-output contract, as the helper receives it.
    var resolvedBrief: String {
        let contract = expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contract.isEmpty else { return brief }
        return "\(brief)\n\nExpected output:\n\(contract)"
    }
}

/// The product of a job-as-product run: results keyed by task name plus a
/// merged summary.
///
/// `results` is keyed by trimmed task name. `summary` merges every helper
/// output with the ``Workflow/MergeStrategy`` you passed to
/// ``Job/run(_:tasks:merge:observer:)`` or ``Job/delegate(_:manager:assignments:merge:observer:tokenLimit:prepare:)``.
public struct JobProduct: Sendable, Equatable {
    /// Helper results keyed by trimmed task name.
    public let results: [String: AgentResult]

    /// Every helper output merged with the run's merge strategy.
    public let summary: String

    public init(results: [String: AgentResult], summary: String) {
        self.results = results
        self.summary = summary
    }
}

/// One delegation slot for ``Job/delegate(_:manager:assignments:merge:observer:tokenLimit:prepare:)``.
///
/// Like ``JobTask`` but without the brief: the manager drafts it from the
/// notes window for `notesQuery`, then one fan-out runs every helper.
public struct JobAssignment: Sendable {
    public let name: String
    public let agent: any AgentRuntime
    public let notesQuery: String
    public let expectedOutput: String

    public init(
        name: String,
        agent: some AgentRuntime,
        notesQuery: String,
        expectedOutput: String = ""
    ) {
        self.name = name
        self.agent = agent
        self.notesQuery = notesQuery
        self.expectedOutput = expectedOutput
    }
}

public extension Job {
    /// Run tasks concurrently and return results keyed by task name.
    ///
    /// Each task's brief plus its expected-output contract goes to its
    /// helper; results come back sorted by trimmed name for the summary and
    /// keyed by name in ``JobProduct/results``. The summary reuses
    /// ``Workflow/MergeStrategy``. Unlike `Workflow.parallel`, every helper
    /// runs to completion first, so `.firstCompleted` returns the first
    /// result by task name rather than racing.
    ///
    /// Name validation (empty, duplicate, empty list) fails before any
    /// helper runs and does not consume the one fan-out.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let product = try await Job().run(
    ///     "Write an essay about rivers",
    ///     tasks: [
    ///         JobTask(name: "alpha", agent: writerA, brief: alpha, expectedOutput: "one paragraph"),
    ///         JobTask(name: "beta", agent: writerB, brief: beta, expectedOutput: "one paragraph"),
    ///     ],
    ///     merge: .indexed
    /// )
    /// print(product.results["alpha"]?.output ?? "")
    /// print(product.summary)
    /// ```
    func run(
        _ input: String,
        tasks: [JobTask],
        merge: Workflow.MergeStrategy = .structured,
        observer: (any AgentObserver)? = nil
    ) async throws -> JobProduct {
        try await run(input) { session in
            try await executeJobTasks(tasks, on: session, merge: merge, observer: observer)
        }
    }

    /// Manager-delegation recipe: the manager drafts one brief per
    /// assignment from the shared notes, then a single fan-out runs every
    /// helper.
    ///
    /// Steps: `prepare` ingests notes (default: nothing), the manager drafts
    /// each brief sequentially from `window(query: notesQuery)`, then one
    /// `fanOut` runs every helper concurrently. Assignment names are
    /// validated before the manager drafts anything. The manager and every
    /// helper receive `observer`.
    ///
    /// The one-fan-out gate still holds: this is one fan-out per run. For
    /// multi-round work, reuse the same `Job` (or store) so rounds share the
    /// notes box, and decide each round's N after seeing the previous
    /// round's product instead of looping fan-outs inside one run.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let product = try await Job().delegate(
    ///     "Write the report",
    ///     manager: leadAgent,
    ///     assignments: [
    ///         JobAssignment(name: "alpha", agent: writerA, notesQuery: "alpha"),
    ///         JobAssignment(name: "beta", agent: writerB, notesQuery: "beta"),
    ///     ]
    /// ) { session in
    ///     await session.ingest(JobRecord(kind: "note", text: "alpha: source"))
    ///     await session.ingest(JobRecord(kind: "note", text: "beta: mouth"))
    /// }
    /// ```
    func delegate(
        _ input: String,
        manager: some AgentRuntime,
        assignments: [JobAssignment],
        merge: Workflow.MergeStrategy = .structured,
        observer: (any AgentObserver)? = nil,
        tokenLimit: Int = 4000,
        prepare: @Sendable (JobSession) async throws -> Void = { _ in }
    ) async throws -> JobProduct {
        _ = try JobFanOutPreparation.prepare(
            assignments.map { JobChild(name: $0.name, agent: $0.agent, brief: "") }
        )
        return try await run(input) { session in
            try await prepare(session)
            var tasks: [JobTask] = []
            for assignment in assignments {
                let window = await session.window(query: assignment.notesQuery, tokenLimit: tokenLimit)
                var prompt = "Draft a brief for helper \"\(assignment.name)\" from these notes:\n\(window)"
                let contract = assignment.expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !contract.isEmpty {
                    prompt += "\nExpected output: \(contract)"
                }
                let brief = try await manager.run(prompt, observer: observer).output
                tasks.append(JobTask(
                    name: assignment.name,
                    agent: assignment.agent,
                    brief: brief,
                    expectedOutput: assignment.expectedOutput
                ))
            }
            return try await executeJobTasks(tasks, on: session, merge: merge, observer: observer)
        }
    }
}

/// Map tasks to children, fan out once, and merge into a product.
///
/// Validation failures throw before the fan-out gate is claimed.
func executeJobTasks(
    _ tasks: [JobTask],
    on session: JobSession,
    merge: Workflow.MergeStrategy,
    observer: (any AgentObserver)?
) async throws -> JobProduct {
    let children = tasks.map {
        JobChild(name: $0.name, agent: $0.agent, brief: $0.resolvedBrief)
    }
    let childResults = try await session.fanOut(children, observer: observer)
    return JobProduct(
        results: Dictionary(uniqueKeysWithValues: childResults.map { ($0.name, $0.result) }),
        summary: merge.mergedOutput(from: childResults.map(\.result))
    )
}
