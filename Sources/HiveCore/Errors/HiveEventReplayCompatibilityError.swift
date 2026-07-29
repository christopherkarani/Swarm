public enum HiveEventReplayCompatibilityError: Error, Sendable, Equatable {
    case incompatibleSchemaVersion(expected: HiveEventSchemaVersion, found: HiveEventSchemaVersion)
}
