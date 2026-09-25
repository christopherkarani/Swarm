// AppleVoiceActivityDetector.swift
// Swarm Framework
//
// SpeechDetector adapter for barge-in.

#if canImport(Speech)
import Foundation
import Speech

/// On-device voice-activity detector using `SpeechDetector`.
///
/// Does not start capture by itself. Pair it with a live analyzer input when
/// the host is speaking. Tests should inject ``MockVoiceActivityDetector``.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public actor AppleVoiceActivityDetector: VoiceActivityDetector {
    private var activeStop: (@Sendable () async -> Void)?

    /// Creates an Apple speech-detector adapter.
    public init() {}

    public nonisolated func start() -> AsyncThrowingStream<VoiceActivityEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let detector = SpeechDetector()
            await self.registerStop {
                continuation.finish()
            }
            do {
                for try await result in detector.results {
                    if result.speechDetected {
                        continuation.yield(.speechStarted)
                    } else {
                        continuation.yield(.speechEnded)
                    }
                }
                continuation.finish()
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
#endif
