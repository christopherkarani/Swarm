#if SWARM_INTEGRATIONS
import Foundation

/// Runs blocking system calls (such as `getaddrinfo`) on a dedicated dispatch
/// queue instead of the Swift cooperative thread pool.
///
/// The pool has one thread per core; a slow DNS lookup blocking one of them
/// stalls unrelated tasks. Cancelling the awaiting task resumes it at once
/// with `CancellationError`; the blocking call itself cannot be interrupted,
/// so it finishes in the background and its result is discarded.
internal enum BlockingWorkQueue {
    static let queue = DispatchQueue(label: "com.swarm.web.blocking-work", attributes: .concurrent)

    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let gate = BlockingWorkResumeGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                queue.async {
                    gate.resume(with: Result { try work() })
                }
            }
        } onCancel: {
            gate.resume(with: .failure(CancellationError()))
        }
    }
}

/// Resumes a continuation exactly once, whichever of the work item or the
/// cancellation handler finishes first. Cancellation can run before the
/// continuation is installed, so an early result is held until then.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
private final class BlockingWorkResumeGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var earlyResult: Result<T, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        let early: Result<T, Error>? = lock.withLock {
            if let earlyResult {
                return earlyResult
            }
            self.continuation = continuation
            return nil
        }
        if let early {
            continuation.resume(with: early)
        }
    }

    func resume(with result: Result<T, Error>) {
        let target: CheckedContinuation<T, Error>? = lock.withLock {
            guard !isResolved else { return nil }
            isResolved = true
            guard let continuation else {
                earlyResult = result
                return nil
            }
            self.continuation = nil
            return continuation
        }
        target?.resume(with: result)
    }
}
#endif
