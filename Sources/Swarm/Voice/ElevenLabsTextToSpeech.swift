// ElevenLabsTextToSpeech.swift
// Swarm Framework
//
// ElevenLabs /v1/text-to-speech/{voice_id} adapter.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Optional ElevenLabs voice tuning, sent as `voice_settings`.
public struct ElevenLabsVoiceSettings: Sendable, Equatable {
    /// Stability, 0.0 to 1.0. Higher is more consistent.
    public var stability: Double?
    /// Similarity boost, 0.0 to 1.0. Higher matches the voice more closely.
    public var similarityBoost: Double?

    /// Creates voice settings. `nil` fields are omitted from the request.
    public init(stability: Double? = nil, similarityBoost: Double? = nil) {
        self.stability = stability
        self.similarityBoost = similarityBoost
    }
}

/// Configuration for ``ElevenLabsTextToSpeech``.
public struct ElevenLabsSpeechSynthesisConfiguration: Sendable {
    /// Default ElevenLabs API base URL.
    public static let defaultBaseURL = URL(string: "https://api.elevenlabs.io")!

    /// API base URL. The client appends `/v1/text-to-speech/{voice_id}`.
    public var baseURL: URL
    /// Voice id from the ElevenLabs voice library.
    public var voiceId: String
    /// ElevenLabs API key, sent as `xi-api-key`.
    public var apiKey: String?
    /// Synthesis model id, for example `eleven_multilingual_v2`.
    public var modelId: String
    /// Optional `output_format` query value, for example `mp3_44100_128`.
    public var outputFormat: String?
    /// Optional voice tuning.
    public var voiceSettings: ElevenLabsVoiceSettings?
    /// Session used for synthesis. Inject a `URLProtocol` stub in tests.
    public var session: URLSession

    /// Full synthesis URL, including the voice id.
    public var endpoint: URL {
        var url = baseURL.appendingPathComponent("v1/text-to-speech/\(voiceId)")
        if let outputFormat, !outputFormat.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "output_format", value: outputFormat)]
            if let composed = components.url {
                url = composed
            }
        }
        return url
    }

    /// Creates an ElevenLabs speech-synthesis configuration.
    public init(
        voiceId: String,
        baseURL: URL = defaultBaseURL,
        apiKey: String? = nil,
        modelId: String = "eleven_multilingual_v2",
        outputFormat: String? = nil,
        voiceSettings: ElevenLabsVoiceSettings? = nil,
        session: URLSession = .shared
    ) {
        self.voiceId = voiceId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
        self.outputFormat = outputFormat
        self.voiceSettings = voiceSettings
        self.session = session
    }
}

/// Text-to-speech that POSTs text to ElevenLabs.
///
/// A 2xx response completes the utterance. Audio bytes are exposed via
/// ``lastAudio`` for the host to play; this adapter plays nothing itself.
public actor ElevenLabsTextToSpeech: TextToSpeech {
    private let configuration: ElevenLabsSpeechSynthesisConfiguration

    /// Last successful audio payload. Tests may inspect it.
    public private(set) var lastAudio: Data = Data()

    /// Creates an ElevenLabs text-to-speech adapter.
    public init(configuration: ElevenLabsSpeechSynthesisConfiguration) {
        self.configuration = configuration
    }

    public func speak(_ text: String) async throws {
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw VoiceError.synthesisFailed(reason: "Utterance is empty.")
        }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        }
        var payload: [String: Any] = [
            "text": text,
            "model_id": configuration.modelId,
        ]
        if let settings = configuration.voiceSettings {
            var voiceSettings: [String: Any] = [:]
            if let stability = settings.stability {
                voiceSettings["stability"] = stability
            }
            if let similarityBoost = settings.similarityBoost {
                voiceSettings["similarity_boost"] = similarityBoost
            }
            if !voiceSettings.isEmpty {
                payload["voice_settings"] = voiceSettings
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let (data, response) = try await configuration.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceError.synthesisFailed(reason: "ElevenLabs speech failed.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw VoiceError.synthesisFailed(
                reason: Self.apiErrorMessage(data, status: http.statusCode, fallback: "speech")
            )
        }
        lastAudio = data
    }

    public func stop() async {}
    /// ElevenLabs' own error message when the body parses, else a status fallback.
    /// Matches the detail wrapper case-insensitively; some endpoints return it
    /// as a nested object, others as a plain string.
    private static func apiErrorMessage(_ data: Data, status: Int, fallback: String) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in object where key.lowercased() == "Detail".lowercased() {
                if let nested = value as? [String: Any],
                   let message = nested["message"] as? String {
                    return "\(message) (HTTP \(status))."
                }
                if let message = value as? String {
                    return "\(message) (HTTP \(status))."
                }
            }
            if let message = object["message"] as? String {
                return "\(message) (HTTP \(status))."
            }
        }
        return "ElevenLabs \(fallback) failed (HTTP \(status))."
    }
}
