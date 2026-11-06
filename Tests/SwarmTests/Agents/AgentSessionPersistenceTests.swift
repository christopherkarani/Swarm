import Foundation
@testable import Swarm
import Testing

@Suite("Agent session persistence", .ephemeralDefaultStores)
struct AgentSessionPersistenceTests {

    @Test("Persisting a turn does not re-read the whole session")
    func persistingTurnDoesNotReadWholeSession() async throws {
        let session = ReadRecordingSession()
        let agent = try Agent(
            "Answer briefly.",
            configuration: AgentConfiguration(name: "agent", defaultTracingEnabled: false),
            inferenceProvider: MockInferenceProvider(responses: ["first", "second"])
        )

        _ = try await agent.run("one", session: session)
        let result = try await agent.run("two", session: session)

        #expect(await session.unboundedReads == 0)

        let stored = try await session.storedItems()
        #expect(stored.count == 4)
        let turnTranscript = SwarmTranscript(memoryMessages: Array(stored.suffix(2)))
        #expect(result.metadata["swarm.transcript.schema_version"]?.stringValue == turnTranscript.schemaVersion.rawValue)
        #expect(result.metadata["swarm.transcript.hash"]?.stringValue == (try turnTranscript.transcriptHash()))
    }
}

/// Session that counts unbounded `getItems(limit: nil)` reads.
private actor ReadRecordingSession: Session {
    nonisolated let sessionId = UUID().uuidString
    private let base = InMemorySession()
    private(set) var unboundedReads = 0

    var itemCount: Int {
        get async { await base.itemCount }
    }

    var isEmpty: Bool {
        get async { await base.isEmpty }
    }

    func getItemCount() async throws -> Int {
        try await base.getItemCount()
    }

    func getItems(limit: Int?) async throws -> [MemoryMessage] {
        if limit == nil {
            unboundedReads += 1
        }
        return try await base.getItems(limit: limit)
    }

    func addItems(_ items: [MemoryMessage]) async throws {
        try await base.addItems(items)
    }

    func popItem() async throws -> MemoryMessage? {
        try await base.popItem()
    }

    func clearSession() async throws {
        try await base.clearSession()
    }

    func storedItems() async throws -> [MemoryMessage] {
        try await base.getAllItems()
    }
}
