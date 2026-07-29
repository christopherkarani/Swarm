/// Runtime errors thrown during Hive execution.
public enum HiveRuntimeError: Error, Sendable {
    case invalidRunOptions(String)

    case stepIndexOutOfRange(stepIndex: Int)
    case taskOrdinalOutOfRange(ordinal: Int)
    case invalidTaskLocalFingerprintLength(expected: Int, actual: Int)

    case checkpointStoreMissing
    case checkpointOverrideNotCheckpointed(channelID: HiveChannelID)
    case checkpointVersionMismatch(
        expectedSchema: String,
        expectedGraph: String,
        foundSchema: String,
        foundGraph: String
    )
    case checkpointDecodeFailed(channelID: HiveChannelID, errorDescription: String)
    case checkpointEncodeFailed(channelID: HiveChannelID, errorDescription: String)
    case checkpointCorrupt(field: String, errorDescription: String)
    case interruptPending(interruptID: HiveInterruptID)
    case noCheckpointToResume
    case checkpointNotFound(id: HiveCheckpointID)
    case noInterruptToResume
    case resumeInterruptMismatch(expected: HiveInterruptID, found: HiveInterruptID)
    case forkSourceCheckpointMissing(threadID: HiveThreadID, checkpointID: HiveCheckpointID?)
    case forkCheckpointStoreMissing
    case forkCheckpointQueryUnsupported
    case forkTargetThreadConflict(threadID: HiveThreadID)
    case forkSchemaGraphMismatch(
        expectedSchema: String,
        expectedGraph: String,
        foundSchema: String,
        foundGraph: String
    )
    case forkMalformedCheckpoint(field: String, errorDescription: String)

    case unknownNodeID(HiveNodeID)
    /// Attempted to access a channel ID that is not present in the schema.
    case unknownChannelID(HiveChannelID)
    /// A required store/cache value for a declared channel was missing.
    case storeValueMissing(channelID: HiveChannelID)
    /// Stored value type does not match the expected channel value type.
    case channelTypeMismatch(
        channelID: HiveChannelID,
        expectedValueTypeID: String,
        actualValueTypeID: String
    )
    /// Channel scope does not match the store being accessed.
    case scopeMismatch(
        channelID: HiveChannelID,
        expected: HiveChannelScope,
        actual: HiveChannelScope
    )
    /// Required codec is missing for a channel.
    case missingCodec(channelID: HiveChannelID)
    /// Task-local fingerprint encoding failed for the selected channel.
    case taskLocalFingerprintEncodeFailed(
        channelID: HiveChannelID,
        errorDescription: String
    )

    case updatePolicyViolation(channelID: HiveChannelID, policy: HiveUpdatePolicy, writeCount: Int)
    case taskLocalWriteNotAllowed
    case missingTaskLocalValue(channelID: HiveChannelID)

    case internalInvariantViolation(String)
}
