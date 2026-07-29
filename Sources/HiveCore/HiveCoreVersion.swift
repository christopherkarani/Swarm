/// Namespace for the Hive framework version information.
public enum HiveVersion {
    /// Semantic version string for the Hive umbrella module.
    public static let string = "0.2.1"

    /// Semantic version string for HiveCore.
    public static let core = "0.2.1"

    /// All module versions as a dictionary.
    public static var all: [String: String] {
        [
            "umbrella": string,
            "core": core
        ]
    }
}

// MARK: - Deprecated Module-Specific Version Types

/// Deprecated: Use `HiveVersion.core` instead.
@available(*, deprecated, renamed: "HiveVersion")
public enum HiveCoreVersion {
    /// Deprecated: Use `HiveVersion.core` instead.
    @available(*, deprecated, renamed: "HiveVersion.core")
    public static let string = HiveVersion.core
}
