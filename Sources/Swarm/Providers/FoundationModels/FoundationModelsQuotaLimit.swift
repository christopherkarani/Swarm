import Foundation

/// Detects Apple Private Cloud Compute daily quota failures from typed
/// errors or host descriptions.
enum FoundationModelsQuotaLimit: Sendable {
    static func stringMatches(_ error: Error) -> Bool {
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return text.contains("quotalimitreached")
            || text.contains("quota limit")
            || text.contains("usage limit exceeded")
            || text.contains("usage limit reached")
    }
}
