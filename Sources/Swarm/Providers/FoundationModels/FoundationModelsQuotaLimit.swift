import Foundation

/// Detects Apple Private Cloud Compute daily quota failures from typed
/// errors or host descriptions.
enum FoundationModelsQuotaLimit: Sendable {
    /// Lowercased description needles identifying a quota failure.
    ///
    /// Shared with the ``FoundationModelsErrorMapping`` string-fallback cause
    /// table; matching runs through ``AgentErrorCauseFactory``.
    static let needles = [
        "quotalimitreached",
        "quota limit",
        "usage limit exceeded",
        "usage limit reached",
    ]

    static func stringMatches(_ error: Error) -> Bool {
        AgentErrorCauseFactory.descriptionMatches(error, needles: needles)
    }
}
