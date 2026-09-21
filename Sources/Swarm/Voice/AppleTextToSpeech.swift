// AppleTextToSpeech.swift
// Swarm Framework
//
// AVSpeechSynthesizer adapter. Isolated on MainActor.

#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// On-device text-to-speech using `AVSpeechSynthesizer`.
///
/// The synthesizer and its delegate live on the main actor so this type stays
/// `Sendable` without an unchecked conformance.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public actor AppleTextToSpeech: TextToSpeech {
    private let configuration: VoiceSessionConfiguration

    /// Creates an Apple speech synthesizer adapter.
    public init(configuration: VoiceSessionConfiguration = .default) {
        self.configuration = configuration
    }

    public func speak(_ text: String) async throws {
        try await AppleSpeechSynthesizerEngine.shared.speak(text, configuration: configuration)
    }

    public func stop() async {
        await AppleSpeechSynthesizerEngine.shared.stop()
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@MainActor
final class AppleSpeechSynthesizerEngine: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AppleSpeechSynthesizerEngine()

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, configuration: VoiceSessionConfiguration) async throws {
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw VoiceError.synthesisFailed(reason: "Utterance is empty.")
        }

        synthesizer.stopSpeaking(at: .immediate)
        if let pending = continuation {
            continuation = nil
            pending.resume()
        }

        let utterance = AVSpeechUtterance(string: text)
        if let identifier = configuration.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: configuration.locale.identifier)
        }
        if let rate = configuration.speechRate {
            utterance.rate = rate
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if let pending = continuation {
            continuation = nil
            pending.resume()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.finishCurrent()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.finishCurrent()
        }
    }

    private func finishCurrent() {
        if let pending = continuation {
            continuation = nil
            pending.resume()
        }
    }
}
#endif
