// VoiceCancellable.swift
// Swarm Framework
//
// Lock-guarded in-flight handle shared by isolated and nonisolated adapter paths.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

extension VoiceCancellable {
    /// Loads `request` as the current unit of work, so ``cancel()`` interrupts it.
    ///
    /// Use this instead of `URLSession.data(for:)` plus `Task.cancel()`. On
    /// Linux, swift-corelibs-foundation runs the `data(for:)` cancellation
    /// handler (which synchronously waits on the session's work queue) while
    /// the Swift runtime holds the task's status lock. If the response is
    /// finishing on that queue at the same moment, resuming the request needs
    /// the same lock and the process deadlocks.
    ///
    /// Here ``cancel()`` resumes the caller with `CancellationError` itself and
    /// cancels the URL task on a background queue, so it never touches
    /// URLSession under the task lock and never blocks on the work queue.
    /// A caller whose task is already cancelled fails before any request.
    func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let call = VoiceDataCall()
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    call.finish(.failure(error))
                } else if let response {
                    call.finish(.success((data ?? Data(), response)))
                } else {
                    call.finish(.failure(URLError(.badServerResponse)))
                }
            }
            call.begin(task: task, continuation: continuation)
            store { call.cancel() }
            if Task.isCancelled {
                call.cancel()
            } else {
                task.resume()
            }
        }
    }
}

/// One in-flight data task whose continuation resumes exactly once.
///
/// Unchecked `Sendable` by lock discipline: every access holds `lock`.
private final class VoiceDataCall: @unchecked Sendable {
    func begin(
        task: URLSessionDataTask,
        continuation: CheckedContinuation<(Data, URLResponse), Error>
    ) {
        lock.withLock {
            self.task = task
            self.continuation = continuation
        }
    }

    /// Resumes the caller with `result` unless it was already resumed.
    func finish(_ result: Result<(Data, URLResponse), Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<(Data, URLResponse), Error>? in
            let current = self.continuation
            self.continuation = nil
            return current
        }
        continuation?.resume(with: result)
    }

    /// Fails the caller with `CancellationError` now; stops the transfer off-thread.
    func cancel() {
        finish(.failure(CancellationError()))
        // `URLSessionTask.cancel()` blocks on the session work queue on Linux.
        DispatchQueue.global(qos: .utility).async {
            self.cancelTransport()
        }
    }

    private func cancelTransport() {
        let task = lock.withLock { () -> URLSessionDataTask? in
            let current = self.task
            self.task = nil
            return current
        }
        task?.cancel()
    }

    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
}
