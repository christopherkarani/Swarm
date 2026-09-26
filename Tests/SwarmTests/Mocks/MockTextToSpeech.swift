// MockTextToSpeech.swift
// SwarmTests
//
// Recording text-to-speech for VoiceSession tests.

import Foundation
@testable import Swarm

/// Records spoken utterances and optionally hangs until ``stop()``.
public actor MockTextToSpeech: TextToSpeech {
    private let hangUntilStopped: Bool
    private var speakWaiters: [CheckedContinuation<Void, Never>] = []

    /// Utterances that completed ``speak(_:)`` without being interrupted.
    public private(set) var spoken: [String] = []

    /// Number of times ``stop()`` has been called.
    public private(set) var stopCount = 0

    /// Creates a recording synthesizer.
    /// - Parameter hangUntilStopped: When `true`, ``speak(_:)`` waits for ``stop()``.
    public init(hangUntilStopped: Bool = false) {
        self.hangUntilStopped = hangUntilStopped
    }

    public func speak(_ text: String) async throws {
        if hangUntilStopped, speakWaiters.isEmpty, spoken.isEmpty, stopCount == 0 {
            await withCheckedContinuation { continuation in
                speakWaiters.append(continuation)
            }
            return
        }
        spoken.append(text)
    }

    public func stop() async {
        stopCount += 1
        let waiters = speakWaiters
        speakWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
