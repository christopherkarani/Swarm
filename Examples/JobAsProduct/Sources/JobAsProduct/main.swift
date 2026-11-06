// JobAsProduct — Swarm job-as-product demo.
//
// Demonstrates:
// - JobTask with an expected-output contract
// - Job.run(_:tasks:merge:) returning results keyed by task name
// - Manager delegation: a manager drafts briefs from notes, then one fan-out
// - Observer forwarding into helper runs
//
// Usage:
//   swift run JobAsProduct
//
// Deterministic: scripted stub agents, no API keys.

import Foundation
import Swarm

@main
struct JobAsProductMain {
    static func main() async {
        do {
            // Direct tasks: briefs are written up front.
            let product = try await Job().run(
                "Write an essay about rivers",
                tasks: [
                    JobTask(
                        name: "alpha",
                        agent: StubAgent(response: "Rivers begin as mountain streams."),
                        brief: "Write the opening paragraph.",
                        expectedOutput: "one paragraph"
                    ),
                    JobTask(
                        name: "beta",
                        agent: StubAgent(response: "They meet the sea at wide deltas."),
                        brief: "Write the closing paragraph.",
                        expectedOutput: "one paragraph"
                    ),
                ],
                merge: .indexed,
                observer: PrintObserver()
            )
            print("alpha: \(product.results["alpha"]?.output ?? "")")
            print("beta: \(product.results["beta"]?.output ?? "")")
            print("summary:\n\(product.summary)")

            // Manager delegation: the manager drafts briefs from shared notes.
            let delegated = try await Job().delegate(
                "Write the report",
                manager: StubAgent(response: "Cover the assigned section in one paragraph."),
                assignments: [
                    JobAssignment(
                        name: "alpha",
                        agent: StubAgent(response: "Rivers begin as mountain streams."),
                        notesQuery: "alpha",
                        expectedOutput: "one paragraph"
                    ),
                    JobAssignment(
                        name: "beta",
                        agent: StubAgent(response: "They meet the sea at wide deltas."),
                        notesQuery: "beta",
                        expectedOutput: "one paragraph"
                    ),
                ],
                merge: .indexed
            ) { session in
                await session.ingest(JobRecord(kind: "note", text: "alpha: source"))
                await session.ingest(JobRecord(kind: "note", text: "beta: mouth"))
            }
            print("delegated summary:\n\(delegated.summary)")
        } catch {
            fputs("JobAsProduct error: \(error)\n", stderr)
            exit(1)
        }
    }
}

/// Deterministic stub agent for the demo. No inference, no keys.
struct StubAgent: AgentRuntime {
    let response: String

    nonisolated var tools: [any AnyJSONTool] { [] }
    nonisolated var instructions: String { "Stub agent" }
    nonisolated var configuration: AgentConfiguration { .default }

    func run(
        _ input: String,
        session _: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
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
        let response = response
        return AsyncThrowingStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: response))))
            continuation.finish()
        }
    }

    func cancel() async {}
}

struct PrintObserver: AgentObserver {
    func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input: String) async {
        print("[start] \(input.prefix(60))")
    }

    func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async {
        print("[end] \(result.output.prefix(60))")
    }
}
