// VoiceFixtureTranscriptionTests.swift
// SwarmTests
//
// Darwin fixture WAV → SpeechAnalyzer. No microphone.

#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Foundation
import Speech
@testable import Swarm
import Testing

@Suite("Voice Fixture Transcription")
struct VoiceFixtureTranscriptionTests {
    @Test("fixture WAV reaches SpeechAnalyzer or skips when assets are missing")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    func fixtureWAVReachesAnalyzerOrSkips() async throws {
        guard SpeechTranscriber.isAvailable else {
            Issue.record("SpeechTranscriber unavailable; skipping fixture transcription.")
            return
        }

        let locale: Locale
        do {
            locale = try await AppleSpeechPreparation.prepare(
                locale: .current,
                installAssetsIfNeeded: false
            )
        } catch let error as VoiceError {
            switch error {
            case .assetUnavailable, .unsupportedLocale:
                return
            default:
                throw error
            }
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            return
        }

        let wav = Self.minimalWAV()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-voice-fixture-\(UUID().uuidString).wav")
        try wav.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputs)

        if let buffer = Self.pcmBuffer(from: wav, format: format) {
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    private static func minimalWAV(sampleRate: Int = 16_000, frames: Int = 160) -> Data {
        let dataSize = frames * 2
        var data = Data()
        func appendASCII(_ text: String) {
            data.append(contentsOf: text.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            var value = value.littleEndian
            data.append(Data(bytes: &value, count: 2))
        }
        func appendUInt32(_ value: UInt32) {
            var value = value.littleEndian
            data.append(Data(bytes: &value, count: 4))
        }
        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        data.append(Data(repeating: 0, count: dataSize))
        return data
    }

    private static func pcmBuffer(from wav: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let header = 44
        guard wav.count > header else { return nil }
        let pcm = wav.subdata(in: header ..< wav.count)
        let frames = AVAudioFrameCount(pcm.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1)) else {
            return nil
        }
        buffer.frameLength = min(frames, buffer.frameCapacity)
        guard format.commonFormat == .pcmFormatInt16, let channel = buffer.int16ChannelData?.pointee else {
            return buffer
        }
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let count = min(Int(buffer.frameLength), samples.count)
            for index in 0 ..< count {
                channel[index] = samples[index]
            }
        }
        return buffer
    }
}
#endif
