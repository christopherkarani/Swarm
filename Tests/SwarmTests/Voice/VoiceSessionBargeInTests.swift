// VoiceSessionBargeInTests.swift
// SwarmTests
//
// Barge-in replaces the in-flight spoken turn.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Session Barge-In", .ephemeralDefaultStores, .timeLimit(.minutes(1)))
struct VoiceSessionBargeInTests {
    @Test("barge-in during speaking starts a replacement listen")
    func bargeInReplacesSpokenTurn() async throws {
        let speechToText = MockSpeechToText(
            transcripts: [SpeechTranscript(text: "hello", isFinal: true)],
            subsequentStarts: [[SpeechTranscript(text: "never mind", isFinal: true)]]
        )
        let textToSpeech = MockTextToSpeech(hangUntilStopped: true)
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
        #expect(events.contains(.finalTranscript("hello")))
        #expect(events.contains(.finalTranscript("never mind")))
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
