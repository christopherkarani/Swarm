import Foundation

extension HiveRuntime {
    func commitStep(
        state: ThreadState<Schema>,
        tasks: [HiveTask<Schema>],
        outputs: [HiveNodeOutput<Schema>],
        options: HiveRunOptions
    ) throws -> CommitResult<Schema> {
        let (perTaskWrites, globalWritesByChannel) = try collectWrites(tasks: tasks, outputs: outputs)

        var postGlobal = state.global

        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let writes = globalWritesByChannel[spec.id] ?? []
            if writes.isEmpty { continue }
            if spec.updatePolicy == .single, writes.count > 1 {
                throw HiveRuntimeError.updatePolicyViolation(
                    channelID: spec.id,
                    policy: .single,
                    writeCount: writes.count
                )
            }
        }

        var writtenGlobalChannels: [HiveChannelID] = []
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            guard let writes = globalWritesByChannel[spec.id], !writes.isEmpty else { continue }
            let ordered = writes.sorted { lhs, rhs in
                if lhs.taskOrdinal == rhs.taskOrdinal {
                    return lhs.emissionIndex < rhs.emissionIndex
                }
                return lhs.taskOrdinal < rhs.taskOrdinal
            }
            var current = try postGlobal.valueAny(for: spec.id)
            for write in ordered {
                current = try spec._reduceBox(current, write.value)
            }
            try postGlobal.setAny(current, for: spec.id)
            writtenGlobalChannels.append(spec.id)
        }

        // Reset ephemeral channels to initial value after each superstep commit.
        for spec in registry.sortedChannelSpecs where spec.scope == .global && spec.persistence.resetsAfterStep {
            let initialValue = spec._initialBox()
            try postGlobal.setAny(initialValue, for: spec.id)
        }

        var postTaskLocal: [HiveTaskLocalStore<Schema>] = []
        postTaskLocal.reserveCapacity(tasks.count)

        for (index, task) in tasks.enumerated() {
            var overlay = task.local
            let writes = perTaskWrites[index].taskLocal

            var writesByChannel: [HiveChannelID: [WriteRecord<Schema>]] = [:]
            for write in writes {
                writesByChannel[write.channelID, default: []].append(write)
            }

            for spec in registry.sortedChannelSpecs where spec.scope == .taskLocal {
                let channelWrites = writesByChannel[spec.id] ?? []
                if channelWrites.isEmpty { continue }
                if spec.updatePolicy == .single, channelWrites.count > 1 {
                    throw HiveRuntimeError.updatePolicyViolation(
                        channelID: spec.id,
                        policy: .single,
                        writeCount: channelWrites.count
                    )
                }
                let ordered = channelWrites.sorted { $0.emissionIndex < $1.emissionIndex }
                var current = try (overlay.valueAny(for: spec.id) ?? initialCache.valueAny(for: spec.id))
                for write in ordered {
                    current = try spec._reduceBox(current, write.value)
                }
                try overlay.setAny(current, for: spec.id)
            }
            postTaskLocal.append(overlay)
        }

        var nextGraphSeeds: [HiveTaskSeed<Schema>] = []
        var nextSpawnSeeds: [HiveTaskSeed<Schema>] = []

        for (index, task) in tasks.enumerated() {
            let output = outputs[index]
            if !output.spawn.isEmpty {
                nextSpawnSeeds.append(contentsOf: output.spawn)
            }

            let normalizedNext = output.next.normalized
            switch normalizedNext {
            case .useGraphEdges:
                break
            case .end:
                continue
            case .to(let nodes):
                for node in nodes {
                    nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                }
                continue
            }

            if let router = graph.routersByFrom[task.nodeID] {
                let routerGlobal = try applyGlobalWritesForTask(
                    taskIndex: index,
                    preStepGlobal: state.global,
                    perTaskWrites: perTaskWrites
                )
                let routerView = HiveStoreView(
                    global: routerGlobal,
                    taskLocal: postTaskLocal[index],
                    initialCache: initialCache,
                    registry: registry
                )
                let routed = router(routerView).normalized
                switch routed {
                case .useGraphEdges:
                    let staticEdges = graph.staticEdgesByFrom[task.nodeID] ?? []
                    for node in staticEdges {
                        nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                    }
                case .end:
                    break
                case .to(let nodes):
                    for node in nodes {
                        nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                    }
                }
            } else {
                let staticEdges = graph.staticEdgesByFrom[task.nodeID] ?? []
                for node in staticEdges {
                    nextGraphSeeds.append(HiveTaskSeed(nodeID: node))
                }
            }
        }

        var joinSeen = state.joinSeenParents
        var joinSeedKeys: Set<SeedKey> = []
        var completedNodesMask = HiveBitset(wordCount: graph.joinBitsetWordCount)
        for task in tasks {
            if let ordinal = graph.nodeOrdinalByID[task.nodeID] {
                completedNodesMask.insert(ordinal)
            }
        }

        for task in tasks {
            for edge in graph.joinEdgesByTarget[task.nodeID] ?? [] {
                guard let parentMask = graph.joinParentMaskByJoinID[edge.id] else { continue }
                if joinSeen[edge.id] == parentMask {
                    joinSeen[edge.id] = HiveBitset(wordCount: graph.joinBitsetWordCount)
                }
            }
        }

        var affectedJoinIDs: Set<String> = []
        affectedJoinIDs.reserveCapacity(tasks.count)
        for task in tasks {
            for edge in graph.joinEdgesByParent[task.nodeID] ?? [] {
                affectedJoinIDs.insert(edge.id)
            }
        }

        var affectedEdges: [HiveJoinEdge] = []
        affectedEdges.reserveCapacity(affectedJoinIDs.count)
        for joinID in affectedJoinIDs {
            guard let edge = graph.joinEdgeByID[joinID] else { continue }
            affectedEdges.append(edge)
        }
        affectedEdges.sort { lhs, rhs in
            let left = graph.joinEdgeOrderByID[lhs.id] ?? 0
            let right = graph.joinEdgeOrderByID[rhs.id] ?? 0
            return left < right
        }

        for edge in affectedEdges {
            guard let parentMask = graph.joinParentMaskByJoinID[edge.id] else { continue }
            let wasAvailable = (joinSeen[edge.id] == parentMask)
            var seen = joinSeen[edge.id] ?? HiveBitset(wordCount: graph.joinBitsetWordCount)
            for parent in edge.parents {
                guard let ordinal = graph.nodeOrdinalByID[parent] else { continue }
                if completedNodesMask.contains(ordinal) {
                    seen.insert(ordinal)
                }
            }
            joinSeen[edge.id] = seen
            let isAvailable = (seen == parentMask)
            if !wasAvailable && isAvailable {
                let seed = HiveTaskSeed<Schema>(nodeID: edge.target)
                nextGraphSeeds.append(seed)
                let fingerprint = try HiveTaskLocalFingerprint.digest(
                    registry: registry,
                    initialCache: initialCache,
                    overlay: seed.local,
                    debugPayloads: options.debugPayloads
                )
                joinSeedKeys.insert(SeedKey(nodeID: seed.nodeID, fingerprint: fingerprint))
            }
        }

        let dedupedGraphSeeds = try dedupeGraphSeeds(nextGraphSeeds, options: options)

        try validateSeedNodes(dedupedGraphSeeds.map(\.seed), spawnSeeds: nextSpawnSeeds)

        var nextFrontier: [HiveFrontierTask<Schema>] = []
        nextFrontier.reserveCapacity(dedupedGraphSeeds.count + nextSpawnSeeds.count)
        for entry in dedupedGraphSeeds {
            nextFrontier.append(
                HiveFrontierTask(
                    seed: entry.seed,
                    provenance: .graph,
                    isJoinSeed: joinSeedKeys.contains(entry.key)
                )
            )
        }
        for seed in nextSpawnSeeds {
            nextFrontier.append(HiveFrontierTask(seed: seed, provenance: .spawn, isJoinSeed: false))
        }

        var normalFrontier: [HiveFrontierTask<Schema>] = []
        var deferredNextFrontier: [HiveFrontierTask<Schema>] = []
        for task in nextFrontier {
            if graph.nodesByID[task.seed.nodeID]?.options.contains(.deferred) == true {
                deferredNextFrontier.append(task)
            } else {
                normalFrontier.append(task)
            }
        }

        return CommitResult(
            global: postGlobal,
            frontier: normalFrontier,
            deferredFrontier: deferredNextFrontier,
            joinSeenParents: joinSeen,
            writtenGlobalChannels: writtenGlobalChannels
        )
    }

    private func collectWrites(
        tasks: [HiveTask<Schema>],
        outputs: [HiveNodeOutput<Schema>]
    ) throws -> ([TaskWrites<Schema>], [HiveChannelID: [WriteRecord<Schema>]]) {
        var perTaskWrites: [TaskWrites<Schema>] = Array(repeating: TaskWrites(), count: tasks.count)
        var globalWritesByChannel: [HiveChannelID: [WriteRecord<Schema>]] = [:]

        for (taskIndex, output) in outputs.enumerated() {
            for (emissionIndex, write) in output.writes.enumerated() {
                guard let spec = registry.channelSpecsByID[write.channelID] else {
                    throw HiveRuntimeError.unknownChannelID(write.channelID)
                }
                try storeSupport.validateValueType(write.value, spec: spec)
                let record = WriteRecord(
                    channelID: write.channelID,
                    value: write.value,
                    emissionIndex: emissionIndex,
                    taskOrdinal: taskIndex,
                    spec: spec
                )
                switch spec.scope {
                case .global:
                    perTaskWrites[taskIndex].global.append(record)
                    globalWritesByChannel[write.channelID, default: []].append(record)
                case .taskLocal:
                    perTaskWrites[taskIndex].taskLocal.append(record)
                }
            }
        }

        return (perTaskWrites, globalWritesByChannel)
    }

    private func applyGlobalWritesForTask(
        taskIndex: Int,
        preStepGlobal: HiveGlobalStore<Schema>,
        perTaskWrites: [TaskWrites<Schema>]
    ) throws -> HiveGlobalStore<Schema> {
        var global = preStepGlobal
        let writes = perTaskWrites[taskIndex].global.sorted { $0.emissionIndex < $1.emissionIndex }
        if writes.isEmpty {
            return global
        }
        // Router "fresh read" requires applying this task's global writes in ascending emission order.
        // Channels are independent, but error precedence (e.g., reducer throws) must follow emission order.
        for write in writes {
            let current = try global.valueAny(for: write.channelID)
            let reduced = try write.spec._reduceBox(current, write.value)
            try global.setAny(reduced, for: write.channelID)
        }

        return global
    }

    private func dedupeGraphSeeds(
        _ seeds: [HiveTaskSeed<Schema>],
        options: HiveRunOptions
    ) throws -> [(seed: HiveTaskSeed<Schema>, key: SeedKey)] {
        var seen: Set<SeedKey> = []
        var deduped: [(seed: HiveTaskSeed<Schema>, key: SeedKey)] = []
        deduped.reserveCapacity(seeds.count)

        for seed in seeds {
            let fingerprint = try HiveTaskLocalFingerprint.digest(
                registry: registry,
                initialCache: initialCache,
                overlay: seed.local,
                debugPayloads: options.debugPayloads
            )
            let key = SeedKey(nodeID: seed.nodeID, fingerprint: fingerprint)
            if seen.insert(key).inserted {
                deduped.append((seed: seed, key: key))
            }
        }

        return deduped
    }

    private func validateSeedNodes(
        _ graphSeeds: [HiveTaskSeed<Schema>],
        spawnSeeds: [HiveTaskSeed<Schema>]
    ) throws {
        for seed in graphSeeds {
            guard graph.nodesByID[seed.nodeID] != nil else {
                throw HiveRuntimeError.unknownNodeID(seed.nodeID)
            }
        }
        for seed in spawnSeeds {
            guard graph.nodesByID[seed.nodeID] != nil else {
                throw HiveRuntimeError.unknownNodeID(seed.nodeID)
            }
        }
    }

    func makeTaskID(
        runID: HiveRunID,
        stepIndex: Int,
        nodeID: HiveNodeID,
        ordinal: Int,
        localFingerprint: Data
    ) throws -> HiveTaskID {
        guard let stepValue = UInt32(exactly: stepIndex) else {
            throw HiveRuntimeError.stepIndexOutOfRange(stepIndex: stepIndex)
        }
        guard let ordinalValue = UInt32(exactly: ordinal) else {
            throw HiveRuntimeError.taskOrdinalOutOfRange(ordinal: ordinal)
        }
        guard localFingerprint.count == 32 else {
            throw HiveRuntimeError.invalidTaskLocalFingerprintLength(
                expected: 32,
                actual: localFingerprint.count
            )
        }

        var bytes = Data()
        var uuid = runID.rawValue.uuid
        withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }

        appendUInt32BE(stepValue, to: &bytes)
        bytes.append(0)
        bytes.append(contentsOf: nodeID.rawValue.utf8)
        bytes.append(0)
        appendUInt32BE(ordinalValue, to: &bytes)
        bytes.append(localFingerprint)

        let hash = HiveSHA256.hash(data: bytes)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return HiveTaskID(hex)
    }
}
