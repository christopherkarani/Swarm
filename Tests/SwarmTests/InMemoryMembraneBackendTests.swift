#if SWARM_INTEGRATIONS && canImport(MembraneCore)
import Foundation
import MembraneCore
import Testing

@Suite("In-memory membrane backend")
struct InMemoryMembraneBackendTests {
    @Test("backend identity is the portable in-memory ID")
    func backendIdentity() {
        let backend = InMemoryMembraneBackend()
        #expect(backend.backendID == MembraneBackendID.inMemory.rawValue)
        #expect(backend.backendID == "in-memory")
    }

    @Test("empty request passes the prompt through with a snapshot")
    func emptyRequestPassthrough() async throws {
        let backend = InMemoryMembraneBackend()
        let prepared = try await backend.prepare(
            request: ContextRequest(basePrompt: "hello", userInput: "hello"),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        #expect(prepared.plan.prompt == "hello")
        #expect(prepared.plan.systemPrompt == "")

        let snapshot = try #require(try await backend.snapshot())
        #expect(snapshot.backendID == "in-memory")
        #expect(snapshot.backendState != nil)
        #expect(await backend.storedSliceCount == 0)
        #expect(await backend.totalPrepares == 1)
    }

    @Test("memories fold into the prompt within budget")
    func memoriesFoldIntoPrompt() async throws {
        let backend = InMemoryMembraneBackend()
        let prepared = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "question",
                userInput: "question",
                memories: [
                    ContextSlice(content: "memory one", tokenCount: 10, importance: 0.9, source: .memory),
                    ContextSlice(content: "memory two", tokenCount: 10, importance: 0.5, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        #expect(prepared.plan.prompt.contains("question"))
        #expect(prepared.plan.prompt.contains("Relevant Context:"))
        #expect(prepared.plan.prompt.contains("memory one"))
        #expect(prepared.plan.prompt.contains("memory two"))
        #expect(await backend.storedSliceCount == 2)
    }

    @Test("higher-importance slices win a tight budget")
    func tightBudgetPrefersImportance() async throws {
        let backend = InMemoryMembraneBackend()
        let prepared = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "hi",
                userInput: "hi",
                memories: [
                    ContextSlice(content: "low priority", tokenCount: 90, importance: 0.1, source: .memory),
                    ContextSlice(content: "high priority", tokenCount: 90, importance: 0.9, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 100, profile: .foundationModels4K),
            snapshot: nil
        )
        #expect(prepared.plan.prompt.contains("high priority"))
        #expect(!prepared.plan.prompt.contains("low priority"))
    }

    @Test("starved budget returns the base prompt alone")
    func starvedBudgetReturnsBase() async throws {
        let backend = InMemoryMembraneBackend()
        let prepared = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "hi",
                userInput: "hi",
                memories: [
                    ContextSlice(content: "memory one", tokenCount: 10, importance: 0.9, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 1, profile: .foundationModels4K),
            snapshot: nil
        )
        #expect(prepared.plan.prompt == "hi")
    }

    @Test("slices persist across prepares on the same backend")
    func slicesPersistAcrossPrepares() async throws {
        let backend = InMemoryMembraneBackend()
        _ = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "first",
                userInput: "first",
                memories: [
                    ContextSlice(content: "sticky memory", tokenCount: 10, importance: 0.9, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        let second = try await backend.prepare(
            request: ContextRequest(basePrompt: "second", userInput: "second"),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        #expect(second.plan.prompt.contains("sticky memory"))
        #expect(await backend.totalPrepares == 2)
    }

    @Test("repeated slices collapse to one retained copy")
    func repeatedSlicesDeduplicate() async throws {
        let backend = InMemoryMembraneBackend()
        let request = ContextRequest(
            basePrompt: "q",
            userInput: "q",
            memories: [
                ContextSlice(content: "same memory", tokenCount: 10, importance: 0.9, source: .memory),
            ]
        )
        let budget = ContextBudget(totalTokens: 4096, profile: .foundationModels4K)
        _ = try await backend.prepare(request: request, budget: budget, snapshot: nil)
        _ = try await backend.prepare(request: request, budget: budget, snapshot: nil)
        #expect(await backend.storedSliceCount == 1)
    }

    @Test("snapshot restores state onto a fresh backend")
    func snapshotRestoreRoundTrip() async throws {
        let backend = InMemoryMembraneBackend()
        _ = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "q",
                userInput: "q",
                memories: [
                    ContextSlice(content: "restored memory", tokenCount: 10, importance: 0.9, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        let snapshot = try #require(try await backend.snapshot())

        let revived = InMemoryMembraneBackend()
        try await revived.restore(snapshot: snapshot)
        #expect(await revived.storedSliceCount == 1)
        #expect(await revived.totalPrepares == 1)
        #expect(try await revived.snapshot() == snapshot)

        let prepared = try await revived.prepare(
            request: ContextRequest(basePrompt: "next", userInput: "next"),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: snapshot
        )
        #expect(prepared.plan.prompt.contains("restored memory"))
    }

    @Test("restore with nil clears retained state")
    func restoreNilClears() async throws {
        let backend = InMemoryMembraneBackend()
        _ = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "q",
                userInput: "q",
                memories: [
                    ContextSlice(content: "memory one", tokenCount: 10, importance: 0.9, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        #expect(await backend.storedSliceCount == 1)
        try await backend.restore(snapshot: nil)
        #expect(await backend.storedSliceCount == 0)
        #expect(try await backend.snapshot() == nil)
    }

    @Test("corrupt backend state throws a typed error")
    func corruptStateThrows() async throws {
        let backend = InMemoryMembraneBackend()
        let bad = ContextSnapshot(
            budget: .init(totalTokens: 4096),
            toolState: .init(mode: .allowAll, loadedToolNames: [], allowListToolNames: [], usageCounts: []),
            backendID: "in-memory",
            backendState: Data("not-json".utf8)
        ).normalized()
        await #expect(throws: InMemoryMembraneBackendError.self) {
            try await backend.restore(snapshot: bad)
        }
    }

    @Test("unknown state version throws a typed error")
    func versionMismatchThrows() async throws {
        let backend = InMemoryMembraneBackend()
        _ = try await backend.prepare(
            request: ContextRequest(
                basePrompt: "q",
                userInput: "q",
                memories: [
                    ContextSlice(content: "memory one", tokenCount: 10, importance: 0.9, source: .memory),
                ]
            ),
            budget: ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
            snapshot: nil
        )
        let snapshot = try #require(try await backend.snapshot())
        let state = try #require(snapshot.backendState)
        var object = try #require(try JSONSerialization.jsonObject(with: state) as? [String: Any])
        object["version"] = 999
        let bumped = try JSONSerialization.data(withJSONObject: object)
        let future = ContextSnapshot(
            budget: snapshot.budget,
            toolState: snapshot.toolState,
            pointerIDs: snapshot.pointerIDs,
            backendID: snapshot.backendID,
            backendState: bumped
        ).normalized()
        await #expect(throws: InMemoryMembraneBackendError.snapshotVersionMismatch(expected: 1, found: 999)) {
            try await backend.restore(snapshot: future)
        }
    }

    @Test("retained slices respect capacity")
    func capacityBoundsSlices() async throws {
        let backend = InMemoryMembraneBackend(capacity: 2)
        let budget = ContextBudget(totalTokens: 4096, profile: .foundationModels4K)
        for index in 0..<5 {
            _ = try await backend.prepare(
                request: ContextRequest(
                    basePrompt: "q",
                    userInput: "q",
                    memories: [
                        ContextSlice(
                            content: "memory \(index)",
                            tokenCount: 10,
                            importance: 0.5,
                            source: .memory
                        ),
                    ]
                ),
                budget: budget,
                snapshot: nil
            )
        }
        #expect(await backend.storedSliceCount == 2)
    }
}
#endif
