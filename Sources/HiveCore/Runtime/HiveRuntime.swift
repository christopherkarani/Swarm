import Foundation
import Mutex

/// Attempt kinds multiplexed through the shared per-thread enqueue path.
private enum HiveAttemptKind<Schema: HiveSchema>: Sendable {
    case run(input: Schema.Input)
    case resume(interruptID: HiveInterruptID, payload: Schema.ResumePayload)
    case externalWrites(writes: [AnyHiveWrite<Schema>])
}

// MARK: - HiveRuntime

/// Deterministic runtime for executing a compiled graph.
public actor HiveRuntime<Schema: HiveSchema> {
    public init(graph: CompiledHiveGraph<Schema>, environment: HiveEnvironment<Schema>) throws {
        self.graph = graph
        self.environment = environment
        self.environmentSnapshot = environment
        let registry = try HiveSchemaRegistry<Schema>()
        self.registry = registry
        self.initialCache = HiveInitialCache(registry: registry)
        self.storeSupport = HiveStoreSupport(registry: registry)
        self.threadStates = [:]
        self.threadQueues = [:]
    }

    public func run(
        threadID: HiveThreadID,
        input: Schema.Input,
        options: HiveRunOptions
    ) -> HiveRunHandle<Schema> {
        enqueueAttempt(threadID: threadID, options: options, kind: .run(input: input))
    }

    public func resume(
        threadID: HiveThreadID,
        interruptID: HiveInterruptID,
        payload: Schema.ResumePayload,
        options: HiveRunOptions
    ) -> HiveRunHandle<Schema> {
        enqueueAttempt(threadID: threadID, options: options, kind: .resume(interruptID: interruptID, payload: payload))
    }

    public func applyExternalWrites(
        threadID: HiveThreadID,
        writes: [AnyHiveWrite<Schema>],
        options: HiveRunOptions
    ) -> HiveRunHandle<Schema> {
        enqueueAttempt(threadID: threadID, options: options, kind: .externalWrites(writes: writes))
    }

    /// Shared enqueue path for run/resume/applyExternalWrites: validates options
    /// (fail-fast handle on error), chains onto the per-thread serial queue, and
    /// dispatches to the attempt implementation for `kind`.
    private func enqueueAttempt(
        threadID: HiveThreadID,
        options: HiveRunOptions,
        kind: HiveAttemptKind<Schema>
    ) -> HiveRunHandle<Schema> {
        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()
        } catch {
            return makeFailFastHandle(threadID: threadID, options: options, error: error)
        }

        let attemptID = HiveRunAttemptID(UUID())
        let runID = threadStates[threadID]?.runID ?? HiveRunID(UUID())
        let capacity = max(1, options.eventBufferCapacity)
        let streamController = HiveEventStreamController(capacity: capacity)
        let events = streamController.makeStream()

        let previous = threadQueues[threadID]
        let outcome = Task { [weak self] in
            if let previous {
                await previous.value
            }
            guard let self else { throw CancellationError() }
            switch kind {
            case .run(let input):
                return try await self.runAttempt(
                    threadID: threadID,
                    input: input,
                    options: options,
                    runID: runID,
                    attemptID: attemptID,
                    streamController: streamController
                )
            case .resume(let interruptID, let payload):
                return try await self.resumeAttempt(
                    threadID: threadID,
                    interruptID: interruptID,
                    payload: payload,
                    options: options,
                    runID: runID,
                    attemptID: attemptID,
                    streamController: streamController
                )
            case .externalWrites(let writes):
                return try await self.applyExternalWritesAttempt(
                    threadID: threadID,
                    writes: writes,
                    options: options,
                    runID: runID,
                    attemptID: attemptID,
                    streamController: streamController
                )
            }
        }

        threadQueues[threadID] = Task {
            _ = try? await outcome.value
        }

        return HiveRunHandle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome,
            streamController: streamController
        )
    }


    // MARK: - State

    let graph: CompiledHiveGraph<Schema>
    let environment: HiveEnvironment<Schema>
    public nonisolated let environmentSnapshot: HiveEnvironment<Schema>
    let registry: HiveSchemaRegistry<Schema>
    let initialCache: HiveInitialCache<Schema>
    let storeSupport: HiveStoreSupport<Schema>

    var threadStates: [HiveThreadID: ThreadState<Schema>]
    var threadQueues: [HiveThreadID: Task<Void, Never>]
    var forkEventHistory: [HiveEvent] = []

    private func makeFailFastHandle(
        threadID: HiveThreadID,
        options: HiveRunOptions,
        error: Error
    ) -> HiveRunHandle<Schema> {
        let attemptID = HiveRunAttemptID(UUID())
        let runID: HiveRunID
        if let existing = threadStates[threadID] {
            runID = existing.runID
        } else {
            runID = HiveRunID(UUID())
        }
        let capacity = max(1, options.eventBufferCapacity)
        let streamController = HiveEventStreamController(capacity: capacity)
        let events = streamController.makeStream()
        streamController.finish(throwing: error)

        let outcome = Task<HiveRunOutcome<Schema>, Error> {
            throw error
        }

        return HiveRunHandle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome,
            streamController: streamController
        )
    }
}
