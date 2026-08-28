// Agent+Cancellation.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

import Foundation

extension Agent {
    /// Registry of in-flight runs keyed by run ID.
    ///
    /// Unlike the single-slot state it replaces, this supports multiple
    /// concurrent runs on one agent value: `cancelAll()` reaches every
    /// in-flight run, while `finish(_:)` removes exactly the run that
    /// completed so finished runs never shadow live ones.
    typealias ActiveRunRegistry = KeyedRunRegistry<UUID>

    /// Cancels every in-flight execution on this agent.
    ///
    /// All runs started through ``run(_:session:observer:)`` or
    /// ``runStructured(_:request:session:observer:)`` that have not finished
    /// yet are cancelled, including runs started concurrently on copies of
    /// this agent value. Earlier releases cancelled only the most recently
    /// registered run; the run registry now tracks every concurrent run by
    /// ID, so cancellation reaches all of them.
    public func cancel() async {
        await activeRuns.cancelAll()
    }

    /// Checks for cancellation and timeout conditions.
    func checkCancellationAndTimeout(startTime: ContinuousClock.Instant) throws {
        try Task.checkCancellation()

        let elapsed = ContinuousClock.now - startTime
        if elapsed > configuration.timeout {
            throw AgentError.timeout(duration: configuration.timeout)
        }
    }

    /// Runs `operation` bounded by the remaining run timeout.
    ///
    /// Delegates to the shared ``withTimeoutRace`` settlement primitive, so
    /// outcomes recorded before the continuation installs are replayed and
    /// worker tasks registered after settlement are cancelled. Owned-loop-gate
    /// deactivation rides on the race's `onSettle` hook: the gate is
    /// deactivated exactly when settlement fails with `CancellationError` or
    /// `AgentError.timeout` (see `shouldDeactivateOwnedLoop`), never on
    /// success or unrelated failures.
    ///
    /// The remaining budget is computed from `startTime` and consumed through
    /// the injected `SwarmClock`, keeping the sleep on the same fake-clock
    /// seam used by resilience code.
    func executeWithinRemainingTimeout<T: Sendable>(
        startTime: ContinuousClock.Instant,
        executionGate: ProviderOwnedLoopGate? = nil,
        clock: any SwarmClock = LiveSwarmClock.live,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let deactivateIfNeeded: @Sendable (Error) -> Void = { error in
            guard Self.shouldDeactivateOwnedLoop(for: error) else { return }
            executionGate?.deactivate()
        }

        do {
            try Task.checkCancellation()
        } catch {
            deactivateIfNeeded(error)
            throw error
        }

        let remaining = configuration.timeout - (ContinuousClock.now - startTime)
        if remaining <= .zero {
            let timeout = AgentError.timeout(duration: configuration.timeout)
            deactivateIfNeeded(timeout)
            throw timeout
        }

        return try await withTimeoutRace(
            timeout: remaining,
            clock: clock,
            timeoutError: AgentError.timeout(duration: configuration.timeout),
            onSettle: { error in
                guard let error else { return }
                deactivateIfNeeded(error)
            },
            operation: operation
        )
    }

    /// Owned-loop gates deactivate only when a run dies by cancellation or
    /// timeout; ordinary inference/tool failures must leave the gate armed.
    static func shouldDeactivateOwnedLoop(for error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if case .timeout = error as? AgentError {
            return true
        }
        return false
    }

    func normalizeCancellation(_ error: Error) -> Error {
        if error is CancellationError {
            return AgentError.cancelled
        }
        if let agentError = error as? AgentError, agentError == .cancelled {
            return agentError
        }
        return error
    }

    func fallbackDiagnosticMessage(for error: Error) -> String {
        let described = String(describing: error)
        if described != String(describing: type(of: error)) {
            return described
        }

        let localized = error.localizedDescription
        if !localized.isEmpty {
            return localized
        }

        return String(describing: type(of: error))
    }
}
