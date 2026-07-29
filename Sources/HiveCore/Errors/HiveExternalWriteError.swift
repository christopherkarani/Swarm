public enum HiveExternalWriteError: Error, Sendable, Equatable {
    case unknownChannel(channelID: HiveChannelID)
    case scopeMismatch(channelID: HiveChannelID, expected: HiveChannelScope, actual: HiveChannelScope)
    case payloadTypeMismatch(channelID: HiveChannelID, expectedValueTypeID: String, actualValueTypeID: String)
    case updatePolicyViolation(channelID: HiveChannelID, policy: HiveUpdatePolicy, writeCount: Int)
}
