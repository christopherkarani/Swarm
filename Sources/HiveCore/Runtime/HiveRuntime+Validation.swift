import Foundation

extension HiveRuntime {
    public func validateRunOptions(_ options: HiveRunOptions) throws {
        guard options.maxSteps >= 0 else {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "maxSteps",
                reason: "must be >= 0"
            )
        }
        guard options.maxConcurrentTasks >= 1 else {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "maxConcurrentTasks",
                reason: "must be >= 1"
            )
        }
        guard options.eventBufferCapacity >= 1 else {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "eventBufferCapacity",
                reason: "must be >= 1"
            )
        }
        if case let .every(steps) = options.checkpointPolicy, steps < 1 {
            throw HiveRunOptionsValidationError.invalidBounds(
                option: "checkpointPolicy.every(steps:)",
                reason: "steps must be >= 1"
            )
        }
        if options.deterministicStreamBuffering, options.streamingMode != .events {
            throw HiveRunOptionsValidationError.unsupportedCombination(
                reason: "deterministicStreamBuffering is only supported when streamingMode == .events"
            )
        }
        switch options.checkpointPolicy {
        case .disabled:
            break
        case .everyStep, .every, .onInterrupt:
            if environment.checkpointStore == nil {
                throw HiveRunOptionsValidationError.missingRequiredComponent(
                    component: "checkpointStore",
                    reason: "checkpointPolicy requires a configured checkpoint store"
                )
            }
        }
        if let override = options.outputProjectionOverride {
            _ = try normalizedOutputProjection(override)
        }
    }

    func validateRetryPolicies() throws {
        var invalid: HiveNodeID?
        for (id, node) in graph.nodesByID {
            if case let .exponentialBackoff(_, factor, maxAttempts, _) = node.retryPolicy {
                let invalidPolicy = maxAttempts < 1 || !factor.isFinite || factor < 1.0
                if invalidPolicy {
                    if let current = invalid {
                        if HiveOrdering.lexicographicallyPrecedes(id.rawValue, current.rawValue) {
                            invalid = id
                        }
                    } else {
                        invalid = id
                    }
                }
            }
        }
        if let invalid {
            throw HiveRunOptionsValidationError.unsupportedCombination(
                reason: "invalid retry policy for node \(invalid.rawValue)"
            )
        }
    }

    func validateRequiredCodecs() throws {
        if let missing = registry.firstMissingRequiredCodecID() {
            throw HiveRuntimeError.missingCodec(channelID: missing)
        }
    }

    private func normalizedOutputProjection(_ projection: HiveOutputProjection) throws -> HiveOutputProjection {
        let normalized = projection.normalized()
        switch normalized {
        case .fullStore:
            return normalized
        case .channels(let ids):
            for id in ids {
                guard let spec = registry.channelSpecsByID[id] else {
                    throw HiveRunOptionsValidationError.unsupportedCombination(
                        reason: "output projection includes unknown channel \(id.rawValue)"
                    )
                }
                if spec.scope == .taskLocal {
                    throw HiveRunOptionsValidationError.unsupportedCombination(
                        reason: "output projection includes task-local channel \(id.rawValue)"
                    )
                }
            }
            return normalized
        }
    }

    func buildOutput(options: HiveRunOptions, state: ThreadState<Schema>) throws -> HiveRunOutput<Schema> {
        let projection = try normalizedOutputProjection(
            options.outputProjectionOverride ?? graph.outputProjection
        )

        switch projection {
        case .fullStore:
            return .fullStore(state.global)
        case .channels(let ids):
            var values: [HiveProjectedChannelValue] = []
            values.reserveCapacity(ids.count)
            for id in ids {
                let value = try state.global.valueAny(for: id)
                values.append(HiveProjectedChannelValue(id: id, value: value))
            }
            return .channels(values)
        }
    }
}
