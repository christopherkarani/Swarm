#if SWARM_INTEGRATIONS && canImport(Membrane)
import Foundation
import Membrane
import MembraneCore
@testable import Swarm
import Testing

@Suite("Membrane backend injection")
struct MembraneBackendInjectionTests {
    @Test("session uses the injected backend")
    func sessionUsesInjectedBackend() async throws {
        let stub = StubMembraneBackend(prompt: "stub-prompt")
        let session = Membrane.MembraneSession(backend: stub)
        let prepared = try await session.prepare(
            ContextRequest(basePrompt: "hello", userInput: "hello")
        )

        #expect(prepared.plan.prompt == "stub-prompt")
        #expect(await stub.prepareCalls == 1)
        let snapshot = try await session.snapshot()
        #expect(snapshot?.backendID == "stub")
    }

    @Test("nil backend defaults to the portable passthrough")
    func nilBackendDefaultsToPassthrough() async throws {
        let session = Membrane.MembraneSession()
        let prepared = try await session.prepare(
            ContextRequest(basePrompt: "hello", userInput: "hello")
        )

        #expect(prepared.plan.prompt == "hello")
        let snapshot = try await session.snapshot()
        #expect(snapshot?.backendID == "passthrough")
    }

    @Test("default backend keeps its identity across pointerization")
    func defaultBackendSurvivesPointerization() async throws {
        let session = Membrane.MembraneSession()
        _ = try await session.prepare(
            ContextRequest(basePrompt: "hello", userInput: "hello")
        )
        let decision = try await session.transformToolResult(
            toolName: "alpha",
            output: String(repeating: "x", count: 2000)
        )

        guard case let .pointer(pointer, _) = decision else {
            Issue.record("expected large output to pointerize")
            return
        }
        let snapshot = try await session.snapshot()
        #expect(snapshot?.backendID == "passthrough")
        #expect(snapshot?.pointerIDs.contains(pointer.id) == true)
    }

    @Test("contextCoreSession injects the ContextCore backend")
    func contextCoreSessionUsesContextCoreBackend() async throws {
        let environment = MembraneEnvironment.contextCoreSession()
        let adapter = try #require(environment.adapter)
        _ = try await adapter.plan(
            prompt: "hello",
            toolSchemas: [ToolSchema(name: "alpha", description: "alpha", parameters: [])],
            profile: .balanced
        )

        let data = try #require(try await adapter.snapshotCheckpointData())
        let snapshot = try JSONDecoder().decode(ContextSnapshot.self, from: data)
        #expect(snapshot.backendID == "contextcore")
    }
}

private actor StubMembraneBackend: MembraneContextBackend {
    let backendID = "stub"
    let prompt: String
    private(set) var prepareCalls = 0
    private var lastSnapshot: ContextSnapshot?

    init(prompt: String) {
        self.prompt = prompt
    }

    func prepare(
        request: ContextRequest,
        budget: MembraneCore.ContextBudget,
        snapshot: ContextSnapshot?
    ) async throws -> MembraneBackendPreparation {
        prepareCalls += 1
        let backendSnapshot = ContextSnapshot(
            budget: snapshot?.budget ?? .init(totalTokens: budget.totalTokens),
            toolState: snapshot?.toolState ?? .init(
                mode: .allowAll,
                loadedToolNames: [],
                allowListToolNames: [],
                usageCounts: []
            ),
            pointerIDs: snapshot?.pointerIDs ?? [],
            backendID: backendID,
            backendState: nil
        ).normalized()
        lastSnapshot = backendSnapshot
        return MembraneBackendPreparation(
            plan: ContextPlan(
                prompt: prompt,
                systemPrompt: request.systemPrompt,
                toolPlan: request.toolPlan,
                budget: budget,
                metadata: request.metadata
            ),
            snapshot: backendSnapshot
        )
    }

    func restore(snapshot: ContextSnapshot?) async throws {
        lastSnapshot = snapshot?.normalized()
    }

    func snapshot() async throws -> ContextSnapshot? {
        lastSnapshot
    }
}
#endif
