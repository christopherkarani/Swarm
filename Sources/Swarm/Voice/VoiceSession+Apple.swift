// VoiceSession+Apple.swift
// Swarm Framework
//
// Apple on-device factory. Not referenced from VoiceSession.swift.

#if canImport(Speech) && canImport(AVFoundation)
import Foundation

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension VoiceSession {
    /// Constructs a session with Apple on-device STT and TTS.
    ///
    /// Preflights locale and language assets. Does not open the microphone.
    /// When `installAssetsIfNeeded` is `false` (the default), missing assets
    /// throw ``VoiceError/assetUnavailable(reason:)``.
    public static func appleOnDevice(
        agent: any AgentRuntime,
        session: (any Session)? = nil,
        locale: Locale = .current,
        configuration: VoiceSessionConfiguration = .default,
        installAssetsIfNeeded: Bool = false
    ) async throws -> VoiceSession {
        var resolved = configuration
        resolved.locale = locale
        resolved.installAssetsIfNeeded = installAssetsIfNeeded

        let speechToText = AppleSpeechToText(configuration: resolved)
        _ = try await speechToText.prepareForSession()
        let textToSpeech = AppleTextToSpeech(configuration: resolved)

        return VoiceSession(
            agent: agent,
            speechToText: speechToText,
            textToSpeech: textToSpeech,
            session: session,
            configuration: resolved
        )
    }
}
#endif
