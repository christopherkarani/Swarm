// VoiceSentenceBufferTests.swift
// SwarmTests
//
// Pure sentence-split tests for VoiceSentenceBuffer.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Sentence Buffer", .ephemeralDefaultStores)
struct VoiceSentenceBufferTests {
    @Test("append Hello world. emits one sentence")
    func appendHelloWorldEmitsSentence() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hello world.") == ["Hello world."])
    }

    @Test("append Hi. holds until flush")
    func appendHiHoldsUntilFlush() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hi.").isEmpty)
        #expect(buffer.flush() == "Hi.")
    }

    @Test("whitespace-only flush returns nil")
    func whitespaceOnlyFlushReturnsNil() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("   \n").isEmpty)
        #expect(buffer.flush() == nil)
    }

    @Test("two short sentences stay held then flush together")
    func twoShortSentencesFlushTogether() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hi. Yo.").isEmpty)
        #expect(buffer.flush() == "Hi. Yo.")
    }

    @Test("short prefix does not block a later speakable sentence")
    func shortPrefixScansPastToLaterTerminator() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hi. Hello world, speak now.") == ["Hi. Hello world, speak now."])
    }

    @Test("short prefix accumulates across appends")
    func shortPrefixAccumulatesAcrossAppends() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hi.").isEmpty)
        #expect(buffer.append(" Hello world, speak now.") == ["Hi. Hello world, speak now."])
    }

    @Test("short prefix joins the first sentence and later sentences still split")
    func shortPrefixJoinsFirstSentenceOnly() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hi. Hello world. Bye now friend.") == [
            "Hi. Hello world.",
            " Bye now friend.",
        ])
    }

    @Test("combined span at exactly the minimum emits")
    func combinedSpanAtMinimumEmits() {
        var buffer = VoiceSentenceBuffer()
        // "Hi. Bye." is 8 characters, exactly minSpeakCharacters: the short
        // prefix no longer blocks, so the combined span emits at once.
        #expect(buffer.append("Hi. Bye.") == ["Hi. Bye."])
        #expect(buffer.flush() == nil)
    }

    @Test("chunk with two long sentences emits both")
    func twoLongSentencesEmitSeparately() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hello world. Bye now friend.") == [
            "Hello world.",
            " Bye now friend.",
        ])
    }

    @Test("flush after tokens without terminator emits remainder")
    func flushRemainderWithoutTerminator() {
        var buffer = VoiceSentenceBuffer()
        #expect(buffer.append("Hello ").isEmpty)
        #expect(buffer.flush() == "Hello ")
    }
}
