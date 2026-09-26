// VoiceTurnRuntimeTests.swift
// SwarmTests
//
// VoiceTurnRuntime presents VoiceSession as AgentRuntime.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Turn Runtime", .ephemeralDefaultStores, .timeLimit(.minutes(1)))
struct VoiceTurnRuntimeTests {
    @Test("workflow step returns the spoken agent result")
    func workflowStepReturnsSpokenResult() async throws {
        let textToSpeech = MockTextToSpeech()
        let agent = MockAgentRuntime(streamTokens: ["Hello ", "world."])
        let voice = VoiceSession(
            agent: agent,
            speechToText: MockSpeechToText(),
            textToSpeech: textToSpeech
        )
        let runtime = VoiceTurnRuntime(voice: voice, presenting: agent)
        let result = try await Workflow().step(runtime).run("hello there")
        let spoken = await textToSpeech.spoken

        #expect(result.output.contains("Hello world."))
        #expect(spoken.contains("Hello world."))
    }

    @Test("job fan-out runs VoiceTurnRuntime as a child")
    func jobFanOutRunsVoiceTurn() async throws {
        let textToSpeech = MockTextToSpeech()
        let agent = MockAgentRuntime(streamTokens: ["Okay then."])
        let voice = VoiceSession(
            agent: agent,
            speechToText: MockSpeechToText(),
            textToSpeech: textToSpeech
        )
        let runtime = VoiceTurnRuntime(voice: voice, presenting: agent)
        let results = try await Job().run("notes") { session in
            try await session.fanOut([
                JobChild(name: "voice", agent: runtime, brief: "hello there"),
            ])
        }

        #expect(results.count == 1)
        #expect(results[0].result.output.contains("Okay then."))
        let spoken = await textToSpeech.spoken
        #expect(spoken.contains("Okay then."))
    }
}
