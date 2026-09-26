// VoiceErrorTests.swift
// SwarmTests
//
// Constructs every VoiceError case and configuration defaults.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Errors", .ephemeralDefaultStores)
struct VoiceErrorTests {
    @Test("VoiceError constructs every case")
    func voiceErrorConstructsEveryCase() {
        let cases: [VoiceError] = [
            .busy,
            .emptyTranscript,
            .notAuthorized(reason: "denied"),
            .unsupportedLocale("xx-YY"),
            .assetUnavailable(reason: "missing"),
            .speechFailed(reason: "mic"),
            .synthesisFailed(reason: "speaker"),
            .agentFinishedWithoutResult,
            .cancelled,
        ]

        #expect(cases.count == 9)
        #expect(VoiceError.busy == VoiceError.busy)
        #expect(VoiceError.notAuthorized(reason: "denied") != .notAuthorized(reason: "other"))
        #expect(VoiceError.unsupportedLocale("en-US") == .unsupportedLocale("en-US"))
        #expect(VoiceError.cancelled != .busy)
        #expect(VoiceError.busy.errorDescription != nil)
        #expect(VoiceError.emptyTranscript.errorDescription != nil)
        #expect(VoiceError.agentFinishedWithoutResult.errorDescription != nil)
        #expect(VoiceError.cancelled.errorDescription != nil)
    }

    @Test("VoiceSessionConfiguration defaults match the spec")
    func configurationDefaultsMatchSpec() {
        let configuration = VoiceSessionConfiguration.default

        #expect(configuration.endOfUtteranceSilence == .milliseconds(1200))
        #expect(configuration.minSpeakCharacters == 8)
        #expect(configuration.sentenceTerminators == [".", "!", "?", "\n"])
        #expect(configuration.voiceIdentifier == nil)
        #expect(configuration.speechRate == nil)
        #expect(configuration.installAssetsIfNeeded == false)
        #expect(configuration.bargeInEnabled == false)
    }

    @Test("SpeechTranscript and VoiceTurnResult are Sendable value types")
    func valueTypesHoldTextOnly() {
        let transcript = SpeechTranscript(text: "hello", isFinal: true)
        #expect(transcript.text == "hello")
        #expect(transcript.isFinal)

        let result = VoiceTurnResult(
            transcript: "hello",
            agentResult: AgentResult(output: "Hi."),
            spokenUtterances: ["Hi."]
        )
        #expect(result.transcript == "hello")
        #expect(result.spokenUtterances == ["Hi."])
        #expect(VoicePhase.idle.rawValue == "idle")
        #expect(VoiceEvent.phase(.listening) == .phase(.listening))
        #expect(
            VoiceEvent.interrupted(transcriptSoFar: "Hi.")
                == .interrupted(transcriptSoFar: "Hi.")
        )
    }
}
