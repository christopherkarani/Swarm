import Foundation

extension HiveRuntime {
    func runAttempt(
        threadID: HiveThreadID,
        input: Schema.Input,
        options: HiveRunOptions,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) async throws -> HiveRunOutcome<Schema> {
        let emitter = HiveEventEmitter(
            runID: runID,
            attemptID: attemptID,
            streamController: streamController
        )

        emitter.emit(kind: .runStarted(threadID: threadID), stepIndex: nil, taskOrdinal: nil)

        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()

            var state = try await resolveBaselineState(
                threadID: threadID,
                debugPayloads: options.debugPayloads,
                emitter: emitter
            )
            rebindLoadedStateRunIDIfNeeded(state: &state, to: runID, threadID: threadID)

            let inputContext = HiveInputContext(threadID: threadID, runID: state.runID, stepIndex: state.stepIndex)
            let inputWrites = try Schema.inputWrites(input, inputContext: inputContext)

            if let interruption = state.interruption {
                // A pending interrupt can only be superseded by explicit new input writes.
                // If there is no new input payload, fail closed and keep interruption pending.
                guard inputWrites.isEmpty == false else {
                    throw HiveRuntimeError.interruptPending(interruptID: interruption.id)
                }

                state.interruption = nil
                state.frontier = []
                state.joinSeenParents = [:]
            }

            if state.frontier.isEmpty {
                state.frontier = graph.start.map {
                    HiveFrontierTask(seed: HiveTaskSeed(nodeID: $0), provenance: .graph, isJoinSeed: false)
                }
            }

            if !inputWrites.isEmpty {
                var global = state.global
                let writtenChannels = try applyInputWrites(inputWrites, to: &global)
                state.global = global
                state.updatedChannelsLastCommit = writtenChannels
                if !writtenChannels.isEmpty {
                    for channelID in writtenChannels {
                        let currentVersion = state.channelVersionsByChannelID[channelID] ?? 0
                        state.channelVersionsByChannelID[channelID] = currentVersion &+ 1
                    }
                }
            }
            threadStates[threadID] = state

            return try await executeRunLoop(
                initialState: state,
                threadID: threadID,
                options: options,
                attemptID: attemptID,
                emitter: emitter,
                streamController: streamController
            )
        } catch let cancellation as RuntimeCancellation {
            throw cancellation
        } catch {
            streamController.finish(throwing: error)
            throw error
        }
    }

    func resumeAttempt(
        threadID: HiveThreadID,
        interruptID: HiveInterruptID,
        payload: Schema.ResumePayload,
        options: HiveRunOptions,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) async throws -> HiveRunOutcome<Schema> {
        let emitter = HiveEventEmitter(
            runID: runID,
            attemptID: attemptID,
            streamController: streamController
        )

        emitter.emit(kind: .runStarted(threadID: threadID), stepIndex: nil, taskOrdinal: nil)

        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()

            var state = try await loadCheckpointStateForResume(
                threadID: threadID,
                interruptID: interruptID,
                debugPayloads: options.debugPayloads,
                emitter: emitter
            )
            rebindLoadedStateRunIDIfNeeded(state: &state, to: runID, threadID: threadID)

            emitter.emit(kind: .runResumed(interruptID: interruptID), stepIndex: nil, taskOrdinal: nil)

            let resume = HiveResume<Schema>(interruptID: interruptID, payload: payload)

            return try await executeRunLoop(
                initialState: state,
                threadID: threadID,
                options: options,
                attemptID: attemptID,
                emitter: emitter,
                streamController: streamController,
                firstStepResume: resume,
                clearInterruptionAfterFirstStep: true
            )
        } catch let cancellation as RuntimeCancellation {
            throw cancellation
        } catch {
            streamController.finish(throwing: error)
            throw error
        }
    }

    /// Shared run-loop extracted from `runAttempt` and `resumeAttempt`.
    ///
    /// Executes supersteps in a `while true` loop until the graph finishes, is interrupted,
    /// runs out of steps, or is cancelled. Handles `RuntimeCancellation` internally (returns
    /// `.cancelled`); all other errors propagate to the caller.
    ///
    /// - Parameters:
    ///   - initialState: Thread state with frontier already populated.
    ///   - threadID: The thread ID used for `threadStates[threadID] = state`.
    ///   - options: Run options (maxSteps, checkpoint policy, streaming mode, etc.).
    ///   - attemptID: Current attempt ID passed through to `executeStep`.
    ///   - emitter: Event emitter for lifecycle events.
    ///   - streamController: Stream controller to finish on terminal outcomes.
    ///   - firstStepResume: If non-nil, passed to `executeStep` only on the first iteration
    ///     (used by `resumeAttempt` to deliver the resume payload).
    ///   - clearInterruptionAfterFirstStep: If `true`, clears `nextState.interruption` after
    ///     the first step when no new interrupt was selected (used by `resumeAttempt`).
    private func executeRunLoop(
        initialState: ThreadState<Schema>,
        threadID: HiveThreadID,
        options: HiveRunOptions,
        attemptID: HiveRunAttemptID,
        emitter: HiveEventEmitter,
        streamController: HiveEventStreamController,
        firstStepResume: HiveResume<Schema>? = nil,
        clearInterruptionAfterFirstStep: Bool = false
    ) async throws -> HiveRunOutcome<Schema> {
        var state = initialState
        var stepsExecutedThisAttempt = 0
        var firstStepDone = false

        do {
            while true {
                if Task.isCancelled {
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(
                        kind: .runCancelled(cause: .explicitRequest),
                        stepIndex: nil,
                        taskOrdinal: nil
                    )
                    streamController.finish()
                    return .cancelled(output: output, checkpointID: state.latestCheckpointID)
                }

                if state.frontier.isEmpty {
                    if !state.deferredFrontier.isEmpty {
                        state.frontier = state.deferredFrontier
                        state.deferredFrontier = []
                        threadStates[threadID] = state
                        continue
                    }
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .finished(output: output, checkpointID: state.latestCheckpointID)
                }

                if stepsExecutedThisAttempt == options.maxSteps {
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .outOfSteps(maxSteps: options.maxSteps, output: output, checkpointID: state.latestCheckpointID)
                }

                let stepOutcome = try await executeStep(
                    state: state,
                    threadID: threadID,
                    attemptID: attemptID,
                    options: options,
                    emitter: emitter,
                    resume: !firstStepDone ? firstStepResume : nil
                )

                var nextState = stepOutcome.nextState

                // For resumeAttempt: clear the pending interruption after the first successfully
                // committed resumed step, unless a new interrupt is selected in that same commit.
                if clearInterruptionAfterFirstStep && !firstStepDone {
                    if stepOutcome.selectedInterrupt == nil {
                        nextState.interruption = nil
                    }
                }
                firstStepDone = true

                if let checkpoint = stepOutcome.checkpointToSave {
                    guard let store = environment.checkpointStore else {
                        throw HiveRuntimeError.checkpointStoreMissing
                    }
                    try await saveCheckpoint(checkpoint, to: store)
                    nextState.latestCheckpointID = checkpoint.id
                }

                state = nextState
                threadStates[threadID] = nextState
                stepsExecutedThisAttempt += 1

                if !stepOutcome.writtenGlobalChannels.isEmpty {
                    for channelID in stepOutcome.writtenGlobalChannels {
                        let payloadHash = try payloadHash(for: channelID, in: state.global)
                        emitter.emit(
                            kind: .writeApplied(channelID: channelID, payloadHash: payloadHash),
                            stepIndex: state.stepIndex - 1,
                            taskOrdinal: nil,
                            metadata: try writeAppliedMetadata(
                                for: channelID,
                                in: state.global,
                                debugPayloads: options.debugPayloads
                            )
                        )
                    }
                }

                if stepOutcome.dropped.droppedDebugEvents > 0 {
                    emitter.emit(
                        kind: .streamBackpressure(droppedDebugEvents: stepOutcome.dropped.droppedDebugEvents),
                        stepIndex: state.stepIndex - 1,
                        taskOrdinal: nil
                    )
                }

                if let checkpoint = stepOutcome.checkpointToSave {
                    emitter.emit(
                        kind: .checkpointSaved(checkpointID: checkpoint.id),
                        stepIndex: state.stepIndex - 1,
                        taskOrdinal: nil
                    )
                }

                try emitStreamingEvents(
                    mode: options.streamingMode,
                    state: state,
                    writtenChannels: stepOutcome.writtenGlobalChannels,
                    debugPayloads: options.debugPayloads,
                    stepIndex: state.stepIndex - 1,
                    emitter: emitter
                )

                emitter.emit(
                    kind: .stepFinished(stepIndex: state.stepIndex - 1, nextFrontierCount: state.frontier.count),
                    stepIndex: state.stepIndex - 1,
                    taskOrdinal: nil
                )

                if let interrupt = stepOutcome.selectedInterrupt {
                    let checkpointID = stepOutcome.checkpointToSave?.id ?? state.latestCheckpointID
                    guard let checkpointID else {
                        throw HiveRuntimeError.internalInvariantViolation(
                            "Interrupted outcome requires a checkpoint ID."
                        )
                    }
                    emitter.emit(kind: .runInterrupted(interruptID: interrupt.id), stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .interrupted(interruption: HiveInterruption(interrupt: interrupt, checkpointID: checkpointID))
                }

                if state.frontier.isEmpty && state.deferredFrontier.isEmpty {
                    let output = try buildOutput(options: options, state: state)
                    emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
                    streamController.finish()
                    return .finished(output: output, checkpointID: state.latestCheckpointID)
                }

                // Give the cancellation flag a fair observation point between committed steps.
                await Task.yield()
            }
        } catch let cancellation as RuntimeCancellation {
            guard let state = threadStates[threadID] else {
                throw cancellation
            }
            let output = try buildOutput(options: options, state: state)
            emitter.emit(
                kind: .runCancelled(cause: cancellation.eventCause),
                stepIndex: nil,
                taskOrdinal: nil
            )
            streamController.finish()
            return .cancelled(output: output, checkpointID: state.latestCheckpointID)
        }
    }

    func applyExternalWritesAttempt(
        threadID: HiveThreadID,
        writes: [AnyHiveWrite<Schema>],
        options: HiveRunOptions,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        streamController: HiveEventStreamController
    ) async throws -> HiveRunOutcome<Schema> {
        let emitter = HiveEventEmitter(
            runID: runID,
            attemptID: attemptID,
            streamController: streamController
        )
        var cancellationState: ThreadState<Schema>? = threadStates[threadID]

        emitter.emit(kind: .runStarted(threadID: threadID), stepIndex: nil, taskOrdinal: nil)

        do {
            try validateRunOptions(options)
            try validateRetryPolicies()
            try validateRequiredCodecs()

            var state = try await resolveBaselineState(
                threadID: threadID,
                debugPayloads: options.debugPayloads,
                emitter: emitter
            )
            rebindLoadedStateRunIDIfNeeded(state: &state, to: runID, threadID: threadID)
            cancellationState = state
            if let interruption = state.interruption {
                throw HiveRuntimeError.interruptPending(interruptID: interruption.id)
            }

            let stepIndex = state.stepIndex
            emitter.emit(kind: .stepStarted(stepIndex: stepIndex, frontierCount: 0), stepIndex: stepIndex, taskOrdinal: nil)

            var postGlobal = state.global
            let writtenChannels = try applyExternalWrites(writes, to: &postGlobal)

            var nextState = state
            nextState.stepIndex += 1
            nextState.global = postGlobal
            // Frontier and join barriers remain unchanged.
            nextState.updatedChannelsLastCommit = writtenChannels
            if !writtenChannels.isEmpty {
                for channelID in writtenChannels {
                    let currentVersion = nextState.channelVersionsByChannelID[channelID] ?? 0
                    nextState.channelVersionsByChannelID[channelID] = currentVersion &+ 1
                }
            }

            let checkpointToSave: HiveCheckpoint<Schema>?
            if environment.checkpointStore != nil {
                checkpointToSave = try makeCheckpoint(threadID: threadID, state: nextState, debugPayloads: options.debugPayloads)
            } else {
                checkpointToSave = nil
            }

            if let checkpointToSave {
                guard let store = environment.checkpointStore else {
                    throw HiveRuntimeError.checkpointStoreMissing
                }
                try await saveCheckpoint(checkpointToSave, to: store)
                nextState.latestCheckpointID = checkpointToSave.id
            }

            state = nextState
            threadStates[threadID] = nextState

            if !writtenChannels.isEmpty {
                for channelID in writtenChannels {
                    let payloadHash = try payloadHash(for: channelID, in: state.global)
                    emitter.emit(
                        kind: .writeApplied(channelID: channelID, payloadHash: payloadHash),
                        stepIndex: stepIndex,
                        taskOrdinal: nil,
                        metadata: try writeAppliedMetadata(
                            for: channelID,
                            in: state.global,
                            debugPayloads: options.debugPayloads
                        )
                    )
                }
            }

            if let checkpointToSave {
                emitter.emit(
                    kind: .checkpointSaved(checkpointID: checkpointToSave.id),
                    stepIndex: stepIndex,
                    taskOrdinal: nil
                )
            }

            try emitStreamingEvents(
                mode: options.streamingMode,
                state: state,
                writtenChannels: writtenChannels,
                debugPayloads: options.debugPayloads,
                stepIndex: stepIndex,
                emitter: emitter
            )

            emitter.emit(
                kind: .stepFinished(stepIndex: stepIndex, nextFrontierCount: state.frontier.count),
                stepIndex: stepIndex,
                taskOrdinal: nil
            )

            let output = try buildOutput(options: options, state: state)
            emitter.emit(kind: .runFinished, stepIndex: nil, taskOrdinal: nil)
            streamController.finish()
            return .finished(output: output, checkpointID: state.latestCheckpointID)
        } catch let cancellation as RuntimeCancellation {
            guard let state = cancellationState ?? threadStates[threadID] else {
                throw cancellation
            }
            let output = try buildOutput(options: options, state: state)
            emitter.emit(
                kind: .runCancelled(cause: cancellation.eventCause),
                stepIndex: nil,
                taskOrdinal: nil
            )
            streamController.finish()
            return .cancelled(output: output, checkpointID: state.latestCheckpointID)
        } catch {
            streamController.finish(throwing: error)
            throw error
        }
    }

    /// Internal sentinel used to represent runtime-observed cancellation without treating arbitrary user-thrown
    /// `CancellationError` values as cancellation.
    enum RuntimeCancellation: Error, Sendable {
        case checkpointPersistenceRace
        case executionObserved

        var eventCause: HiveRunCancellationCause {
            switch self {
            case .checkpointPersistenceRace:
                return .checkpointPersistenceRace
            case .executionObserved:
                return .executionObserved
            }
        }
    }

    func saveCheckpoint(
        _ checkpoint: HiveCheckpoint<Schema>,
        to store: AnyHiveCheckpointStore<Schema>
    ) async throws {
        do {
            try await store.save(checkpoint)
        } catch is CancellationError {
            throw RuntimeCancellation.checkpointPersistenceRace
        }
    }

    /// Ensures loaded checkpoint state uses the active run handle's run ID.
    /// This keeps handle/event IDs and newly persisted checkpoints in sync on cold-start restores.
    private func rebindLoadedStateRunIDIfNeeded(
        state: inout ThreadState<Schema>,
        to runID: HiveRunID,
        threadID: HiveThreadID
    ) {
        guard state.runID != runID else { return }
        state.runID = runID
        threadStates[threadID] = state
    }
}
