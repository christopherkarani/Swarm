// VoiceSessionConfiguration.swift
// Swarm Framework
//
// Turn timing, sentence splitting, and optional speech-adapter settings.

import Foundation

/// Configuration for a ``VoiceSession`` turn.
public struct VoiceSessionConfiguration: Sendable, Equatable {
    /// Locale used by speech adapters.
    public var locale: Locale

    /// Silence after the last volatile transcript that ends a listen.
    ///
    /// Mocks may ignore this and finish when their scripted stream ends.
    public var endOfUtteranceSilence: Duration

    /// Minimum character count before a terminator emits a speakable sentence.
    public var minSpeakCharacters: Int

    /// Characters that close a speakable sentence.
    public var sentenceTerminators: Set<Character>

    /// Optional platform voice identifier for text-to-speech.
    public var voiceIdentifier: String?

    /// Optional synthesizer rate. `nil` uses the platform default.
    public var speechRate: Float?

    /// Whether Apple speech language assets may be downloaded on first listen.
    ///
    /// Defaults to `false` so the first listen cannot surprise-download.
    public var installAssetsIfNeeded: Bool

    /// When `true`, a ``VoiceActivityDetector`` may interrupt speaking and
    /// start a replacement listen. Defaults to `false`.
    public var bargeInEnabled: Bool

    /// Default configuration: 1200 ms silence, 8-character minimum, `. ! ? \\n`.
    public static let `default` = VoiceSessionConfiguration()

    /// Creates a voice session configuration.
    public init(
        locale: Locale = .current,
        endOfUtteranceSilence: Duration = .milliseconds(1200),
        minSpeakCharacters: Int = 8,
        sentenceTerminators: Set<Character> = [".", "!", "?", "\n"],
        voiceIdentifier: String? = nil,
        speechRate: Float? = nil,
        installAssetsIfNeeded: Bool = false,
        bargeInEnabled: Bool = false
    ) {
        self.locale = locale
        self.endOfUtteranceSilence = endOfUtteranceSilence
        self.minSpeakCharacters = minSpeakCharacters
        self.sentenceTerminators = sentenceTerminators
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
        self.installAssetsIfNeeded = installAssetsIfNeeded
        self.bargeInEnabled = bargeInEnabled
    }
}
