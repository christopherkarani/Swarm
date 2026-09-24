// HTTPSpeechToText.swift
// Swarm Framework
//
// OpenAI-compatible /audio/transcriptions adapter.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for ``HTTPSpeechToText``.
public struct HTTPSpeechConfiguration: Sendable {
    /// Full transcription URL, including `/audio/transcriptions`.
    public var endpoint: URL
    /// Optional bearer token.
    public var apiKey: String?
    /// Model name sent as multipart `model`.
    public var model: String
    /// Session used for the upload. Inject a `URLProtocol` stub in tests.
    public var session: URLSession

    /// Creates an HTTP speech configuration.
    public init(
        endpoint: URL,
        apiKey: String? = nil,
        model: String = "whisper-1",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }
}

/// Speech-to-text that POSTs one audio blob to a Whisper-compatible endpoint.
///
/// Call ``submitAudio(_:mimeType:)`` before ``start()``. No microphone.
public actor HTTPSpeechToText: SpeechToText {
    private let configuration: HTTPSpeechConfiguration
    private var pending: (Data, String)?

    /// Creates an HTTP speech-to-text adapter.
    public init(configuration: HTTPSpeechConfiguration) {
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
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let boundary = "swarm-voice-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            audio: pending.0,
            mimeType: pending.1,
            model: configuration.model,
            boundary: boundary
        )
        let (data, response) = try await configuration.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw VoiceError.speechFailed(reason: "HTTP transcription failed.")
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
        model: String,
        boundary: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
