# Job as Product

`Job` runs helpers that each get their own brief. The job-as-product
surface turns that fan-out into a usable product: tasks with an
expected-output contract, results keyed by task name, a merged summary,
observer forwarding, and a manager-delegation recipe.

## Tasks and the expected-output contract

A `JobTask` is a name, a helper agent, a brief, and an expected-output
contract — a short description of the shape the helper should return.
The contract is appended to the brief the helper receives.

```swift
let product = try await Job().run(
    "Write an essay about rivers",
    tasks: [
        JobTask(name: "alpha", agent: writerA, brief: alpha, expectedOutput: "one paragraph"),
        JobTask(name: "beta", agent: writerB, brief: beta, expectedOutput: "one paragraph"),
    ],
    merge: .indexed
)
```

`product.results` is keyed by trimmed task name:

```swift
product.results["alpha"]?.output  // "…"
```

`product.summary` merges every helper output with the `Workflow.MergeStrategy`
you pass. Unlike `Workflow.parallel`, every helper runs to completion first,
so `.firstCompleted` returns the first result by task name rather than racing.

Name validation (empty list, empty names, duplicate names) fails before any
helper runs and does not consume the one fan-out.

## Observing helpers

`fanOut` and both product conveniences accept an optional `AgentObserver`
that is forwarded to every child `agent.run` call:

```swift
let product = try await Job().run(
    "Write an essay about rivers",
    tasks: tasks,
    merge: .indexed,
    observer: loggingObserver
)
```

## Manager delegation

`Job.delegate` is the manager-delegation recipe: a manager agent drafts one
brief per assignment from the shared notes, then a single fan-out runs every
helper. The `prepare` closure ingests notes first.

```swift
let product = try await Job().delegate(
    "Write the report",
    manager: leadAgent,
    assignments: [
        JobAssignment(name: "alpha", agent: writerA, notesQuery: "alpha"),
        JobAssignment(name: "beta", agent: writerB, notesQuery: "beta"),
    ]
) { session in
    await session.ingest(JobRecord(kind: "note", text: "alpha: source"))
    await session.ingest(JobRecord(kind: "note", text: "beta: mouth"))
}
```

Assignment names are validated before the manager drafts anything. The
manager drafts sequentially (one `run` per assignment); the helpers then run
concurrently in one fan-out.

## One fan-out, multi-round via a shared store

The one-fan-out gate still holds: each `Job.run` (including `delegate`)
fans out at most once. For multi-round work, reuse the same `Job` or store
so rounds share the notes box, and decide each round's N after seeing the
previous round's product instead of looping fan-outs inside one run:

```swift
let job = Job()  // shared notes box across rounds
let round1 = try await job.run("Draft", tasks: firstTasks)
let round2 = try await job.run("Revise", tasks: tasksDecidedFrom(round1))
```

See the [front-facing API](/reference/front-facing-api#7b-job) for the full
`Job` surface.
