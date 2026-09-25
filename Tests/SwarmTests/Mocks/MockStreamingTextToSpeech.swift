// MockStreamingTextToSpeech.swift
// SwarmTests
//
// Recording streaming text-to-speech for VoiceSession tests.

import Foundation
@testable import Swarm

/// Records utterances and yields scripted audio chunks per call.
public actor MockStreamingTextToSpeech: StreamingTextToSpeech {
    private let scriptedChunks: [[Data]]
    private let hangUntilStopped: Bool
    private var callIndex = 0
    private var streamWaiters: [CheckedContinuation<Void, Never>] = []

    /// Utterances passed to `speak` or `streamAudio`, in order.
    public private(set) var spoken: [String] = []

    /// Number of times ``stop()`` has been called.
    public private(set) var stopCount = 0

    /// Creates a recording streaming synthesizer.
    /// - Parameters:
    ///   - chunks: Per-utterance chunk arrays. Calls beyond the scripts yield
    ///     the utterance bytes as a single chunk.
    ///   - hangUntilStopped: When `true`, `streamAudio` waits for ``stop()``
    ///     before emitting, then ends cancelled. Only applies before the
    ///     first `stop()` so replacement turns complete.
    public init(chunks: [[Data]] = [], hangUntilStopped: Bool = false) {
        self.scriptedChunks = chunks
        self.hangUntilStopped = hangUntilStopped
    }

    public func speak(_ text: String) async throws {
        spoken.append(text)
    }

    public nonisolated func streamAudio(_ text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.emit(text: text, continuation: continuation) }
        }
    }

    public func stop() async {
        stopCount += 1
        let waiters = streamWaiters
        streamWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func emit(
        text: String,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async {
        spoken.append(text)
        if hangUntilStopped, stopCount == 0 {
            await withCheckedContinuation { streamWaiters.append($0) }
            continuation.finish(throwing: VoiceError.cancelled)
            return
        }
        let index = callIndex
        callIndex += 1
        if index < scriptedChunks.count {
            for chunk in scriptedChunks[index] {
                continuation.yield(chunk)
            }
        } else {
            continuation.yield(Data(text.utf8))
        }
        continuation.finish()
    }
}
