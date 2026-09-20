// VoiceSessionTests.swift
// SwarmTests
//
// Behavioral tests for the turn-based VoiceSession coordinator.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Session", .ephemeralDefaultStores, .timeLimit(.minutes(1)))
struct VoiceSessionTests {
    @Test("listenAndRespond speaks streamed tokens and records transcripts")
    func listenAndRespondSpeaksStreamedTokens() async throws {
        let speechToText = MockSpeechToText(transcripts: [
            SpeechTranscript(text: "hel", isFinal: false),
            SpeechTranscript(text: "hello there", isFinal: true),
        ])
        let textToSpeech = MockTextToSpeech()
        let agent = MockAgentRuntime(streamTokens: ["Hello ", "world."])
        let voice = VoiceSession(
            agent: agent,
            speechToText: speechToText,
            textToSpeech: textToSpeech
        )
        let collector = VoiceEventCollector()
        await collector.attach(to: voice)

        let turn = try await voice.listenAndRespond()

        #expect(turn.transcript == "hello there")
        #expect(turn.spokenUtterances.contains("Hello world."))
        #expect(await textToSpeech.spoken.contains("Hello world."))

        let events = await collector.waitUntil { snapshot in
            snapshot.contains(.speakingFinished("Hello world."))
        }
        #expect(events.contains(.partialTranscript("hel")))
        #expect(events.contains(.finalTranscript("hello there")))
        #expect(events.contains(where: { event in
            if case .agent(.output(.token)) = event { return true }
            return false
        }))
        #expect(events.contains(.speaking("Hello world.")))
        #expect(events.contains(.speakingFinished("Hello world.")))
        await collector.cancel()
    }

    @Test("empty transcript does not start the agent")
    func emptyTranscriptDoesNotStartAgent() async throws {
        let agent = ScriptedVoiceAgentRuntime(tokens: ["should not stream"])
        let voice = VoiceSession(
            agent: agent,
            speechToText: MockSpeechToText(),
            textToSpeech: MockTextToSpeech()
        )

        await #expect(throws: VoiceError.emptyTranscript) {
            try await voice.respond(to: "   ")
        }
        #expect(await agent.streamCount == 0)
    }

    @Test("second respond throws busy while a turn is speaking")
    func secondRespondThrowsBusy() async throws {
        let textToSpeech = MockTextToSpeech(hangUntilStopped: true)
        let voice = VoiceSession(
            agent: MockAgentRuntime(streamTokens: ["Hello world."]),
            speechToText: MockSpeechToText(),
            textToSpeech: textToSpeech
        )
        let collector = VoiceEventCollector()
        await collector.attach(to: voice)
        let first = Task {
            try await voice.respond(to: "hello")
        }
        _ = await collector.waitUntil { events in
            events.contains { event in
                if case .speaking = event { return true }
                return false
            }
        }

        await #expect(throws: VoiceError.busy) {
            try await voice.respond(to: "again")
        }
        await #expect(throws: VoiceError.busy) {
            try await voice.listenAndRespond()
        }

        await voice.stop()
        await #expect(throws: VoiceError.cancelled) {
            try await first.value
        }
    }

    @Test("stop during listen cancels STT and TTS")
    func stopDuringListenCancelsAdapters() async throws {
        let speechToText = MockSpeechToText(hangUntilStopped: true)
        let textToSpeech = MockTextToSpeech()
        let agent = MockAgentRuntime(streamTokens: ["Hello world."])
        let voice = VoiceSession(
            agent: agent,
            speechToText: speechToText,
            textToSpeech: textToSpeech
        )
        let collector = VoiceEventCollector()
        await collector.attach(to: voice)
        let listen = Task {
            try await voice.listenAndRespond()
        }
        _ = await collector.waitUntil { events in
            events.contains(.phase(.listening))
        }

        await voice.stop()

        await #expect(throws: VoiceError.cancelled) {
            try await listen.value
        }
        #expect(await speechToText.stopCount >= 1)
        #expect(await textToSpeech.stopCount >= 1)
        #expect(await agent.isCancelled)
    }

    @Test("thinking output is not spoken")
    func thinkingOutputIsNotSpoken() async throws {
        let textToSpeech = MockTextToSpeech()
        let agent = ScriptedVoiceAgentRuntime(streamEvents: [
            .output(.thinking(thought: "Thinking")),
            .output(.token("Done.")),
            .lifecycle(.completed(result: AgentResult(output: "Done."))),
        ])
        let voice = VoiceSession(
            agent: agent,
            speechToText: MockSpeechToText(),
            textToSpeech: textToSpeech
        )

        let turn = try await voice.respond(to: "x")

        #expect(!turn.spokenUtterances.contains("Thinking"))
        #expect(turn.spokenUtterances.contains("Done."))
        #expect(await textToSpeech.spoken == ["Done."])
    }

    @Test("session history is passed through on subsequent responds")
    func sessionPassThroughAcrossTurns() async throws {
        let provider = MockInferenceProvider(responses: [
            "Nice to meet you.",
            "Yes, I remember that.",
        ])
        let agent = try Agent(
            tools: [],
            instructions: "Remember prior turns.",
            inferenceProvider: provider
        )
        let session = InMemorySession()
        let voice = VoiceSession(
            agent: agent,
            speechToText: MockSpeechToText(),
            textToSpeech: MockTextToSpeech(),
            session: session
        )

        _ = try await voice.respond(to: "My name is Casey.")
        let afterFirst = try await session.getAllItems()
        _ = try await voice.respond(to: "Do you remember my name?")
        let afterSecond = try await session.getAllItems()

        #expect(afterFirst.count >= 2)
        #expect(afterSecond.count > afterFirst.count)
        #expect(afterSecond.contains(where: { $0.role == .user && $0.content.contains("Casey") }))
        let messageCalls = await provider.generateMessageCalls
        #expect(messageCalls.count == 2)
        #expect(messageCalls.last?.messages.contains(where: { $0.content.contains("Casey") }) == true)
    }

    @Test("tool-loop result is spoken when no tokens arrive")
    func flushedResultSpokenWhenNoTokens() async throws {
        let textToSpeech = MockTextToSpeech()
        let agent = MockAgentRuntime(response: "The sum is 42.")
        let voice = VoiceSession(
            agent: agent,
            speechToText: MockSpeechToText(),
            textToSpeech: textToSpeech
        )

        let turn = try await voice.respond(to: "What is 20 plus 22?")

        #expect(turn.spokenUtterances.contains("The sum is 42."))
        #expect(await textToSpeech.spoken == ["The sum is 42."])
    }
}

// MARK: - Helpers

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

private actor ScriptedVoiceAgentRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool]
    nonisolated let instructions: String
    nonisolated let configuration: AgentConfiguration
    nonisolated let memory: (any Memory)?
    nonisolated let inferenceProvider: (any InferenceProvider)?
    nonisolated let tracer: (any Tracer)?
    nonisolated let handoffs: [AnyHandoffConfiguration]
    nonisolated let inputGuardrails: [any InputGuardrail]
    nonisolated let outputGuardrails: [any OutputGuardrail]

    private let streamEvents: [AgentEvent]
    private(set) var streamCount = 0

    init(
        streamEvents: [AgentEvent] = [],
        tokens: [String] = []
    ) {
        tools = []
        instructions = "scripted voice runtime"
        configuration = .default
        memory = nil
        inferenceProvider = nil
        tracer = nil
        handoffs = []
        inputGuardrails = []
        outputGuardrails = []
        if streamEvents.isEmpty {
            var events: [AgentEvent] = tokens.map { .output(.token($0)) }
            events.append(.lifecycle(.completed(result: AgentResult(output: tokens.joined()))))
            self.streamEvents = events
        } else {
            self.streamEvents = streamEvents
        }
    }

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        AgentResult(output: "")
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            await self.recordStream()
            continuation.yield(.lifecycle(.started(input: input)))
            for event in await self.streamEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func cancel() async {}

    private func recordStream() {
        streamCount += 1
    }
}
