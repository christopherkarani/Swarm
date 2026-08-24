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

/// An enum with associated values used to exercise codec round-trips that
/// must not corrupt case payloads.
private enum AssociatedValueEnum: Codable, Equatable, Sendable {
    case count(Int)
    case label(String)
}

/// A Codable type whose `encode(to:)` always throws, forcing the codec's
/// description-string fallback; its synthesized decoder requires a field
/// the fallback cannot supply, so typed reads of the fallback return nil.
private struct UnencodableButDecodable: Codable, Sendable {
    let required: Int

    func encode(to encoder: any Encoder) throws {
        struct EncodingUnavailable: Error {}
        throw EncodingUnavailable()
    }
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

    @Test("store-level merge without overwrite restamps same-name ids below the local winner")
    func storeMergeDoesNotLetDifferentTypedSameNameStealProjection() {
        var local = ContextSlotStore()
        local.setValuePayload(ContextKey<Int>("user_id"), payload: .int(42))

        var incoming = ContextSlotStore()
        incoming.setValuePayload(ContextKey<String>("user_id"), payload: .string("parent-user"))

        local.mergeValueSlots(from: incoming, overwrite: false)

        #expect(local.projectedValues()["user_id"] == .int(42))
        #expect(local.valuePayload(for: ContextKey<Int>("user_id")) == .int(42))
        #expect(local.valuePayload(for: ContextKey<String>("user_id")) == .string("parent-user"))
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

    // MARK: - Codec Edge Cases

    @Test("enums with associated values round-trip without corrupting cases")
    func associatedValueEnumRoundTrips() async throws {
        let context = AgentContext(input: "test")

        await context.setTyped(ContextKey<AssociatedValueEnum>("en_count"), value: .count(5))
        await context.setTyped(ContextKey<AssociatedValueEnum>("en_label"), value: .label("x"))

        #expect(await context.getTyped(ContextKey<AssociatedValueEnum>("en_count")) == .count(5))
        #expect(await context.getTyped(ContextKey<AssociatedValueEnum>("en_label")) == .label("x"))
    }

    @Test("nested SendableValue containers round-trip")
    func nestedContainersRoundTrip() async throws {
        let context = AgentContext(input: "test")
        let nested: [String: SendableValue] = [
            "a": .array([.int(1), .string("s")]),
            "b": .bool(true),
        ]

        await context.setTyped(ContextKey<[String: SendableValue]>("nest"), value: nested)
        await context.setTyped(ContextKey<[SendableValue]>("arr"), value: [.double(1.5), .null])

        #expect(await context.getTyped(ContextKey<[String: SendableValue]>("nest")) == nested)
        #expect(await context.getTyped(ContextKey<[SendableValue]>("arr")) == [.double(1.5), .null])
    }

    @Test("optional none stores a null slot that reads back as absent")
    func optionalNoneSlotSemantics() async throws {
        let key = ContextKey<String?>("opt_none")
        let context = AgentContext(input: "test")

        await context.setTyped(key, value: nil)

        // The slot exists and projects a null payload; the typed read
        // succeeds decoding `null` as String?, yielding .some(.none).
        #expect(await context.hasTyped(key))
        #expect(await context.snapshot["opt_none"] == .null)
        let decoded = await context.valueSlotPayload(for: key)
        #expect(decoded == .null)
        // A present-optional write still round-trips exactly.
        let someKey = ContextKey<String?>("opt_some")
        await context.setTyped(someKey, value: "present")
        #expect(await context.getTyped(someKey) == "present")
    }

    @Test("unencodable value falls back to a description string that fails to decode")
    func unencodableFallsBackToInertStringPayload() async throws {
        let key = ContextKey<UnencodableButDecodable>("boom")
        let context = AgentContext(input: "test")

        await context.setTyped(key, value: UnencodableButDecodable(required: 7))

        // Write never throws (fallback stored); the payload is inert for
        // typed reads: has stays true, the read returns nil, nothing is
        // corrupted.
        #expect(await context.hasTyped(key))
        #expect(await context.getTyped(key) == nil)
        #expect(await context.snapshot["boom"]?.stringValue?.isEmpty == false)
    }

    @Test("whole-number doubles collapse to int payloads but read back exact")
    func wholeDoublePayloadCollapsesNumericallyLosslessly() async throws {
        let context = AgentContext(input: "test")

        await context.setTyped(ContextKey<Double>("whole"), value: 2.0)

        // JSON cannot distinguish 2 from 2.0, so the projected payload
        // decodes as an integer; the Double read remains numerically exact.
        let snap = try #require(await context.snapshot["whole"])
        guard case .int = snap else {
            Issue.record("expected integer-shaped payload for whole double, got \(snap)")
            return
        }
        #expect(await context.getTyped(ContextKey<Double>("whole")) == 2.0)
    }

    @Test("date keys stay exact at sub-second precision and far-future epochs")
    func dateExtremeValuesStayExact() async throws {
        let context = AgentContext(input: "test")
        let tiny = Date(timeIntervalSince1970: 0.000001)
        let far = Date(timeIntervalSince1970: 4_102_444_800)

        await context.setTyped(.timestamp, value: tiny)
        await context.setTyped(ContextKey<Date>("far_future"), value: far)

        #expect(await context.getTyped(.timestamp) == tiny)
        #expect(await context.getTyped(ContextKey<Date>("far_future")) == far)
    }

    @Test("merge without overwrite keeps raw entry in snapshot while merging the slot")
    func mergeWithoutOverwriteSeparatesRawEntryFromMergedSlot() async throws {
        let parent = AgentContext(input: "parent")
        await parent.setTyped(.userID, value: "from-slot")

        let child = AgentContext(input: "child")
        await child.set("user_id", value: .string("raw-local"))
        await child.merge(from: parent, overwrite: false)

        // Snapshot projection: existing raw entry wins.
        #expect(await child.snapshot["user_id"] == .string("raw-local"))
        // Typed namespace still received the merged slot.
        #expect(await child.getTyped(.userID) == "from-slot")
        #expect(await child.get("user_id") == .string("raw-local"))
    }

    @Test("merge of typed-only parent then removeTyped leaves no raw shadow")
    func mergeThenRemoveTypedDoesNotLeaveRawShadow() async throws {
        let parent = AgentContext(input: "parent")
        await parent.setTyped(.userID, value: "p-user")

        let child = AgentContext(input: "child")
        await child.merge(from: parent, overwrite: false)

        #expect(await child.getTyped(.userID) == "p-user")
        #expect(await child.snapshot["user_id"] == .string("p-user"))
        // Merge must not copy the projection into raw storage.
        #expect(await child.get("user_id") == nil)

        await child.removeTyped(.userID)
        #expect(await child.getTyped(.userID) == nil)
        #expect(await child.get("user_id") == nil)
        #expect(await child.snapshot["user_id"] == nil)
    }

    @Test("merge without overwrite keeps a local typed snapshot winner across value types")
    func mergeWithoutOverwriteKeepsLocalSameNameSnapshotWinner() async throws {
        let parent = AgentContext(input: "parent")
        await parent.setTyped(ContextKey<String>("user_id"), value: "parent-user")

        let child = AgentContext(input: "child")
        await child.setTyped(ContextKey<Int>("user_id"), value: 42)

        await child.merge(from: parent, overwrite: false)

        #expect(await child.getTyped(ContextKey<Int>("user_id")) == 42)
        #expect(await child.getTyped(ContextKey<String>("user_id")) == "parent-user")
        #expect(await child.snapshot["user_id"] == .int(42))

        await child.removeTyped(ContextKey<Int>("user_id"))
        #expect(await child.snapshot["user_id"] == .string("parent-user"))
    }
}
