// ContextStoreUnificationTests.swift
// SwarmTests
//
// Tests for the unified phantom-typed AgentContext store: slot identity,
// round-trip exactness, namespace separation, snapshot/merge/copy behavior,
// and the deprecated AgentContextProviding shim.

import Foundation
import Testing
@testable import Swarm

// MARK: - Test Fixtures

/// A custom Codable value used to exercise complex typed slots.
private struct UserProfile: Codable, Equatable, Sendable {
    let id: String
    let score: Double
}

/// A deprecated-protocol conformer used to prove the shim still functions.
private struct LegacyUserContext: AgentContextProviding {
    static let contextKey = "legacy_user_context"

    let userId: String
    let isAdmin: Bool
}

/// A second deprecated-protocol conformer used to prove shim coexistence.
private struct LegacySessionContext: AgentContextProviding {
    static let contextKey = "legacy_session_context"

    let sessionId: String
}

// MARK: - ContextStoreUnificationTests

@Suite("Context Store Unification")
struct ContextStoreUnificationTests {
    // MARK: - Slot Identity

    @Test("same-name keys with different Value types occupy distinct slots")
    func sameNameDifferentValueTypesDoNotCollide() async throws {
        let stringKey = ContextKey<String>("shared_name")
        let intKey = ContextKey<Int>("shared_name")
        let context = AgentContext(input: "test")

        await context.setTyped(stringKey, value: "hello")
        await context.setTyped(intKey, value: 42)

        let stringValue = await context.getTyped(stringKey)
        let intValue = await context.getTyped(intKey)
        #expect(stringValue == "hello")
        #expect(intValue == 42)
    }

    @Test("overwriting one same-named key leaves the other untouched")
    func overwritingSameNamedKeyDoesNotLeak() async throws {
        let boolKey = ContextKey<Bool>("shared_name_2")
        let doubleKey = ContextKey<Double>("shared_name_2")
        let context = AgentContext(input: "test")

        await context.setTyped(boolKey, value: true)
        await context.setTyped(doubleKey, value: 1.5)
        await context.setTyped(boolKey, value: false)

        #expect(await context.getTyped(doubleKey) == 1.5)
        #expect(await context.getTyped(boolKey) == false)
    }

    // MARK: - Round-Trip Exactness

    @Test("typed round trip returns the exact stored value for standard keys")
    func typedRoundTripStandardKeys() async throws {
        let context = AgentContext(input: "test")

        let stamp = Date(timeIntervalSince1970: 1_793_200_000.123456)
        await context.setTyped(.userID, value: "user-123")
        await context.setTyped(.requestCount, value: 7)
        await context.setTyped(ContextKey<Double>("pi"), value: 3.14)
        await context.setTyped(.isAuthenticated, value: true)
        await context.setTyped(.tags, value: ["alpha", "beta"])
        await context.setTyped(.timestamp, value: stamp)
        await context.setTyped(
            ContextKey<UserProfile>("profile"),
            value: UserProfile(id: "u1", score: 99.5)
        )

        #expect(await context.getTyped(.userID) == "user-123")
        #expect(await context.getTyped(.requestCount) == 7)
        #expect(await context.getTyped(ContextKey<Double>("pi")) == 3.14)
        #expect(await context.getTyped(.isAuthenticated) == true)
        #expect(await context.getTyped(.tags) == ["alpha", "beta"])
        #expect(await context.getTyped(.timestamp) == stamp)
        #expect(
            await context.getTyped(ContextKey<UserProfile>("profile"))
                == UserProfile(id: "u1", score: 99.5)
        )
    }

    @Test("Date keys stored via timestamp doubles still decode")
    func dateFromTimestampPayloadDecodes() async throws {
        let context = AgentContext(input: "test")

        await context.setTyped(.expiresAt, value: Date(timeIntervalSince1970: 1_900_000_000))

        let decoded = await context.getTyped(.expiresAt)
        #expect(decoded == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test("getTyped default returns stored value or fallback")
    func getTypedWithDefault() async throws {
        let context = AgentContext(input: "test")

        let missing = await context.getTyped(.retryCount, default: 5)
        #expect(missing == 5)

        await context.setTyped(.retryCount, value: 2)
        let present = await context.getTyped(.retryCount, default: 5)
        #expect(present == 2)
    }

    @Test("removeTyped and hasTyped target only their own slot")
    func removeAndHasSemantics() async throws {
        let context = AgentContext(input: "test")
        await context.setTyped(.userID, value: "u-1")
        await context.setTyped(ContextKey<Int>("user_id"), value: 9)

        #expect(await context.hasTyped(.userID))
        await context.removeTyped(.userID)
        #expect(await context.hasTyped(.userID) == false)
        // Same name, different Value type keeps its own slot.
        #expect(await context.getTyped(ContextKey<Int>("user_id")) == 9)
        #expect(await context.getTyped(.userID) == nil)
    }

    // MARK: - Namespace Separation

    @Test("typed writes are not visible through untyped reads and vice versa")
    func typedAndRawNamespacesStaySeparate() async throws {
        let context = AgentContext(input: "test")

        await context.setTyped(.userID, value: "x")
        #expect(await context.get("user_id") == nil)

        // A raw write does not touch the typed slot.
        await context.set("user_id", value: .string("y"))
        #expect(await context.getTyped(.userID) == "x")
        #expect(await context.hasTyped(.userID))

        // Removing the typed slot leaves the raw entry intact.
        await context.removeTyped(.userID)
        #expect(await context.getTyped(.userID) == nil)
        #expect(await context.get("user_id") == .string("y"))

        // Raw entries keep flowing through the raw API.
        #expect(await context.get("user_id") == .string("y"))
    }

    // MARK: - Snapshot Behavior

    @Test("snapshot projects typed slots by name and preserves raw entries")
    func snapshotIncludesTypedSlotsAndRawEntries() async throws {
        let context = AgentContext(input: "hello", initialValues: ["branch": .string("main")])
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)

        await context.setTyped(.userID, value: "u-9")
        await context.setTyped(.depth, value: 3)
        await context.setTyped(.timestamp, value: stamp)

        let snap = await context.snapshot
        #expect(snap["branch"] == .string("main"))
        #expect(snap[AgentContextKey.originalInput.rawValue] == .string("hello"))
        #expect(snap["user_id"] == .string("u-9"))
        #expect(snap["depth"] == .int(3))

        let timestampPayload = try #require(snap["timestamp"])
        switch timestampPayload {
        case let .double(seconds):
            #expect(Date(timeIntervalSince1970: seconds) == stamp)
        case let .int(seconds):
            #expect(Date(timeIntervalSince1970: Double(seconds)) == stamp)
        default:
            Issue.record("Expected timestamp payload encoded as a number")
        }
    }

    @Test("raw entries win when a raw key collides with a projected slot name")
    func snapshotRawEntriesTakePrecedence() async throws {
        let context = AgentContext(input: "test")

        await context.setTyped(.sessionID, value: "from-typed-slot")
        await context.set("session_id", value: .string("from-raw"))

        let snap = await context.snapshot
        #expect(snap["session_id"] == .string("from-raw"))
    }

    @Test("allKeys includes typed slot names alongside raw keys")
    func allKeysIncludesSlotNames() async throws {
        let context = AgentContext(input: "test")
        await context.setTyped(.correlationID, value: "c-1")
        await context.set("plain", value: .int(1))

        let keys = Set(await context.allKeys)
        #expect(keys.contains("correlation_id"))
        #expect(keys.contains("plain"))
        #expect(keys.contains(AgentContextKey.originalInput.rawValue))
    }

    // MARK: - Merge Behavior

    @Test("merge carries typed values and respects overwrite flag")
    func mergeCarriesTypedValues() async throws {
        let parent = AgentContext(input: "parent")
        await parent.setTyped(.userID, value: "p-user")
        await parent.addMessage(MemoryMessage.user("hello"))

        let child = AgentContext(input: "child")
        await child.setTyped(.userID, value: "c-user")
        await child.setTyped(.depth, value: 1)

        await child.merge(from: parent, overwrite: false)
        #expect(await child.getTyped(.userID) == "c-user")
        #expect(await child.getTyped(.depth) == 1)

        await child.merge(from: parent, overwrite: true)
        #expect(await child.getTyped(.userID) == "p-user")

        let messages = await child.getMessages()
        #expect(messages.count == 1)
        #expect(messages.first?.content == "hello")
    }

    @Test("merge keeps execution path tracking intact")
    func mergePreservesExecutionPath() async throws {
        let parent = AgentContext(input: "parent")
        await parent.recordExecution(agentName: "Fetcher")

        let child = AgentContext(input: "child")
        await child.recordExecution(agentName: "Analyzer")
        await child.merge(from: parent)

        let path = await child.getExecutionPath()
        #expect(path.contains("Fetcher"))
        #expect(path.contains("Analyzer"))
    }

    @Test("merge does not displace a local typed slot with an incoming same-named value")
    func mergeKeepsLocalSlotWithoutOverwrite() async throws {
        let parent = AgentContext(input: "parent")
        await parent.setTyped(.userID, value: "parent-user")

        let child = AgentContext(input: "child")
        await child.setTyped(.userID, value: "child-user")

        await child.merge(from: parent, overwrite: false)
        #expect(await child.getTyped(.userID) == "child-user")
        // The projected payload must not shadow the live slot in snapshots.
        #expect(await child.snapshot["user_id"] == .string("child-user"))

        await child.merge(from: parent, overwrite: true)
        #expect(await child.getTyped(.userID) == "parent-user")
        #expect(await child.snapshot["user_id"] == .string("parent-user"))
    }

    @Test("merge keeps most-recent same-named slot winning across value types")
    func mergePreservesSameNamedRecencyAcrossValueTypes() async throws {
        let parent = AgentContext(input: "parent")
        await parent.setTyped(ContextKey<Int>("recency_name"), value: 1)
        await parent.setTyped(ContextKey<String>("recency_name"), value: "newest")

        let child = AgentContext(input: "child")
        await child.merge(from: parent)

        #expect(await child.snapshot["recency_name"] == .string("newest"))
        #expect(await child.getTyped(ContextKey<String>("recency_name")) == "newest")
        #expect(await child.getTyped(ContextKey<Int>("recency_name")) == 1)
    }

    @Test("store-level merge re-stamps incoming slots in source-recency order")
    func storeMergeRestampsInSourceRecencyOrder() {
        var source = ContextSlotStore()
        source.setValuePayload(ContextKey<Int>("recency_name"), payload: .int(1))
        source.setValuePayload(ContextKey<String>("recency_name"), payload: .string("newest"))

        var merged = ContextSlotStore()
        merged.mergeValueSlots(from: source, overwrite: false)

        #expect(merged.projectedValues()["recency_name"] == .string("newest"))
        #expect(merged.valuePayload(for: ContextKey<Int>("recency_name")) == .int(1))
        #expect(merged.valuePayload(for: ContextKey<String>("recency_name")) == .string("newest"))
    }

    // MARK: - Copy Behavior

    @Test("copy carries typed values and lands additionalValues in the raw namespace")
    func copyCarriesTypedValues() async throws {
        let source = AgentContext(input: "source")
        await source.setTyped(.userID, value: "copied-user")

        let branch = await source.copy(additionalValues: ["mode": .string("experimental")])

        #expect(await branch.getTyped(.userID) == "copied-user")
        #expect(await branch.get("mode") == .string("experimental"))
        #expect(await branch.originalInput == "source")

        // The copy is independent of its source.
        await branch.setTyped(.userID, value: "changed-in-copy")
        #expect(await source.getTyped(.userID) == "copied-user")
    }

    @Test("copy keeps most-recent same-named slot winning across value types")
    func copyPreservesSameNamedRecencyAcrossValueTypes() async throws {
        let context = AgentContext(input: "test")
        await context.setTyped(ContextKey<Int>("recency_name"), value: 1)
        await context.setTyped(ContextKey<String>("recency_name"), value: "newest")

        let branch = await context.copy()
        #expect(await branch.snapshot["recency_name"] == .string("newest"))
        #expect(await branch.getTyped(ContextKey<String>("recency_name")) == "newest")
        #expect(await branch.getTyped(ContextKey<Int>("recency_name")) == 1)
    }

    // MARK: - Deprecated AgentContextProviding Shim

    @Test("deprecated AgentContextProviding shim stores and retrieves instances")
    func providedShimStillFunctions() async throws {
        let context = AgentContext(input: "test")

        await context.setTyped(LegacyUserContext(userId: "u-42", isAdmin: true))
        let retrieved = await context.typed(LegacyUserContext.self)
        #expect(retrieved?.userId == "u-42")
        #expect(retrieved?.isAdmin == true)
    }

    @Test("deprecated shim supports has, overwrite, removal, and coexistence")
    func providedShimHasRemoveCoexist() async throws {
        let context = AgentContext(input: "test")

        #expect(await context.hasTyped(LegacyUserContext.self) == false)
        #expect(await context.removeTyped(LegacyUserContext.self) == nil)
        #expect(await context.typed(LegacyUserContext.self) == nil)

        await context.setTyped(LegacyUserContext(userId: "first", isAdmin: false))
        await context.setTyped(LegacyUserContext(userId: "second", isAdmin: true))
        let overwritten = await context.typed(LegacyUserContext.self)
        #expect(overwritten?.userId == "second")

        await context.setTyped(LegacySessionContext(sessionId: "s-1"))
        let user = await context.typed(LegacyUserContext.self)
        let session = await context.typed(LegacySessionContext.self)
        #expect(user?.userId == "second")
        #expect(session?.sessionId == "s-1")

        let removed = await context.removeTyped(LegacyUserContext.self)
        #expect(removed?.userId == "second")
        #expect(await context.hasTyped(LegacyUserContext.self) == false)
        #expect(await context.hasTyped(LegacySessionContext.self))
    }

    @Test("deprecated shim instances do not appear in snapshots")
    func providedShimStaysOutOfSnapshots() async throws {
        let context = AgentContext(input: "test")
        await context.setTyped(LegacyUserContext(userId: "u-1", isAdmin: false))

        let snap = await context.snapshot
        #expect(snap["legacy_user_context"] == nil)
    }
}
