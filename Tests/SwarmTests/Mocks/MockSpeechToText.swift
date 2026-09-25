// MockSpeechToText.swift
// SwarmTests
//
// Scripted speech-to-text for VoiceSession tests.

import Foundation
@testable import Swarm

/// Yields configured transcripts then finishes, or hangs until ``stop()``.
public actor MockSpeechToText: SpeechToText {
    private let transcripts: [SpeechTranscript]
    private let hangUntilStopped: Bool
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    /// Number of times ``stop()`` has been called.
    public private(set) var stopCount = 0

    /// Creates a scripted recognizer.
    /// - Parameters:
    ///   - transcripts: Fragments yielded in order from ``start()``.
    ///   - hangUntilStopped: When `true`, the stream waits for ``stop()``.
    public init(transcripts: [SpeechTranscript] = [], hangUntilStopped: Bool = false) {
        self.transcripts = transcripts
        self.hangUntilStopped = hangUntilStopped
    }

    public nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let scripted = await self.transcripts
            let shouldHang = await self.hangUntilStopped
            for transcript in scripted {
                continuation.yield(transcript)
            }
            if shouldHang {
                await self.waitUntilStopped()
            }
            continuation.finish()
        }
    }

    public func stop() async {
        stopCount += 1
        let waiters = stopWaiters
        stopWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitUntilStopped() async {
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
        }
    }
}
