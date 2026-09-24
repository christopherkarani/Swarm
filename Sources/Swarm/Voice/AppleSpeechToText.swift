// AppleSpeechToText.swift
// Swarm Framework
//
// SpeechAnalyzer + SpeechTranscriber adapter.

#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text using `SpeechAnalyzer` and `SpeechTranscriber`.
///
/// Does not download language assets unless `installAssetsIfNeeded` is `true`.
/// Live capture prefers Apple's input-sequence provider when available, then
/// `AVAudioEngine` plus conversion to `SpeechAnalyzer.bestAvailableAudioFormat`.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public actor AppleSpeechToText: SpeechToText {
    private let configuration: VoiceSessionConfiguration
    private var activeStop: (@Sendable () async -> Void)?

    /// Creates an Apple speech-to-text adapter.
    public init(configuration: VoiceSessionConfiguration = .default) {
        self.configuration = configuration
    }

    /// Resolves locale and assets without opening the microphone.
    public func prepareForSession() async throws -> Locale {
        try await AppleSpeechPreparation.prepare(
            locale: configuration.locale,
            installAssetsIfNeeded: configuration.installAssetsIfNeeded
        )
    }

    public nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let session = SessionCoordinator()
            await self.registerStop {
                await session.stop()
            }
            do {
                try await session.run(
                    configuration: self.configuration,
                    continuation: continuation
                )
            } catch let error as VoiceError {
                continuation.finish(throwing: error)
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: VoiceError.speechFailed(reason: String(describing: error)))
            }
            await self.registerStop(nil)
        }
    }

    public func stop() async {
        let stop = activeStop
        activeStop = nil
        await stop?()
    }

    private func registerStop(_ stop: (@Sendable () async -> Void)?) {
        activeStop = stop
    }
}

// MARK: - Preparation (no microphone)

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum AppleSpeechPreparation {
    static func prepare(locale: Locale, installAssetsIfNeeded: Bool) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw VoiceError.assetUnavailable(reason: "SpeechTranscriber is not available on this device.")
        }

        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw VoiceError.unsupportedLocale(locale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: resolved, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        try AppleSpeechAssetMapping.requireInstalled(
            status: AppleSpeechAssetMapping.status(from: status),
            localeIdentifier: resolved.identifier,
            installAssetsIfNeeded: installAssetsIfNeeded
        )

        if status != .installed, installAssetsIfNeeded {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                do {
                    try await request.downloadAndInstall()
                } catch {
                    throw VoiceError.assetUnavailable(reason: error.localizedDescription)
                }
            }
        }

        guard await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) != nil else {
            throw VoiceError.assetUnavailable(reason: "No compatible analyzer audio format.")
        }

        return resolved
    }
}

extension AppleSpeechAssetMapping {
    static func status(from inventory: AssetInventory.Status) -> AppleSpeechAssetStatus {
        switch inventory {
        case .installed:
            .installed
        case .supported:
            .supported
        case .downloading:
            .downloading
        case .unsupported:
            .unsupported
        @unknown default:
            .unknown
        }
    }
}

// MARK: - Capture session

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
private actor SessionCoordinator {
    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var lastText = ""
    private var finished = false

    func run(
        configuration: VoiceSessionConfiguration,
        continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation
    ) async throws {
        let locale = try await AppleSpeechPreparation.prepare(
            locale: configuration.locale,
            installAssetsIfNeeded: configuration.installAssetsIfNeeded
        )
        try await requestMicrophoneAccess()

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError.assetUnavailable(reason: "No compatible analyzer audio format.")
        }

        resultTask = Task {
            await self.pumpResults(
                transcriber: transcriber,
                silence: configuration.endOfUtteranceSilence,
                continuation: continuation
            )
        }

        do {
            if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
                try await startCaptureProvider(analyzer: analyzer, transcriber: transcriber)
            } else {
                try await startEngine(analyzer: analyzer, format: format)
            }
        } catch {
            await stop()
            throw VoiceError.speechFailed(reason: String(describing: error))
        }

        await resultTask?.value
        if !finished {
            continuation.finish()
        }
    }

    func stop() async {
        silenceTask?.cancel()
        silenceTask = nil
        resultTask?.cancel()
        resultTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        finished = true
    }

    private func requestMicrophoneAccess() async throws {
        #if os(macOS)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        #else
        let granted = await AVAudioApplication.requestRecordPermission()
        #endif
        if let error = AppleSpeechAuthorization.deniedReason(granted: granted) {
            throw error
        }
    }

    private func pumpResults(
        transcriber: SpeechTranscriber,
        silence: Duration,
        continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation
    ) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if !text.isEmpty {
                    lastText = text
                }
                continuation.yield(SpeechTranscript(text: text, isFinal: result.isFinal))
                resetSilenceTimer(silence: silence, continuation: continuation)
                if result.isFinal {
                    await finishListen(continuation: continuation, emitFinal: false)
                    return
                }
            }
            await finishListen(continuation: continuation, emitFinal: true)
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: VoiceError.speechFailed(reason: String(describing: error)))
        }
    }

    private func resetSilenceTimer(
        silence: Duration,
        continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation
    ) {
        silenceTask?.cancel()
        silenceTask = Task {
            do {
                try await Task.sleep(for: silence)
            } catch {
                return
            }
            await self.finishListen(continuation: continuation, emitFinal: true)
        }
    }

    private func finishListen(
        continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation,
        emitFinal: Bool
    ) async {
        guard !finished else { return }
        if emitFinal, !lastText.isEmpty {
            continuation.yield(SpeechTranscript(text: lastText, isFinal: true))
        }
        continuation.finish()
        await stop()
    }

    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    private func startCaptureProvider(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber
    ) async throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            throw VoiceError.speechFailed(reason: "No microphone.")
        }
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: mic,
            compatibleWith: [transcriber]
        )
        _ = try await analyzer.analyzeSequence(provider.analyzerInputs)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    private func startEngine(analyzer: SpeechAnalyzer, format: AVAudioFormat) async throws {
        let engine = AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: nativeFormat, to: format) else {
            throw VoiceError.speechFailed(reason: "Unable to convert microphone format.")
        }

        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        try await analyzer.start(inputSequence: inputs)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
            let converted = Self.convert(buffer, converter: converter, format: format)
            if let converted {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }

        #if os(iOS) || os(visionOS)
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        try engine.start()
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let frameCount = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1)) else {
            return nil
        }
        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}
#endif
