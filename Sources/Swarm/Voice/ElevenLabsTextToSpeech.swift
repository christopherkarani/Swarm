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
    /// Optional `optimize_streaming_latency` value (0-4). Higher trades a
    /// little quality for lower time-to-first-byte on ``streamAudio(_:)``.
    public var optimizeStreamingLatency: Int?
    /// Session used for synthesis. Inject a `URLProtocol` stub in tests.
    public var session: URLSession

    /// Full synthesis URL, including the voice id and streaming queries.
    public var endpoint: URL {
        let url = baseURL.appendingPathComponent("v1/text-to-speech/\(voiceId)")
        var items: [URLQueryItem] = []
        if let outputFormat, !outputFormat.isEmpty {
            items.append(URLQueryItem(name: "output_format", value: outputFormat))
        }
        if let optimizeStreamingLatency {
            items.append(URLQueryItem(name: "optimize_streaming_latency", value: String(optimizeStreamingLatency)))
        }
        guard !items.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        components.queryItems = items
        return components.url ?? url
    }

    /// Creates an ElevenLabs speech-synthesis configuration.
    public init(
        voiceId: String,
        baseURL: URL = defaultBaseURL,
        apiKey: String? = nil,
        modelId: String = "eleven_multilingual_v2",
        outputFormat: String? = nil,
        voiceSettings: ElevenLabsVoiceSettings? = nil,
        optimizeStreamingLatency: Int? = nil,
        session: URLSession = .shared
    ) {
        self.voiceId = voiceId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
        self.outputFormat = outputFormat
        self.voiceSettings = voiceSettings
        self.optimizeStreamingLatency = optimizeStreamingLatency
        self.session = session
    }
}

/// Text-to-speech that POSTs text to ElevenLabs.
///
/// A 2xx response completes the utterance. Audio bytes are exposed via
/// ``lastAudio`` for the host to play; this adapter plays nothing itself.
/// ``streamAudio(_:)`` yields MP3 chunks while synthesis is still running.
public actor ElevenLabsTextToSpeech: StreamingTextToSpeech {
    private nonisolated let configuration: ElevenLabsSpeechSynthesisConfiguration
    private nonisolated let interrupt = VoiceCancellable()

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
        let configuration = configuration
        let interrupt = interrupt
        let task = Task<Data, Error> {
            let request = try Self.synthesisRequest(configuration: configuration, text: text)
            let (data, response) = try await configuration.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw VoiceError.synthesisFailed(reason: "ElevenLabs speech failed.")
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw VoiceError.synthesisFailed(
                    reason: Self.apiErrorMessage(data, status: http.statusCode, fallback: "speech")
                )
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

    /// Synthesizes `text`, yielding MP3 chunks as ElevenLabs streams them.
    ///
    /// Chunks concatenate byte-for-byte into ``lastAudio``. `stop()` and
    /// consumer cancellation end the stream with ``VoiceError/cancelled``.
    public nonisolated func streamAudio(_ text: String) -> AsyncThrowingStream<Data, Error> {
        let configuration = configuration
        let interrupt = interrupt
        return AsyncThrowingStream { continuation in
            guard text.contains(where: { !$0.isWhitespace }) else {
                continuation.finish(throwing: VoiceError.synthesisFailed(reason: "Utterance is empty."))
                return
            }
            let request: URLRequest
            do {
                request = try Self.synthesisRequest(configuration: configuration, text: text)
            } catch {
                continuation.finish(throwing: VoiceError.synthesisFailed(reason: String(describing: error)))
                return
            }
            let download = ChunkedAudioDownload(
                request: request,
                sessionConfiguration: configuration.session.configuration,
                onChunk: { continuation.yield($0) },
                onCompletion: { result in
                    switch result {
                    case .success(let data):
                        Task { [weak self] in
                            await self?.setLastAudio(data)
                            continuation.finish()
                        }
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                }
            )
            download.start()
            interrupt.store { download.cancel() }
            continuation.onTermination = { _ in download.cancel() }
        }
    }

    public func stop() async {
        interrupt.cancel()
    }

    private func setLastAudio(_ data: Data) {
        lastAudio = data
    }

    private static func synthesisRequest(
        configuration: ElevenLabsSpeechSynthesisConfiguration,
        text: String
    ) throws -> URLRequest {
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
        return request
    }

    /// Progressive HTTP download that yields response-body chunks via delegate.
    ///
    /// `URLSession.bytes(for:)` is avoided deliberately: URLProtocol stubs and
    /// swift-corelibs-foundation do not deliver it reliably (see
    /// `OpenAICompatibleProvider`). The data-task delegate path works on both.
    /// Delegate callbacks arrive on one serial queue; `start()`/`cancel()`
    /// may arrive from any thread, so task lifecycle is lock-guarded.
    private final class ChunkedAudioDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        init(
            request: URLRequest,
            sessionConfiguration: URLSessionConfiguration,
            onChunk: @escaping @Sendable (Data) -> Void,
            onCompletion: @escaping @Sendable (Result<Data, VoiceError>) -> Void
        ) {
            self.request = request
            self.sessionConfiguration = sessionConfiguration
            self.onChunk = onChunk
            self.onCompletion = onCompletion
        }

        func start() {
            lock.withLock {
                guard session == nil else { return }
                let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        }

        func cancel() {
            lock.withLock { task?.cancel() }
        }

        func urlSession(
            _: URLSession,
            dataTask _: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            statusCode = (response as? HTTPURLResponse)?.statusCode
            // Errors are buffered instead of yielded so the completion can
            // report the server's message; .allow keeps the body flowing.
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            guard !data.isEmpty else { return }
            if let statusCode, statusCode >= 400 {
                errorData.append(data)
            } else {
                received.append(data)
                onChunk(data)
            }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
            let alreadyFinished: Bool = lock.withLock {
                defer { finished = true }
                return finished
            }
            guard !alreadyFinished else { return }
            lock.withLock { session }?.finishTasksAndInvalidate()
            if let error {
                if let cancelled = VoiceCancellation.error(for: error) {
                    onCompletion(.failure(cancelled))
                } else {
                    onCompletion(.failure(.synthesisFailed(reason: String(describing: error))))
                }
            } else if let statusCode, statusCode >= 400 {
                onCompletion(.failure(.synthesisFailed(
                    reason: apiErrorMessage(errorData, status: statusCode, fallback: "speech")
                )))
            } else if statusCode == nil {
                onCompletion(.failure(.synthesisFailed(reason: "ElevenLabs speech failed.")))
            } else {
                onCompletion(.success(received))
            }
        }

        private let request: URLRequest
        private let sessionConfiguration: URLSessionConfiguration
        private let onChunk: @Sendable (Data) -> Void
        private let onCompletion: @Sendable (Result<Data, VoiceError>) -> Void

        private let lock = NSLock()
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var finished = false
        // Touched only on the serial delegate queue.
        private var statusCode: Int?
        private var received = Data()
        private var errorData = Data()
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
}
