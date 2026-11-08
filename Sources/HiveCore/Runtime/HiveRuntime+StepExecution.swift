import Foundation

extension HiveRuntime {
    func executeStep(
        state: ThreadState<Schema>,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        options: HiveRunOptions,
        emitter: HiveEventEmitter,
        resume: HiveResume<Schema>?
    ) async throws -> StepOutcome<Schema> {
        var state = state
        let stepIndex = state.stepIndex
        guard UInt32(exactly: stepIndex) != nil else {
            throw HiveRuntimeError.stepIndexOutOfRange(stepIndex: stepIndex)
        }

        let frontier = state.frontier
        let tasks = try buildTasks(
            frontier: frontier,
            runID: state.runID,
            stepIndex: stepIndex,
            debugPayloads: options.debugPayloads
        )

        snapshotVersionsSeenForStepStart(tasks: tasks, state: &state)

        emitter.emit(
            kind: .stepStarted(stepIndex: stepIndex, frontierCount: tasks.count),
            stepIndex: stepIndex,
            taskOrdinal: nil
        )

        for task in tasks {
            emitter.emit(
                kind: .taskStarted(node: task.nodeID, taskID: task.id),
                stepIndex: stepIndex,
                taskOrdinal: task.ordinal
            )
        }

        if Task.isCancelled {
            for task in tasks {
                emitter.emit(
                    kind: .taskFailed(
                        node: task.nodeID,
                        taskID: task.id,
                        errorDescription: HiveErrorDescription.describe(CancellationError(), debugPayloads: options.debugPayloads)
                    ),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            }
            throw RuntimeCancellation.executionObserved
        }

        let droppedCounter = HiveDroppedEventCounter()

        // Cache lookup: skip execution for tasks with a cache hit.
        let cacheNowNs = DispatchTime.now().uptimeNanoseconds
        let cachePreStoreView = HiveStoreView(
            global: state.global,
            taskLocal: HiveTaskLocalStore(registry: registry),
            initialCache: initialCache,
            registry: registry
        )
        var cachedResultsByTaskIndex: [Int: HiveNodeOutput<Schema>] = [:]
        for (index, task) in tasks.enumerated() {
            guard let node = graph.nodesByID[task.nodeID],
                  let cachePolicy = node.cachePolicy
            else { continue }
            // Compute cache key — log failures instead of silently disabling caching.
            let cacheKey: String
            do {
                cacheKey = try cachePolicy.keyProvider.cacheKey(forNode: task.nodeID, store: cachePreStoreView)
            } catch {
                environment.logger.debug(
                    "Cache key computation failed for node \(task.nodeID.rawValue): \(error)",
                    metadata: [:]
                )
                continue
            }
            guard var nodeCache = state.nodeCaches[task.nodeID] else { continue }
            let cachedOutput = nodeCache.lookup(key: cacheKey, policy: cachePolicy, nowNanoseconds: cacheNowNs)
            // Always write back: persists LRU order update AND expired-entry removal to state.
            // Without this writeback, HiveNodeCache is a value type whose mutations inside
            // lookup() are silently discarded, breaking LRU eviction ordering.
            state.nodeCaches[task.nodeID] = nodeCache
            guard let cachedOutput else { continue }
            cachedResultsByTaskIndex[index] = cachedOutput
        }

        // Only execute tasks that were not cache hits.
        let uncachedIndices = tasks.indices.filter { cachedResultsByTaskIndex[$0] == nil }
        let uncachedTasks = uncachedIndices.map { tasks[$0] }

        let executionResults = await Self.executeTasks(
            tasks: uncachedTasks,
            options: options,
            stepIndex: stepIndex,
            threadID: threadID,
            attemptID: attemptID,
            runID: state.runID,
            graph: graph,
            environment: environment,
            registry: registry,
            initialCache: initialCache,
            preStepGlobal: state.global,
            resume: resume,
            emitter: emitter,
            droppedCounter: droppedCounter
        )

        // Merge cached and fresh results back into a full-sized array.
        var results = Array(repeating: TaskExecutionResult<Schema>.empty, count: tasks.count)
        for (resultIndex, taskIndex) in uncachedIndices.enumerated() {
            results[taskIndex] = executionResults[resultIndex]
        }
        for (taskIndex, cachedOutput) in cachedResultsByTaskIndex {
            results[taskIndex] = TaskExecutionResult(
                output: cachedOutput,
                error: nil,
                streamEvents: nil,
                streamDrops: HiveDroppedEventCounts()
            )
        }

        if Task.isCancelled || results.contains(where: { $0.error is RuntimeCancellation }) {
            if options.deterministicStreamBuffering == false {
                // Live stream events already emitted (if any). Ensure determinism for task failure surface.
            }

            for task in tasks {
                emitter.emit(
                    kind: .taskFailed(
                        node: task.nodeID,
                        taskID: task.id,
                        errorDescription: HiveErrorDescription.describe(CancellationError(), debugPayloads: options.debugPayloads)
                    ),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            }
            throw RuntimeCancellation.executionObserved
        }

        var dropped = droppedCounter.snapshot()
        if options.deterministicStreamBuffering {
            for result in results {
                dropped.droppedDebugEvents += result.streamDrops.droppedDebugEvents
            }

            for result in results {
                guard let events = result.streamEvents else { continue }
                for event in events {
                    let enqueueResult = emitter.emit(
                        kind: event.kind,
                        stepIndex: stepIndex,
                        taskOrdinal: event.taskOrdinal,
                        metadata: event.metadata,
                        treatAsNonDroppable: true
                    )
                    dropped.record(enqueueResult)
                }
            }
        }

        var firstError: Error?
        for (index, result) in results.enumerated() {
            let task = tasks[index]
            if let error = result.error {
                if firstError == nil {
                    firstError = error
                }
                emitter.emit(
                    kind: .taskFailed(
                        node: task.nodeID,
                        taskID: task.id,
                        errorDescription: HiveErrorDescription.describe(error, debugPayloads: options.debugPayloads)
                    ),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            } else {
                emitter.emit(
                    kind: .taskFinished(node: task.nodeID, taskID: task.id),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal
                )
            }
        }

        if let firstError {
            throw firstError
        }

        var outputs: [HiveNodeOutput<Schema>] = []
        outputs.reserveCapacity(results.count)
        for result in results {
            guard let output = result.output else {
                throw HiveRuntimeError.internalInvariantViolation(
                    "Task result missing output without error."
                )
            }
            outputs.append(output)
        }

        // Cache: store new outputs for nodes with a cache policy.
        var updatedNodeCaches = state.nodeCaches
        let storeNowNs = DispatchTime.now().uptimeNanoseconds
        for (index, output) in outputs.enumerated() {
            let task = tasks[index]
            guard let node = graph.nodesByID[task.nodeID],
                  let cachePolicy = node.cachePolicy,
                  let cacheKey = try? cachePolicy.keyProvider.cacheKey(forNode: task.nodeID, store: cachePreStoreView)
            else { continue }
            var nodeCache = updatedNodeCaches[task.nodeID] ?? HiveNodeCache()
            nodeCache.store(key: cacheKey, output: output, policy: cachePolicy, nowNanoseconds: storeNowNs)
            updatedNodeCaches[task.nodeID] = nodeCache
        }

        let commitResult = try commitStep(
            state: state,
            tasks: tasks,
            outputs: outputs,
            options: options
        )

        var nextState = state
        nextState.stepIndex += 1
        nextState.global = commitResult.global
        nextState.joinSeenParents = commitResult.joinSeenParents
        nextState.updatedChannelsLastCommit = commitResult.writtenGlobalChannels
        nextState.nodeCaches = updatedNodeCaches
        if !commitResult.writtenGlobalChannels.isEmpty {
            for channelID in commitResult.writtenGlobalChannels {
                let current = nextState.channelVersionsByChannelID[channelID] ?? 0
                nextState.channelVersionsByChannelID[channelID] = current &+ 1
            }
        }
        nextState.frontier = filterFrontierForTriggers(
            commitResult.frontier,
            channelVersionsByChannelID: nextState.channelVersionsByChannelID,
            versionsSeenByNodeID: nextState.versionsSeenByNodeID
        )
        nextState.deferredFrontier = state.deferredFrontier + commitResult.deferredFrontier

        let selectedInterrupt = try selectInterrupt(tasks: tasks, outputs: outputs)
        // A step that delivered a resume payload resolves the pending interrupt.
        // Clear it before building this step's checkpoint; otherwise a resumed
        // step that ends the run persists a stale interruption that can be
        // resumed (and its decision re-applied) again.
        if resume != nil, selectedInterrupt == nil {
            nextState.interruption = nil
        }
        var checkpointToSave: HiveCheckpoint<Schema>?
        let shouldSaveForPolicy: Bool
        switch options.checkpointPolicy {
        case .disabled:
            shouldSaveForPolicy = false
        case .everyStep:
            shouldSaveForPolicy = true
        case .every(let steps):
            shouldSaveForPolicy = steps > 0 && (nextState.stepIndex % steps == 0)
        case .onInterrupt:
            shouldSaveForPolicy = selectedInterrupt != nil
        }

        let shouldSave = shouldSaveForPolicy || selectedInterrupt != nil
        if shouldSave {
            // Commit-time enforcement: checkpoint boundaries require checkpoint store.
            guard environment.checkpointStore != nil else {
                throw HiveRuntimeError.checkpointStoreMissing
            }
            if let selectedInterrupt {
                nextState.interruption = selectedInterrupt
            }
            checkpointToSave = try makeCheckpoint(
                threadID: threadID,
                state: nextState,
                debugPayloads: options.debugPayloads
            )
        }

        return StepOutcome(
            nextState: nextState,
            writtenGlobalChannels: commitResult.writtenGlobalChannels,
            dropped: dropped,
            selectedInterrupt: selectedInterrupt,
            checkpointToSave: checkpointToSave
        )
    }

    private func buildTasks(
        frontier: [HiveFrontierTask<Schema>],
        runID: HiveRunID,
        stepIndex: Int,
        debugPayloads: Bool
    ) throws -> [HiveTask<Schema>] {
        var tasks: [HiveTask<Schema>] = []
        tasks.reserveCapacity(frontier.count)

        for (ordinal, entry) in frontier.enumerated() {
            guard UInt32(exactly: ordinal) != nil else {
                throw HiveRuntimeError.taskOrdinalOutOfRange(ordinal: ordinal)
            }
            let fingerprint = try HiveTaskLocalFingerprint.digest(
                registry: registry,
                initialCache: initialCache,
                overlay: entry.seed.local,
                debugPayloads: debugPayloads
            )
            let taskID = try makeTaskID(
                runID: runID,
                stepIndex: stepIndex,
                nodeID: entry.seed.nodeID,
                ordinal: ordinal,
                localFingerprint: fingerprint
            )
            tasks.append(
                HiveTask(
                    id: taskID,
                    ordinal: ordinal,
                    provenance: entry.provenance,
                    nodeID: entry.seed.nodeID,
                    local: entry.seed.local
                )
            )
        }
        return tasks
    }

    private func snapshotVersionsSeenForStepStart(
        tasks: [HiveTask<Schema>],
        state: inout ThreadState<Schema>
    ) {
        if tasks.isEmpty { return }

        for task in tasks {
            guard let node = graph.nodesByID[task.nodeID] else { continue }
            let channels = node.runWhen.triggerChannels
            if channels.isEmpty { continue }

            var perChannel = state.versionsSeenByNodeID[task.nodeID] ?? [:]
            perChannel.reserveCapacity(max(perChannel.count, channels.count))
            for channelID in channels {
                perChannel[channelID] = state.channelVersionsByChannelID[channelID] ?? 0
            }
            state.versionsSeenByNodeID[task.nodeID] = perChannel
        }
    }

    private func filterFrontierForTriggers(
        _ frontier: [HiveFrontierTask<Schema>],
        channelVersionsByChannelID: [HiveChannelID: UInt64],
        versionsSeenByNodeID: [HiveNodeID: [HiveChannelID: UInt64]]
    ) -> [HiveFrontierTask<Schema>] {
        if frontier.isEmpty { return [] }

        func channelChanged(
            channelID: HiveChannelID,
            seen: [HiveChannelID: UInt64]?
        ) -> Bool {
            let current = channelVersionsByChannelID[channelID] ?? 0
            guard let seenValue = seen?[channelID] else { return true }
            return current > seenValue
        }

        var filtered: [HiveFrontierTask<Schema>] = []
        filtered.reserveCapacity(frontier.count)

        for entry in frontier {
            if entry.isJoinSeed {
                filtered.append(entry)
                continue
            }

            guard let node = graph.nodesByID[entry.seed.nodeID] else {
                filtered.append(entry)
                continue
            }

            switch node.runWhen.normalized {
            case .always:
                filtered.append(entry)
            case .anyOf(let channels):
                if channels.isEmpty {
                    filtered.append(entry)
                    continue
                }
                let seen = versionsSeenByNodeID[entry.seed.nodeID]
                if channels.contains(where: { channelChanged(channelID: $0, seen: seen) }) {
                    filtered.append(entry)
                }
            case .allOf(let channels):
                if channels.isEmpty {
                    filtered.append(entry)
                    continue
                }
                let seen = versionsSeenByNodeID[entry.seed.nodeID]
                if channels.allSatisfy({ channelChanged(channelID: $0, seen: seen) }) {
                    filtered.append(entry)
                }
            }
        }

        return filtered
    }

    private static func executeTasks(
        tasks: [HiveTask<Schema>],
        options: HiveRunOptions,
        stepIndex: Int,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        runID: HiveRunID,
        graph: CompiledHiveGraph<Schema>,
        environment: HiveEnvironment<Schema>,
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        preStepGlobal: HiveGlobalStore<Schema>,
        resume: HiveResume<Schema>?,
        emitter: HiveEventEmitter,
        droppedCounter: HiveDroppedEventCounter
    ) async -> [TaskExecutionResult<Schema>] {
        if tasks.isEmpty { return [] }
        let concurrency = max(1, min(options.maxConcurrentTasks, tasks.count))
        var results = Array(repeating: TaskExecutionResult<Schema>.empty, count: tasks.count)

        await withTaskGroup(of: (Int, TaskExecutionResult<Schema>).self) { group in
            var nextIndex = 0
            var cancellationObserved = false
            func addTask(_ index: Int) {
                let task = tasks[index]
                group.addTask {
                    let result = await Self.executeTask(
                        task: task,
                        stepIndex: stepIndex,
                        threadID: threadID,
                        attemptID: attemptID,
                        runID: runID,
                        options: options,
                        graph: graph,
                        environment: environment,
                        registry: registry,
                        initialCache: initialCache,
                        preStepGlobal: preStepGlobal,
                        resume: resume,
                        emitter: emitter,
                        droppedCounter: droppedCounter
                    )
                    return (index, result)
                }
            }

            while nextIndex < concurrency {
                addTask(nextIndex)
                nextIndex += 1
            }

            while let (index, result) = await group.next() {
                results[index] = result

                if cancellationObserved == false {
                    // If any task reports cancellation (including CancellationError during retry-backoff sleep),
                    // treat the step as cancelled and cancel remaining in-flight tasks.
                    if Task.isCancelled || (result.error is RuntimeCancellation) {
                        cancellationObserved = true
                        group.cancelAll()
                    }
                }

                if cancellationObserved == false, nextIndex < tasks.count {
                    addTask(nextIndex)
                    nextIndex += 1
                }
            }
        }

        return results
    }

    private static func executeTask(
        task: HiveTask<Schema>,
        stepIndex: Int,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        runID: HiveRunID,
        options: HiveRunOptions,
        graph: CompiledHiveGraph<Schema>,
        environment: HiveEnvironment<Schema>,
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        preStepGlobal: HiveGlobalStore<Schema>,
        resume: HiveResume<Schema>?,
        emitter: HiveEventEmitter,
        droppedCounter: HiveDroppedEventCounter
    ) async -> TaskExecutionResult<Schema> {
        guard let node = graph.nodesByID[task.nodeID] else {
            return TaskExecutionResult(error: HiveRuntimeError.unknownNodeID(task.nodeID))
        }

        switch node.retryPolicy {
        case .none:
            return await runNodeAttempt(
                node: node,
                task: task,
                stepIndex: stepIndex,
                threadID: threadID,
                attemptID: attemptID,
                runID: runID,
                options: options,
                environment: environment,
                registry: registry,
                initialCache: initialCache,
                preStepGlobal: preStepGlobal,
                resume: resume,
                emitter: emitter,
                droppedCounter: droppedCounter
            )
        case let .exponentialBackoff(initialNanoseconds, factor, maxAttempts, maxNanoseconds):
            var attempt = 1
            while attempt <= maxAttempts {
                let result = await runNodeAttempt(
                    node: node,
                    task: task,
                    stepIndex: stepIndex,
                    threadID: threadID,
                    attemptID: attemptID,
                    runID: runID,
                    options: options,
                    environment: environment,
                    registry: registry,
                    initialCache: initialCache,
                    preStepGlobal: preStepGlobal,
                    resume: resume,
                    emitter: emitter,
                    droppedCounter: droppedCounter
                )
                if result.error == nil {
                    return result
                }
                if attempt == maxAttempts {
                    return result
                }
                if Task.isCancelled {
                    return TaskExecutionResult(error: RuntimeCancellation.executionObserved)
                }

                let delay = Self.retryDelayNanoseconds(
                    initialNanoseconds: initialNanoseconds,
                    factor: factor,
                    attempt: attempt,
                    maxNanoseconds: maxNanoseconds
                )
                do {
                    try await environment.clock.sleep(nanoseconds: delay)
                } catch is CancellationError {
                    return TaskExecutionResult(error: RuntimeCancellation.executionObserved)
                } catch {
                    return TaskExecutionResult(error: error)
                }
                attempt += 1
            }
            return TaskExecutionResult(error: HiveRuntimeError.invalidRunOptions("retry attempts exhausted"))
        }
    }

    private static func retryDelayNanoseconds(
        initialNanoseconds: UInt64,
        factor: Double,
        attempt: Int,
        maxNanoseconds: UInt64
    ) -> UInt64 {
        // Spec: attempts are 1-based, and the delay for a failure before attempt+1 is:
        // min(maxNanoseconds, floor(initialNanoseconds * pow(factor, attempt-1))).
        let exponent = Double(max(0, attempt - 1))
        let raw = Double(initialNanoseconds) * pow(factor, exponent)
        let floored = raw.rounded(.down)
        let capped = min(Double(maxNanoseconds), floored)
        if capped <= 0 { return 0 }
        return UInt64(capped)
    }

    private static func runNodeAttempt(
        node: HiveCompiledNode<Schema>,
        task: HiveTask<Schema>,
        stepIndex: Int,
        threadID: HiveThreadID,
        attemptID: HiveRunAttemptID,
        runID: HiveRunID,
        options: HiveRunOptions,
        environment: HiveEnvironment<Schema>,
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        preStepGlobal: HiveGlobalStore<Schema>,
        resume: HiveResume<Schema>?,
        emitter: HiveEventEmitter,
        droppedCounter: HiveDroppedEventCounter
    ) async -> TaskExecutionResult<Schema> {
        let bufferingCapacity = max(1, options.eventBufferCapacity)
        let streamBuffer: HivePerAttemptStreamBuffer? = options.deterministicStreamBuffering
            ? HivePerAttemptStreamBuffer(capacity: bufferingCapacity, stepIndex: stepIndex, taskOrdinal: task.ordinal)
            : nil

        let storeView = HiveStoreView(
            global: preStepGlobal,
            taskLocal: task.local,
            initialCache: initialCache,
            registry: registry
        )

        let runContext = HiveRunContext<Schema>(
            runID: runID,
            threadID: threadID,
            attemptID: attemptID,
            stepIndex: stepIndex,
            taskID: task.id,
            options: options,
            resume: resume
        )

        let input = HiveNodeInput(
            store: storeView,
            run: runContext,
            context: environment.context,
            environment: environment,
            emitStream: { kind, metadata in
                if let streamBuffer {
                    streamBuffer.record(kind: mapStream(kind), metadata: metadata)
                    return
                }
                let enqueueResult = emitter.emit(
                    kind: mapStream(kind),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal,
                    metadata: metadata
                )
                droppedCounter.record(enqueueResult)
            },
            emitDebug: { name, metadata in
                if let streamBuffer {
                    streamBuffer.record(kind: .customDebug(name: name), metadata: metadata)
                    return
                }
                let enqueueResult = emitter.emit(
                    kind: .customDebug(name: name),
                    stepIndex: stepIndex,
                    taskOrdinal: task.ordinal,
                    metadata: metadata
                )
                droppedCounter.record(enqueueResult)
            }
        )

        do {
            let output = try await node.run(input)
            if let streamBuffer {
                let snapshot = streamBuffer.snapshot()
                if let overflowError = snapshot.overflowError {
                    return TaskExecutionResult(error: overflowError)
                }
                return TaskExecutionResult(output: output, streamEvents: snapshot.events, streamDrops: snapshot.dropped)
            }
            return TaskExecutionResult(output: output, error: nil, streamEvents: nil, streamDrops: .init())
        } catch {
            if options.deterministicStreamBuffering {
                // Failed-attempt stream events are discarded in this mode.
                return TaskExecutionResult(error: error)
            }
            return TaskExecutionResult(error: error)
        }
    }

    private static func mapStream(_ kind: HiveStreamEventKind) -> HiveEventKind {
        switch kind {
        case .customDebug(let name):
            return .customDebug(name: name)
        }
    }
}
