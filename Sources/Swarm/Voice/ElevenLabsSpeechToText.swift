// ElevenLabsSpeechToText.swift
// Swarm Framework
//
// ElevenLabs Scribe /v1/speech-to-text adapter.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for ``ElevenLabsSpeechToText``.
public struct ElevenLabsSpeechConfiguration: Sendable {
    /// Default ElevenLabs API base URL.
    public static let defaultBaseURL = URL(string: "https://api.elevenlabs.io")!

    /// API base URL. The client appends `/v1/speech-to-text`.
    public var baseURL: URL
    /// ElevenLabs API key, sent as `xi-api-key`.
    public var apiKey: String?
    /// Scribe model id, for example `scribe_v2` or `scribe_v1`.
    public var modelId: String
    /// Optional ISO-639-1 language code. `nil` auto-detects.
    public var languageCode: String?
    /// Session used for the upload. Inject a `URLProtocol` stub in tests.
    public var session: URLSession

    /// Full transcription URL.
    public var endpoint: URL {
        baseURL.appendingPathComponent("v1/speech-to-text")
    }

    /// Creates an ElevenLabs speech-to-text configuration.
    public init(
        baseURL: URL = defaultBaseURL,
        apiKey: String? = nil,
        modelId: String = "scribe_v2",
        languageCode: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
        self.languageCode = languageCode
        self.session = session
    }
}

/// Speech-to-text that POSTs one audio blob to ElevenLabs Scribe.
///
/// Call ``submitAudio(_:mimeType:)`` before ``start()``. No microphone.
public actor ElevenLabsSpeechToText: SpeechToText {
    private let configuration: ElevenLabsSpeechConfiguration
    private var pending: (Data, String)?

    /// Creates an ElevenLabs speech-to-text adapter.
    public init(configuration: ElevenLabsSpeechConfiguration) {
        self.configuration = configuration
    }

    /// Queues audio for the next ``start()``.
    public func submitAudio(_ data: Data, mimeType: String = "audio/wav") {
        pending = (data, mimeType)
    }

    public nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        StreamHelper.makeTrackedStream { continuation in
            do {
                let text = try await self.transcribePending()
                continuation.yield(SpeechTranscript(text: text, isFinal: true))
                continuation.finish()
            } catch let error as VoiceError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: VoiceError.speechFailed(reason: String(describing: error)))
            }
        }
    }

    public func stop() async {
        pending = nil
    }

    private func transcribePending() async throws -> String {
        guard let pending else {
            throw VoiceError.emptyTranscript
        }
        self.pending = nil
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        }
        let boundary = "swarm-voice-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            audio: pending.0,
            mimeType: pending.1,
            modelId: configuration.modelId,
            languageCode: configuration.languageCode,
            boundary: boundary
        )
        let (data, response) = try await configuration.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceError.speechFailed(reason: "ElevenLabs transcription failed.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw VoiceError.speechFailed(
                reason: Self.apiErrorMessage(data, status: http.statusCode, fallback: "transcription")
            )
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            return text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func multipartBody(
        audio: Data,
        mimeType: String,
        modelId: String,
        languageCode: String?,
        boundary: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        append("\(modelId)\r\n")
        if let languageCode, !languageCode.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n")
            append("\(languageCode)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename(mimeType: mimeType))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

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

    private static func filename(mimeType: String) -> String {
        switch mimeType.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) {
        case "audio/mpeg", "audio/mp3": "audio.mp3"
        case "audio/mp4", "audio/m4a", "audio/x-m4a": "audio.m4a"
        case "audio/webm": "audio.webm"
        case "audio/ogg": "audio.ogg"
        case "audio/flac", "audio/x-flac": "audio.flac"
        default: "audio.wav"
        }
    }
}
