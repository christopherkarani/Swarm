// AppleVoiceAdapterTests.swift
// SwarmTests
//
// Apple adapter mapping tests. Does not open the microphone.

import Foundation
@testable import Swarm
import Testing

@Suite("Voice Apple Adapters", .ephemeralDefaultStores)
struct VoiceAppleAdapterTests {
    @Test("asset mapping fails closed unless install is opted in")
    func assetMappingFailsClosed() throws {
        #expect(throws: VoiceError.assetUnavailable(reason: "Speech locale assets are not installed.")) {
            try AppleSpeechAssetMapping.requireInstalled(
                status: .supported,
                localeIdentifier: "en-US",
                installAssetsIfNeeded: false
            )
        }
        try AppleSpeechAssetMapping.requireInstalled(
            status: .installed,
            localeIdentifier: "en-US",
            installAssetsIfNeeded: false
        )
        #expect(throws: VoiceError.unsupportedLocale("zz-ZZ")) {
            try AppleSpeechAssetMapping.requireInstalled(
                status: .unsupported,
                localeIdentifier: "zz-ZZ",
                installAssetsIfNeeded: false
            )
        }
    }

    @Test("denied microphone access maps to notAuthorized")
    func deniedMicrophoneMapsToNotAuthorized() {
        #expect(AppleSpeechAuthorization.deniedReason(granted: true) == nil)
        #expect(
            AppleSpeechAuthorization.deniedReason(granted: false)
                == .notAuthorized(reason: "Microphone access denied.")
        )
    }

    @Test("unsupported locale fails during prepare without starting capture")
    func unsupportedLocaleFailsDuringPrepare() async throws {
        #if canImport(Speech) && canImport(AVFoundation)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            let stt = AppleSpeechToText(
                configuration: VoiceSessionConfiguration(locale: Locale(identifier: "zz-ZZ"))
            )
            do {
                _ = try await stt.prepareForSession()
                Issue.record("expected unsupported or unavailable locale to throw")
            } catch let error as VoiceError {
                switch error {
                case .unsupportedLocale, .assetUnavailable:
                    break
                default:
                    Issue.record("unexpected VoiceError \(error)")
                }
            }
        }
        #endif
    }

    @Test("appleOnDevice is not declared on VoiceSession.swift")
    func factoryLivesOnAppleExtension() throws {
        let sessionSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Swarm/Voice/VoiceSession.swift"),
            encoding: .utf8
        )
        #expect(!sessionSource.contains("appleOnDevice"))
    }
}
