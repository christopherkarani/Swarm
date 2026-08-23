// AgentRunEnvironment.swift
// Swarm Framework
//
// Explicit per-run dependency bundle for agents, replacing process globals.

import Foundation

// MARK: - DefaultMemorySessionTracker

/// Serializes runs that share the package default memory.
///
/// While a run is active for a memory instance, other runs using the same
/// memory with a different session park until the active run finishes; runs
/// reusing the same session proceed without clearing memory.
actor DefaultMemorySessionTracker {
    private var sessionIDs: [ObjectIdentifier: String] = [:]
    private var activeSessionIDs: [ObjectIdentifier: String] = [:]
    private var activeCounts: [ObjectIdentifier: Int] = [:]
    // Waiters are keyed by a per-call UUID so a cancellation can target the
    // exact parked task without disturbing siblings. `endRun()` resumes any
    // remaining waiters with success; cancellation resumes the targeted
    // waiter with `CancellationError` and removes it from the map.
    private var waiters: [ObjectIdentifier: [UUID: CheckedContinuation<Void, Error>]] = [:]

    func beginRun(for key: ObjectIdentifier, sessionID: String) async throws -> Bool {
        while let activeSessionID = activeSessionIDs[key],
              activeSessionID != sessionID
        {
            try Task.checkCancellation()
            try await waitForSessionRelease(key: key)
        }

        // Final cancellation check after exiting the wait loop. Closes the
        // race where `endRun` resumes the continuation just as the parent
        // task is cancelled — without this, the resumed task would proceed
        // to claim the slot and trigger memory-clear side effects.
        try Task.checkCancellation()

        let previous = sessionIDs[key]
        sessionIDs[key] = sessionID
        activeSessionIDs[key] = sessionID
        activeCounts[key, default: 0] += 1
        return previous != sessionID
    }

    func endRun(for key: ObjectIdentifier) {
        let remaining = (activeCounts[key] ?? 1) - 1
        if remaining > 0 {
            activeCounts[key] = remaining
            return
        }

        activeCounts[key] = nil
        activeSessionIDs[key] = nil
        let pendingWaiters = waiters.removeValue(forKey: key) ?? [:]
        for (_, continuation) in pendingWaiters {
            continuation.resume()
        }
    }

    /// Park the calling task until either the active session releases (success)
    /// or the calling task is cancelled (throws `CancellationError`). Without
    /// the cancellation arm, a cancelled task would stay parked until the
    /// holder of the active session calls `endRun()`, then wake up and claim
    /// the slot — performing memory clears and other side effects before the
    /// cancellation surfaces deeper in execution.
    private func waitForSessionRelease(key: ObjectIdentifier) async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[key, default: [:]][waiterID] = continuation
            }
        } onCancel: {
            Task { await self.cancelWaiter(key: key, id: waiterID) }
        }
    }

    private func cancelWaiter(key: ObjectIdentifier, id: UUID) {
        if let continuation = waiters[key]?.removeValue(forKey: id) {
            if waiters[key]?.isEmpty == true {
                waiters[key] = nil
            }
            continuation.resume(throwing: CancellationError())
        }
    }
}

// MARK: - AgentRunEnvironment

/// Per-run dependencies previously held in process state.
///
/// An ``Agent`` resolves its response tracker, default-memory session
/// serializer, and shared configuration source through this value instead of
/// reaching into statics at run time:
///
/// - ``live`` (the default) wires to the framework-wide instances, so agents
///   built through public initializers share dedup and session-serialization
///   state exactly as they did when these were process globals.
/// - A separately constructed environment carries freshly created trackers,
///   giving each agent fully isolated state.
struct AgentRunEnvironment: Sendable {
    // MARK: Dependencies

    /// Tracks previous response IDs per session for conversation continuation.
    let responseTracker: ResponseTracker

    /// Serializes concurrent runs sharing the package default memory.
    let defaultMemorySessionTracker: DefaultMemorySessionTracker

    /// Explicit durable store location for the auto-created default memory.
    ///
    /// `nil` (the default) resolves the package location: the installed
    /// ephemeral root when one is present via
    /// ``SwarmDefaultStoreLocation/installEphemeralRoot(_:)``, and the durable
    /// Application-Support location otherwise.
    let defaultMemoryStoreURL: URL?

    private let defaultProviderLookup: @Sendable () async -> (any InferenceProvider)?
    private let webConfigurationLookup: @Sendable () async -> WebSearchTool.Configuration?

    // MARK: Initialization

    /// Creates an environment.
    ///
    /// Defaults produce fresh trackers and read the globally configured
    /// provider / web-search configuration via ``Swarm/defaultProvider`` and
    /// ``Swarm/webConfiguration``.
    init(
        responseTracker: ResponseTracker = ResponseTracker(),
        defaultMemorySessionTracker: DefaultMemorySessionTracker = DefaultMemorySessionTracker(),
        defaultProvider: @escaping @Sendable () async -> (any InferenceProvider)? = { await Swarm.defaultProvider },
        webConfiguration: @escaping @Sendable () async -> WebSearchTool.Configuration? = { await Swarm.webConfiguration },
        defaultMemoryStoreURL: URL? = nil
    ) {
        self.responseTracker = responseTracker
        self.defaultMemorySessionTracker = defaultMemorySessionTracker
        self.defaultProviderLookup = defaultProvider
        self.webConfigurationLookup = webConfiguration
        self.defaultMemoryStoreURL = defaultMemoryStoreURL
    }

    // MARK: Shared Configuration Source

    /// The globally configured default provider, if any.
    func defaultProvider() async -> (any InferenceProvider)? {
        await defaultProviderLookup()
    }

    /// The globally configured web-search configuration, if any.
    func webConfiguration() async -> WebSearchTool.Configuration? {
        await webConfigurationLookup()
    }

    // MARK: Default Instance

    /// The shared environment backing every agent constructed without an
    /// explicit one. All agents reading from this instance observe the same
    /// tracker state — the observable contract of the former process globals.
    static let live = AgentRunEnvironment()
}
