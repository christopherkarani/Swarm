// VoiceSessionStreamingTests.swift
// SwarmTests
//
// Streaming TTS paths through VoiceSession.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Session Streaming", .ephemeralDefaultStores, .timeLimit(.minutes(1)))
struct VoiceSessionStreamingTests {
    @Test("streaming adapters emit audio chunks between speaking events")
    func streamingEmitsAudioChunks() async throws {
        let chunkOne = Data("audio-one".utf8)
        let chunkTwo = Data("audio-two".utf8)
        let speechToText = MockSpeechToText(
            transcripts: [SpeechTranscript(text: "hello", isFinal: true)]
        )
        let textToSpeech = MockStreamingTextToSpeech(chunks: [[chunkOne, chunkTwo]])
        let agent = MockAgentRuntime(streamTokenRuns: [["Hello world."]])
        let voice = VoiceSession(
            agent: agent,
            speechToText: speechToText,
            textToSpeech: textToSpeech
        )
        let collector = VoiceEventCollector()
        await collector.attach(to: voice)

        let turn = try await voice.listenAndRespond()
        let events = await collector.waitUntil { $0.contains(.speakingFinished("Hello world.")) }

        #expect(turn.transcript == "hello")
        #expect(turn.spokenUtterances == ["Hello world."])
        #expect(events.contains(.speaking("Hello world.")))
        #expect(events.contains(.audioChunk(utterance: "Hello world.", data: chunkOne)))
        #expect(events.contains(.audioChunk(utterance: "Hello world.", data: chunkTwo)))
        let chunkEvents = events.filter {
            if case .audioChunk = $0 { return true }
            return false
        }
        #expect(chunkEvents == [
            .audioChunk(utterance: "Hello world.", data: chunkOne),
            .audioChunk(utterance: "Hello world.", data: chunkTwo),
        ])
        await collector.cancel()
    }

    @Test("whole-utterance adapters emit no audio chunks")
    func nonStreamingEmitsNoChunks() async throws {
        let speechToText = MockSpeechToText(
            transcripts: [SpeechTranscript(text: "hello", isFinal: true)]
        )
        let textToSpeech = MockTextToSpeech()
        let agent = MockAgentRuntime(streamTokenRuns: [["Hello world."]])
        let voice = VoiceSession(
            agent: agent,
            speechToText: speechToText,
            textToSpeech: textToSpeech
        )
        let collector = VoiceEventCollector()
        await collector.attach(to: voice)

        let turn = try await voice.listenAndRespond()
        let events = await collector.waitUntil { $0.contains(.speakingFinished("Hello world.")) }

        #expect(turn.spokenUtterances == ["Hello world."])
        #expect(events.contains { if case .audioChunk = $0 { return true }; return false } == false)
        await collector.cancel()
    }

    @Test("barge-in during streaming starts a replacement listen")
    func bargeInDuringStreamingReplacesTurn() async throws {
        let speechToText = MockSpeechToText(
            transcripts: [SpeechTranscript(text: "hello", isFinal: true)],
            subsequentStarts: [[SpeechTranscript(text: "never mind", isFinal: true)]]
        )
        let textToSpeech = MockStreamingTextToSpeech(hangUntilStopped: true)
        let agent = MockAgentRuntime(streamTokenRuns: [
            ["Hello world."],
            ["Okay then."],
        ])
        let detector = MockVoiceActivityDetector()
        var configuration = VoiceSessionConfiguration.default
        configuration.bargeInEnabled = true
        let voice = VoiceSession(
            agent: agent,
            speechToText: speechToText,
            textToSpeech: textToSpeech,
            voiceActivityDetector: detector,
            configuration: configuration
        )
        let collector = VoiceEventCollector()
        await collector.attach(to: voice)

        let turnTask = Task {
            try await voice.listenAndRespond()
        }
        _ = await collector.waitUntil { events in
            events.contains { event in
                if case .speaking = event { return true }
                return false
            }
        }
        await detector.triggerSpeechStarted()

        let turn = try await turnTask.value
        let events = await collector.waitUntil { snapshot in
            snapshot.contains(.interrupted(transcriptSoFar: ""))
                && snapshot.contains(.finalTranscript("never mind"))
                && snapshot.contains(.speakingFinished("Okay then."))
        }

        #expect(turn.transcript == "never mind")
        #expect(turn.spokenUtterances.contains("Okay then."))
        #expect(events.contains(.interrupted(transcriptSoFar: "")))
        await collector.cancel()
    }
}

private actor VoiceEventCollector {
    private var events: [VoiceEvent] = []
    private var waiters: [Waiter] = []
    private var pump: Task<Void, Never>?

    private struct Waiter {
        let predicate: @Sendable ([VoiceEvent]) -> Bool
        let continuation: CheckedContinuation<[VoiceEvent], Never>
    }

    func attach(to voice: VoiceSession) async {
        let stream = voice.events
        pump = Task {
            for await event in stream {
                self.append(event)
            }
        }
        await Task.yield()
    }

    func append(_ event: VoiceEvent) {
        events.append(event)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            if waiter.predicate(events) {
                waiter.continuation.resume(returning: events)
            } else {
                waiters.append(waiter)
            }
        }
    }

    func waitUntil(_ predicate: @escaping @Sendable ([VoiceEvent]) -> Bool) async -> [VoiceEvent] {
        if predicate(events) {
            return events
        }
        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(predicate: predicate, continuation: continuation))
        }
    }

    func cancel() {
        pump?.cancel()
        pump = nil
    }
}
