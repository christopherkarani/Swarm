// AppleSpeechMapping.swift
// Swarm Framework
//
// Platform-agnostic error mapping for Apple speech adapters.

import Foundation

enum AppleSpeechAssetStatus: Sendable, Equatable {
    case installed
    case supported
    case downloading
    case unsupported
    case unknown
}

enum AppleSpeechAssetMapping {
    static func requireInstalled(
        status: AppleSpeechAssetStatus,
        localeIdentifier: String,
        installAssetsIfNeeded: Bool
    ) throws {
        switch status {
        case .installed:
            return
        case .unsupported:
            throw VoiceError.unsupportedLocale(localeIdentifier)
        case .supported, .downloading, .unknown:
            if !installAssetsIfNeeded {
                throw VoiceError.assetUnavailable(reason: "Speech locale assets are not installed.")
            }
        }
    }
}

enum AppleSpeechAuthorization {
    static func deniedReason(granted: Bool) -> VoiceError? {
        granted ? nil : VoiceError.notAuthorized(reason: "Microphone access denied.")
    }
}
