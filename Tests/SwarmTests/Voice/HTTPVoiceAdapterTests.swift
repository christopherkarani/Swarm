// HTTPVoiceAdapterTests.swift
// SwarmTests
//
// URLProtocol stubs for HTTP STT/TTS. No network.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Swarm
import Testing

@Suite("Voice HTTP Adapters", .ephemeralDefaultStores, .serialized)
struct VoiceHTTPAdapterTests {
    @Test("HTTP speech-to-text yields the stubbed transcript")
    func httpSpeechToTextYieldsTranscript() async throws {
        VoiceHTTPURLProtocol.reset()
        defer { VoiceHTTPURLProtocol.reset() }
        VoiceHTTPURLProtocol.handler = { _, _ in
            .json(#"{"text":"hello there"}"#)
        }

        let stt = HTTPSpeechToText(
            configuration: HTTPSpeechConfiguration(
                endpoint: URL(string: "https://example.test/v1/audio/transcriptions")!,
                apiKey: "test-key",
                session: VoiceHTTPURLProtocol.makeSession()
            )
        )
        await stt.submitAudio(Data("wav".utf8), mimeType: "audio/wav")

        var transcripts: [SpeechTranscript] = []
        for try await transcript in stt.start() {
            transcripts.append(transcript)
        }

        #expect(transcripts == [SpeechTranscript(text: "hello there", isFinal: true)])
        let request = try #require(VoiceHTTPURLProtocol.requests.first)
        #expect(request.url.path.contains("transcriptions"))
        #expect(request.headers["Authorization"] == "Bearer test-key")
        #expect(request.body.contains(Data("wav".utf8)))
    }

    @Test("HTTP text-to-speech stores the stubbed audio")
    func httpTextToSpeechStoresAudio() async throws {
        VoiceHTTPURLProtocol.reset()
        defer { VoiceHTTPURLProtocol.reset() }
        VoiceHTTPURLProtocol.handler = { _, body in
            #expect(String(data: body, encoding: .utf8)?.contains("Hello world.") == true)
            return .data(Data("audio-bytes".utf8), contentType: "audio/mpeg")
        }

        let tts = HTTPTextToSpeech(
            configuration: HTTPSpeechSynthesisConfiguration(
                endpoint: URL(string: "https://example.test/v1/audio/speech")!,
                apiKey: "test-key",
                session: VoiceHTTPURLProtocol.makeSession()
            )
        )
        try await tts.speak("Hello world.")
        let audio = await tts.lastAudio
        #expect(audio == Data("audio-bytes".utf8))
    }

    @Test("HTTP speech-to-text without queued audio fails closed")
    func httpSpeechToTextRequiresQueuedAudio() async {
        let stt = HTTPSpeechToText(
            configuration: HTTPSpeechConfiguration(
                endpoint: URL(string: "https://example.test/v1/audio/transcriptions")!
            )
        )
        await #expect(throws: VoiceError.emptyTranscript) {
            for try await _ in stt.start() {}
        }
    }

    @Test("HTTP speak honours stop")
    func httpSpeakHonoursStop() async throws {
        VoiceHTTPURLProtocol.reset()
        defer { VoiceHTTPURLProtocol.reset() }
        VoiceHTTPURLProtocol.responseDelay = 2
        VoiceHTTPURLProtocol.handler = { _, _ in
            .data(Data("audio".utf8), contentType: "audio/mpeg")
        }

        let tts = HTTPTextToSpeech(
            configuration: HTTPSpeechSynthesisConfiguration(
                endpoint: URL(string: "https://example.test/v1/audio/speech")!,
                session: VoiceHTTPURLProtocol.makeSession()
            )
        )
        let task = Task { try await tts.speak("Hello.") }
        while VoiceHTTPURLProtocol.requests.isEmpty {
            await Task.yield()
        }
        await tts.stop()
        await #expect(throws: VoiceError.cancelled) {
            try await task.value
        }
    }

    @Test("HTTP speech-to-text honours stop")
    func httpSpeechToTextHonoursStop() async throws {
        VoiceHTTPURLProtocol.reset()
        defer { VoiceHTTPURLProtocol.reset() }
        VoiceHTTPURLProtocol.responseDelay = 2
        VoiceHTTPURLProtocol.handler = { _, _ in
            .json(#"{"text":"too slow"}"#)
        }

        let stt = HTTPSpeechToText(
            configuration: HTTPSpeechConfiguration(
                endpoint: URL(string: "https://example.test/v1/audio/transcriptions")!,
                session: VoiceHTTPURLProtocol.makeSession()
            )
        )
        await stt.submitAudio(Data("wav".utf8))
        let task = Task {
            for try await _ in stt.start() {}
        }
        while VoiceHTTPURLProtocol.requests.isEmpty {
            await Task.yield()
        }
        await stt.stop()
        await #expect(throws: VoiceError.cancelled) {
            try await task.value
        }
    }
}

private final class VoiceHTTPURLProtocol: URLProtocol {
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

    /// Seconds to wait before delivering a response.
    static var responseDelay: TimeInterval {
        get { state.withLock(\.responseDelay) }
        set { state.withLock { $0.responseDelay = newValue } }
    }

    static func reset() {
        state.withLock {
            $0.handler = nil
            $0.requests = []
            $0.responseDelay = 0
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VoiceHTTPURLProtocol.self]
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
        let (stub, delay) = Self.state.withLock { state -> (Stub, TimeInterval) in
            state.requests.append(recorded)
            let stub = state.handler?(self.request, body)
                ?? Stub(status: 500, headers: [:], body: Data())
            return (stub, state.responseDelay)
        }
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
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
            var responseDelay: TimeInterval = 0
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
