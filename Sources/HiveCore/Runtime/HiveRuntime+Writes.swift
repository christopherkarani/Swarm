import Foundation

extension HiveRuntime {
    func applyInputWrites(
        _ writes: [AnyHiveWrite<Schema>],
        to global: inout HiveGlobalStore<Schema>
    ) throws -> [HiveChannelID] {
        var globalWritesByChannel: [HiveChannelID: [AnyHiveWrite<Schema>]] = [:]
        for write in writes {
            guard let spec = registry.channelSpecsByID[write.channelID] else {
                throw HiveRuntimeError.unknownChannelID(write.channelID)
            }
            if spec.scope != .global {
                throw HiveRuntimeError.taskLocalWriteNotAllowed
            }
            try storeSupport.validateValueType(write.value, spec: spec)
            globalWritesByChannel[write.channelID, default: []].append(write)
        }

        var written: [HiveChannelID] = []
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let writesForChannel = globalWritesByChannel[spec.id] ?? []
            if writesForChannel.isEmpty { continue }
            if spec.updatePolicy == .single, writesForChannel.count > 1 {
                throw HiveRuntimeError.updatePolicyViolation(
                    channelID: spec.id,
                    policy: .single,
                    writeCount: writesForChannel.count
                )
            }
            var current = try global.valueAny(for: spec.id)
            for write in writesForChannel {
                current = try spec._reduceBox(current, write.value)
            }
            try global.setAny(current, for: spec.id)
            written.append(spec.id)
        }

        return written
    }

    func selectInterrupt(
        tasks: [HiveTask<Schema>],
        outputs: [HiveNodeOutput<Schema>]
    ) throws -> HiveInterrupt<Schema>? {
        // Selection is by smallest taskOrdinal (i.e., earliest task in this step).
        for (index, output) in outputs.enumerated() {
            if let request = output.interrupt {
                let winningTaskID = tasks[index].id
                let interruptID = makeInterruptID(winningTaskID: winningTaskID)
                return HiveInterrupt(id: interruptID, payload: request.payload)
            }
        }
        return nil
    }

    private func makeInterruptID(winningTaskID: HiveTaskID) -> HiveInterruptID {
        var bytes = Data()
        bytes.append(contentsOf: "HINT1".utf8)
        bytes.append(contentsOf: winningTaskID.rawValue.utf8)
        let hash = HiveSHA256.hash(data: bytes)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return HiveInterruptID(hex)
    }

    func applyExternalWrites(
        _ writes: [AnyHiveWrite<Schema>],
        to global: inout HiveGlobalStore<Schema>
    ) throws -> [HiveChannelID] {
        func validateValueType(_ value: any Sendable, spec: AnyHiveChannelSpec<Schema>) throws {
            let expectedValueTypeID = spec.valueTypeID
            let actualValueTypeID = String(reflecting: type(of: value))
            guard expectedValueTypeID == actualValueTypeID else {
                throw HiveExternalWriteError.payloadTypeMismatch(
                    channelID: spec.id,
                    expectedValueTypeID: expectedValueTypeID,
                    actualValueTypeID: actualValueTypeID
                )
            }
        }

        var writesByChannel: [HiveChannelID: [AnyHiveWrite<Schema>]] = [:]
        for write in writes {
            guard let spec = registry.channelSpecsByID[write.channelID] else {
                throw HiveExternalWriteError.unknownChannel(channelID: write.channelID)
            }
            if spec.scope != .global {
                throw HiveExternalWriteError.scopeMismatch(
                    channelID: write.channelID,
                    expected: .global,
                    actual: spec.scope
                )
            }
            try validateValueType(write.value, spec: spec)
            writesByChannel[write.channelID, default: []].append(write)
        }

        // Enforce `.single` using the provided external writes array grouping.
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let channelWrites = writesByChannel[spec.id] ?? []
            if spec.updatePolicy == .single, channelWrites.count > 1 {
                throw HiveExternalWriteError.updatePolicyViolation(
                    channelID: spec.id,
                    policy: .single,
                    writeCount: channelWrites.count
                )
            }
        }

        var written: [HiveChannelID] = []
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            let channelWrites = writesByChannel[spec.id] ?? []
            if channelWrites.isEmpty { continue }
            var current = try global.valueAny(for: spec.id)
            for write in channelWrites {
                current = try spec._reduceBox(current, write.value)
            }
            try global.setAny(current, for: spec.id)
            written.append(spec.id)
        }

        return written
    }
}
