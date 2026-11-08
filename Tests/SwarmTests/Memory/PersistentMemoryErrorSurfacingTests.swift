// PersistentMemoryErrorSurfacingTests.swift
// SwarmTests
//
// Backend failures in PersistentMemory must be observable, not just logged.

import Foundation
@testable import Swarm
import Testing

@Suite("PersistentMemory Error Surfacing")
struct PersistentMemoryErrorSurfacingTests {
    @Test("A failed add is recorded in lastFailure")
    func failedAddIsRecorded() async {
        let backend = FailingPersistentBackend()
        let memory = PersistentMemory(backend: backend, conversationId: "broken")

        await memory.add(.user("lost"))

        let failure = await memory.lastFailure
        #expect(failure?.operation == .store)
        #expect(failure?.message.contains("disk unavailable") == true)
    }

    @Test("count and isEmpty record failures instead of silently reporting empty")
    func countAndIsEmptyRecordFailures() async {
        let backend = FailingPersistentBackend()
        let memory = PersistentMemory(backend: backend, conversationId: "broken")

        #expect(await memory.count == 0)
        #expect(await memory.lastFailure?.operation == .count)

        let fresh = PersistentMemory(backend: backend, conversationId: "broken")
        #expect(await fresh.isEmpty == true)
        #expect(await fresh.lastFailure?.operation == .count)
    }

    @Test("Throwing variants propagate backend errors")
    func throwingVariantsPropagate() async {
        let backend = FailingPersistentBackend()
        let memory = PersistentMemory(backend: backend, conversationId: "broken")

        await #expect(throws: FailingPersistentBackend.Failure.self) {
            try await memory.store(.user("x"))
        }
        await #expect(throws: FailingPersistentBackend.Failure.self) {
            try await memory.storeAll([.user("x")])
        }
        await #expect(throws: FailingPersistentBackend.Failure.self) {
            _ = try await memory.messageCount()
        }
        await #expect(throws: FailingPersistentBackend.Failure.self) {
            _ = try await memory.fetchMessages()
        }
        await #expect(throws: FailingPersistentBackend.Failure.self) {
            try await memory.deleteMessages()
        }
    }

    @Test("A later success does not hide an earlier failure")
    func failureStaysUntilCleared() async throws {
        let backend = FailingPersistentBackend()
        let memory = PersistentMemory(backend: backend, conversationId: "flaky")

        await memory.add(.user("lost"))
        #expect(await memory.lastFailure?.operation == .store)

        await backend.setFailing(false)
        await memory.add(.user("kept"))
        _ = await memory.allMessages()
        #expect(await memory.lastFailure?.operation == .store)
        #expect(try await memory.messageCount() == 1)

        await memory.clearLastFailure()
        #expect(await memory.lastFailure == nil)
    }

    @Test("Healthy backends never record failures")
    func healthyBackendHasNoFailure() async throws {
        let memory = PersistentMemory(backend: InMemoryBackend(), conversationId: "ok")
        await memory.add(.user("a"))
        try await memory.store(.assistant("b"))
        #expect(await memory.count == 2)
        #expect(await memory.lastFailure == nil)
    }
}

/// Backend whose operations throw while `failing` is true, delegating to an
/// in-memory store otherwise.
private actor FailingPersistentBackend: PersistentMemoryBackend {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "disk unavailable" }
    }

    private var failing = true
    private let store = InMemoryBackend()

    func setFailing(_ value: Bool) {
        failing = value
    }

    private func check() throws {
        if failing { throw Failure() }
    }

    func store(_ message: MemoryMessage, conversationId: String) async throws {
        try check()
        try await store.store(message, conversationId: conversationId)
    }

    func fetchMessages(conversationId: String) async throws -> [MemoryMessage] {
        try check()
        return try await store.fetchMessages(conversationId: conversationId)
    }

    func fetchRecentMessages(conversationId: String, limit: Int) async throws -> [MemoryMessage] {
        try check()
        return try await store.fetchRecentMessages(conversationId: conversationId, limit: limit)
    }

    func deleteMessages(conversationId: String) async throws {
        try check()
        try await store.deleteMessages(conversationId: conversationId)
    }

    func messageCount(conversationId: String) async throws -> Int {
        try check()
        return try await store.messageCount(conversationId: conversationId)
    }

    func allConversationIds() async throws -> [String] {
        try check()
        return try await store.allConversationIds()
    }
}
