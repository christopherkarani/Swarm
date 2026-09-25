// VoiceLiveMicTests.swift
// SwarmTests
//
// Opt-in live-mic proof. Default CI skips. Never records samples.

#if canImport(Speech) && canImport(AVFoundation)
import Foundation
import Speech
@testable import Swarm
import Testing

@Suite("Voice Live Microphone")
struct VoiceLiveMicTests {
    @Test("opt-in job prepares Apple STT without capturing audio")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    func prepareAppleSpeechWithoutCapture() async throws {
        guard ProcessInfo.processInfo.environment["SWARM_VOICE_LIVE_MIC"] == "1" else {
            return
        }
        guard SpeechTranscriber.isAvailable else {
            Issue.record("SpeechTranscriber unavailable on this runner.")
            return
        }

        let speechToText = AppleSpeechToText()
        do {
            _ = try await speechToText.prepareForSession()
        } catch let error as VoiceError {
            switch error {
            case .assetUnavailable, .unsupportedLocale:
                return
            default:
                throw error
            }
        }
    }
}
#endif
