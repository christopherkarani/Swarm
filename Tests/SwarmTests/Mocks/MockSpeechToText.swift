// MockSpeechToText.swift
// SwarmTests
//
// Scripted speech-to-text for VoiceSession tests.

import Foundation
@testable import Swarm

/// Yields configured transcripts then finishes, or hangs until ``stop()``.
public actor MockSpeechToText: SpeechToText {
    private let transcripts: [SpeechTranscript]
    private let subsequentStarts: [[SpeechTranscript]]
    private let hangUntilStopped: Bool
    private var startCount = 0
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    /// Number of times ``stop()`` has been called.
    public private(set) var stopCount = 0

    /// Creates a scripted recognizer.
    /// - Parameters:
    ///   - transcripts: Fragments yielded in order from the first ``start()``.
    ///   - subsequentStarts: Batches yielded from later ``start()`` calls.
    ///   - hangUntilStopped: When `true`, the stream waits for ``stop()``.
    public init(
        transcripts: [SpeechTranscript] = [],
        subsequentStarts: [[SpeechTranscript]] = [],
        hangUntilStopped: Bool = false
    ) {
        self.transcripts = transcripts
        self.subsequentStarts = subsequentStarts
        self.hangUntilStopped = hangUntilStopped
    }

    public nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let scripted = await self.nextBatch()
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

    private func nextBatch() -> [SpeechTranscript] {
        let index = startCount
        startCount += 1
        if index == 0 {
            return transcripts
        }
        let subsequentIndex = index - 1
        guard subsequentStarts.indices.contains(subsequentIndex) else {
            return []
        }
        return subsequentStarts[subsequentIndex]
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
