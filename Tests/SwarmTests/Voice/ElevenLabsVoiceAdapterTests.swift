// ElevenLabsVoiceAdapterTests.swift
// SwarmTests
//
// URLProtocol stubs for ElevenLabs STT/TTS. No network.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Swarm
import Testing

@Suite("Voice ElevenLabs Adapters", .ephemeralDefaultStores, .serialized)
struct ElevenLabsVoiceAdapterTests {
    @Test("ElevenLabs speech-to-text yields the stubbed transcript")
    func elevenLabsSpeechToTextYieldsTranscript() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, _ in
            .json(#"{"text":"hello there","language_code":"en"}"#)
        }

        let stt = ElevenLabsSpeechToText(
            configuration: ElevenLabsSpeechConfiguration(
                apiKey: "test-key",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        await stt.submitAudio(Data("wav".utf8), mimeType: "audio/wav")

        var transcripts: [SpeechTranscript] = []
        for try await transcript in stt.start() {
            transcripts.append(transcript)
        }

        #expect(transcripts == [SpeechTranscript(text: "hello there", isFinal: true)])
        let request = try #require(ElevenLabsURLProtocol.requests.first)
        #expect(request.url.path.contains("v1/speech-to-text"))
        #expect(request.headers["xi-api-key"] == "test-key")
        #expect(request.headers["Authorization"] == nil)
        #expect(request.body.contains(Data("scribe_v2".utf8)))
        #expect(request.body.contains(Data("audio.wav".utf8)))
        #expect(request.body.contains(Data("wav".utf8)))
    }

    @Test("ElevenLabs speech-to-text sends language code and mp3 filename")
    func elevenLabsSpeechToTextSendsLanguageAndFilename() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, _ in
            .json(#"{"text":"bonjour"}"#)
        }

        let stt = ElevenLabsSpeechToText(
            configuration: ElevenLabsSpeechConfiguration(
                modelId: "scribe_v1",
                languageCode: "fr",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        await stt.submitAudio(Data("mp3".utf8), mimeType: "audio/mpeg")
        for try await _ in stt.start() {}

        let request = try #require(ElevenLabsURLProtocol.requests.first)
        let body = String(data: request.body, encoding: .utf8) ?? ""
        #expect(body.contains("scribe_v1"))
        #expect(body.contains("language_code"))
        #expect(body.contains("audio.mp3"))
    }

    @Test("ElevenLabs speech-to-text without queued audio fails closed")
    func elevenLabsSpeechToTextRequiresQueuedAudio() async {
        let stt = ElevenLabsSpeechToText(
            configuration: ElevenLabsSpeechConfiguration(apiKey: "test-key")
        )
        await #expect(throws: VoiceError.emptyTranscript) {
            for try await _ in stt.start() {}
        }
    }

    @Test("ElevenLabs speech-to-text surfaces HTTP failures")
    func elevenLabsSpeechToTextSurfacesHTTPFailures() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, _ in
            ElevenLabsURLProtocol.Stub(status: 401, headers: [:], body: Data())
        }

        let stt = ElevenLabsSpeechToText(
            configuration: ElevenLabsSpeechConfiguration(
                apiKey: "bad-key",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        await stt.submitAudio(Data("wav".utf8))
        await #expect(throws: VoiceError.speechFailed(reason: "ElevenLabs transcription failed (HTTP 401).")) {
            for try await _ in stt.start() {}
        }
    }

    @Test("ElevenLabs speech-to-text surfaces the API error message")
    func elevenLabsSpeechToTextSurfacesAPIMessage() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, _ in
            ElevenLabsURLProtocol.Stub(
                status: 400,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"Detail":{"message":"File is corrupted."}}"#.utf8)
            )
        }

        let stt = ElevenLabsSpeechToText(
            configuration: ElevenLabsSpeechConfiguration(
                apiKey: "test-key",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        await stt.submitAudio(Data("wav".utf8))
        await #expect(throws: VoiceError.speechFailed(reason: "File is corrupted. (HTTP 400).")) {
            for try await _ in stt.start() {}
        }
    }

    @Test("ElevenLabs text-to-speech stores the stubbed audio")
    func elevenLabsTextToSpeechStoresAudio() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, body in
            let text = String(data: body, encoding: .utf8) ?? ""
            #expect(text.contains("Hello world."))
            #expect(text.contains("eleven_multilingual_v2"))
            return .data(Data("audio-bytes".utf8), contentType: "audio/mpeg")
        }

        let tts = ElevenLabsTextToSpeech(
            configuration: ElevenLabsSpeechSynthesisConfiguration(
                voiceId: "voice-123",
                apiKey: "test-key",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        try await tts.speak("Hello world.")
        let audio = await tts.lastAudio
        #expect(audio == Data("audio-bytes".utf8))

        let request = try #require(ElevenLabsURLProtocol.requests.first)
        #expect(request.url.path.contains("v1/text-to-speech/voice-123"))
        #expect(request.headers["xi-api-key"] == "test-key")
        #expect(request.headers["Authorization"] == nil)
    }

    @Test("ElevenLabs text-to-speech sends output format and voice settings")
    func elevenLabsTextToSpeechSendsFormatAndSettings() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, body in
            let text = String(data: body, encoding: .utf8) ?? ""
            #expect(text.contains("voice_settings"))
            #expect(text.contains("stability"))
            #expect(text.contains("similarity_boost"))
            return .data(Data("audio".utf8), contentType: "audio/mpeg")
        }

        let tts = ElevenLabsTextToSpeech(
            configuration: ElevenLabsSpeechSynthesisConfiguration(
                voiceId: "voice-123",
                apiKey: "test-key",
                outputFormat: "mp3_44100_128",
                voiceSettings: ElevenLabsVoiceSettings(stability: 0.5, similarityBoost: 0.75),
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        try await tts.speak("Hello.")
        let request = try #require(ElevenLabsURLProtocol.requests.first)
        #expect(request.url.query?.contains("output_format=mp3_44100_128") == true)
    }

    @Test("ElevenLabs text-to-speech rejects empty utterances")
    func elevenLabsTextToSpeechRejectsEmptyUtterances() async throws {
        let tts = ElevenLabsTextToSpeech(
            configuration: ElevenLabsSpeechSynthesisConfiguration(voiceId: "voice-123")
        )
        await #expect(throws: VoiceError.synthesisFailed(reason: "Utterance is empty.")) {
            try await tts.speak("   ")
        }
    }

    @Test("ElevenLabs text-to-speech surfaces string-form API errors")
    func elevenLabsTextToSpeechSurfacesStringError() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, _ in
            ElevenLabsURLProtocol.Stub(
                status: 402,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"detail":"Paid plan required."}"#.utf8)
            )
        }

        let tts = ElevenLabsTextToSpeech(
            configuration: ElevenLabsSpeechSynthesisConfiguration(
                voiceId: "voice-123",
                apiKey: "test-key",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        await #expect(throws: VoiceError.synthesisFailed(reason: "Paid plan required. (HTTP 402).")) {
            try await tts.speak("Hello.")
        }
    }

    @Test("ElevenLabs text-to-speech surfaces HTTP failures")
    func elevenLabsTextToSpeechSurfacesHTTPFailures() async throws {
        ElevenLabsURLProtocol.reset()
        defer { ElevenLabsURLProtocol.reset() }
        ElevenLabsURLProtocol.handler = { _, _ in
            ElevenLabsURLProtocol.Stub(status: 401, headers: [:], body: Data())
        }

        let tts = ElevenLabsTextToSpeech(
            configuration: ElevenLabsSpeechSynthesisConfiguration(
                voiceId: "voice-123",
                apiKey: "bad-key",
                session: ElevenLabsURLProtocol.makeSession()
            )
        )
        await #expect(throws: VoiceError.synthesisFailed(reason: "ElevenLabs speech failed (HTTP 401).")) {
            try await tts.speak("Hello.")
        }
    }
}

private final class ElevenLabsURLProtocol: URLProtocol {
    struct RecordedRequest: Sendable {
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    struct Stub: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data

        static func json(_ text: String) -> Stub {
            Stub(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(text.utf8)
            )
        }

        static func data(_ body: Data, contentType: String) -> Stub {
            Stub(
                status: 200,
                headers: ["Content-Type": contentType],
                body: body
            )
        }
    }

    private static let state = Lock()
    static var handler: (@Sendable (URLRequest, Data) -> Stub)? {
        get { state.withLock(\.handler) }
        set { state.withLock { $0.handler = newValue } }
    }

    static var requests: [RecordedRequest] {
        state.withLock(\.requests)
    }

    static func reset() {
        state.withLock {
            $0.handler = nil
            $0.requests = []
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ElevenLabsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody
            ?? request.httpBodyStream.flatMap(Self.read)
            ?? Data()
        let recorded = RecordedRequest(
            url: request.url ?? URL(string: "https://example.test")!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )
        let stub = Self.state.withLock { state -> Stub in
            state.requests.append(recorded)
            return state.handler?(self.request, body)
                ?? Stub(status: 500, headers: [:], body: Data())
        }
        let response = HTTPURLResponse(
            url: recorded.url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private final class Lock: @unchecked Sendable {
        struct State {
            var handler: (@Sendable (URLRequest, Data) -> Stub)?
            var requests: [RecordedRequest] = []
        }

        private var state = State()
        private let lock = NSLock()

        func withLock<T>(_ body: (inout State) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }

        func withLock<T>(_ keyPath: KeyPath<State, T>) -> T {
            withLock { $0[keyPath: keyPath] }
        }
    }
}
