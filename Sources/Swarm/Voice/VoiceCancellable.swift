// VoiceCancellable.swift
// Swarm Framework
//
// Lock-guarded in-flight handle shared by isolated and nonisolated adapter paths.

import Foundation

/// Holds one cancellable unit of voice work across isolation boundaries.
///
/// Network adapters create their request task inside nonisolated stream
/// closures but cancel it from isolated `stop()`. The handle erases the
/// task type so every adapter shares one shape.
///
/// Maps task and URL cancellation to ``VoiceError/cancelled``.
///
/// URLSession reports cancellation as `URLError(.cancelled)`, not
/// `CancellationError`; voice adapters normalize both.
enum VoiceCancellation {
    static func error(for error: Error) -> VoiceError? {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        return nil
    }
}

/// Unchecked `Sendable` by lock discipline: every access holds `lock`.
final class VoiceCancellable: @unchecked Sendable {
    /// Stores the canceller for the current unit of work, replacing any prior one.
    func store(_ canceller: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.canceller = canceller
        }
    }

    /// Runs and clears the stored canceller, if any.
    func cancel() {
        let canceller = lock.withLock { () -> (@Sendable () -> Void)? in
            let current = self.canceller
            self.canceller = nil
            return current
        }
        canceller?()
    }

    private let lock = NSLock()
    private var canceller: (@Sendable () -> Void)?
}
