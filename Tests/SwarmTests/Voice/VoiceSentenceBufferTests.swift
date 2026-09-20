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
        #expect(buffer.append("Hi. Bye.").isEmpty)
        #expect(buffer.flush() == "Hi. Bye.")
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
