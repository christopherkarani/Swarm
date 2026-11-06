import Foundation

extension HiveRuntime {
    // MARK: - Streaming Mode Helpers

    /// Builds a snapshot of all global channel values for streaming.
    private func buildStoreSnapshot(state: ThreadState<Schema>, debugPayloads: Bool) throws -> [HiveSnapshotValue] {
        try registry.sortedChannelSpecs.compactMap { spec -> HiveSnapshotValue? in
            guard spec.scope == .global else { return nil }
            let hash = try payloadHash(for: spec.id, in: state.global)
            let debugVal: (any Sendable)? = debugPayloads ? (try? state.global.valueAny(for: spec.id)) : nil
            return HiveSnapshotValue(channelID: spec.id, payloadHash: hash, debugValue: debugVal)
        }
    }

    /// Builds channel update values for only the channels written in this step.
    private func buildChannelUpdates(writtenChannels: [HiveChannelID], state: ThreadState<Schema>, debugPayloads: Bool) throws -> [HiveSnapshotValue] {
        try writtenChannels.sorted(by: { $0.rawValue < $1.rawValue }).compactMap { channelID -> HiveSnapshotValue? in
            let hash = try payloadHash(for: channelID, in: state.global)
            let debugVal: (any Sendable)? = debugPayloads ? (try? state.global.valueAny(for: channelID)) : nil
            return HiveSnapshotValue(channelID: channelID, payloadHash: hash, debugValue: debugVal)
        }
    }

    /// Emits streaming mode events if enabled in options.
    func emitStreamingEvents(
        mode: HiveStreamingMode,
        state: ThreadState<Schema>,
        writtenChannels: [HiveChannelID],
        debugPayloads: Bool,
        stepIndex: Int,
        emitter: HiveEventEmitter
    ) throws {
        guard mode != .events else { return }

        if mode == .values || mode == .combined {
            let snapshot = try buildStoreSnapshot(state: state, debugPayloads: debugPayloads)
            emitter.emit(
                kind: .storeSnapshot(channelValues: snapshot),
                stepIndex: stepIndex,
                taskOrdinal: nil,
                treatAsNonDroppable: true
            )
        }

        if mode == .updates || mode == .combined {
            let updates = try buildChannelUpdates(writtenChannels: writtenChannels, state: state, debugPayloads: debugPayloads)
            emitter.emit(
                kind: .channelUpdates(channelValues: updates),
                stepIndex: stepIndex,
                taskOrdinal: nil,
                treatAsNonDroppable: true
            )
        }
    }
}
