// HTTPTextToSpeech.swift
// Swarm Framework
//
// OpenAI-compatible /audio/speech adapter.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for ``HTTPTextToSpeech``.
public struct HTTPSpeechSynthesisConfiguration: Sendable {
    /// Full speech URL, including `/audio/speech`.
    public var endpoint: URL
    public var apiKey: String?
    public var model: String
    public var voice: String
    public var session: URLSession

    /// Creates an HTTP speech-synthesis configuration.
    public init(
        endpoint: URL,
        apiKey: String? = nil,
        model: String = "tts-1",
        voice: String = "alloy",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.session = session
    }
}

/// Text-to-speech that POSTs text to a compatible `/audio/speech` endpoint.
///
/// A 2xx response completes the utterance. Audio bytes are not played here.
public actor HTTPTextToSpeech: TextToSpeech {
    private let configuration: HTTPSpeechSynthesisConfiguration
    private nonisolated let interrupt = VoiceCancellable()

    /// Last successful audio payload. Tests may inspect it.
    public private(set) var lastAudio: Data = Data()

    /// Creates an HTTP text-to-speech adapter.
    public init(configuration: HTTPSpeechSynthesisConfiguration) {
        self.configuration = configuration
    }

    public func speak(_ text: String) async throws {
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw VoiceError.synthesisFailed(reason: "Utterance is empty.")
        }
        let configuration = configuration
        let interrupt = interrupt
        let task = Task<Data, Error> {
            var request = URLRequest(url: configuration.endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = configuration.apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            let payload: [String: Any] = [
                "model": configuration.model,
                "voice": configuration.voice,
                "input": text,
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            let (data, response) = try await configuration.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw VoiceError.synthesisFailed(reason: "HTTP speech failed.")
            }
            return data
        }
        interrupt.store { task.cancel() }
        do {
            lastAudio = try await task.value
        } catch {
            if let cancelled = VoiceCancellation.error(for: error) {
                throw cancelled
            }
            throw error
        }
    }

    public func stop() async {
        interrupt.cancel()
    }
}
