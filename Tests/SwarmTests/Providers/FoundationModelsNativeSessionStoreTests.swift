// FoundationModelsNativeSessionStoreTests.swift
//
// Store-actor re-entry and identity-safe discard — no live Apple required.

import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels

@Suite("FoundationModels Native Session Store")
struct FoundationModelsNativeSessionStoreTests {
    @Test("Nested begin does not replace an owned session; child discard leaves parent")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func nestedBeginDoesNotReplaceOwnedSession() async {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let store = FoundationModelsNativeSessionStore()
        let identity = FoundationModelsNativeSessionIdentity(
            conversationID: "parent-conv",
            instructions: "Be helpful.",
            toolNames: []
        )

        let parent = await store.tryBeginOwnedLoop(matching: identity) {
            LanguageModelSession()
        } recreate: { _ in
            LanguageModelSession()
        }
        #expect(parent.lease.isOwned)
        #expect(!parent.reusedTranscript)
        #expect(await store.isOwnedLoopActive())
        #expect(await store.isStored(parent.session))

        let child = await store.tryBeginOwnedLoop(matching: identity) {
            LanguageModelSession()
        } recreate: { _ in
            LanguageModelSession()
        }
        #expect(!child.lease.isOwned)
        #expect(!child.reusedTranscript)
        #expect(child.session !== parent.session)
        #expect(await store.isStored(parent.session))
        #expect(!(await store.isStored(child.session)))
        #expect(await store.isOwnedLoopActive())

        await store.discard(child.lease)
        #expect(await store.isStored(parent.session))
        #expect(await store.hasStoredSession())
        #expect(await store.isOwnedLoopActive())

        await store.discard(parent.lease)
        #expect(!(await store.hasStoredSession()))
        #expect(!(await store.isOwnedLoopActive()))
        #expect(!(await store.isStored(parent.session)))
        #endif
    }

    @Test("Stale discard after endOwnedLoop does not nil the stored parent")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func staleDiscardAfterEndDoesNotClearStoredSession() async {
        #if os(tvOS) || os(watchOS)
        return
        #else
        let store = FoundationModelsNativeSessionStore()
        let identity = FoundationModelsNativeSessionIdentity(
            conversationID: "reuse-conv",
            instructions: "Be helpful.",
            toolNames: []
        )

        let first = await store.tryBeginOwnedLoop(matching: identity) {
            LanguageModelSession()
        } recreate: { _ in
            LanguageModelSession()
        }
        #expect(first.lease.isOwned)
        await store.endOwnedLoop(first.lease)
        #expect(!(await store.isOwnedLoopActive()))
        #expect(await store.isStored(first.session))

        await store.discard(first.lease)
        #expect(await store.isStored(first.session))
        #expect(await store.hasStoredSession())

        let second = await store.tryBeginOwnedLoop(matching: identity) {
            LanguageModelSession()
        } recreate: { _ in
            LanguageModelSession()
        }
        #expect(second.lease.isOwned)
        #expect(second.reusedTranscript)
        #expect(await store.isStored(second.session))
        #expect(!(await store.isStored(first.session)))

        await store.discard(first.lease)
        #expect(await store.isStored(second.session))
        #endif
    }
}
#endif
