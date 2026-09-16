import Foundation

/// Detects Apple Foundation Models overflowing the on-device context window.
///
/// Typed OS 26/27 errors are mapped in ``FoundationModelsErrorMapping``. This
/// helper keeps a string fallback for hosts that only expose a description.
enum FoundationModelsContextOverflow: Sendable {
    static func matches(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if FoundationModelsErrorMapping.isContextOverflow(error) {
            return true
        }
        #endif
        return stringMatches(error)
    }

    static func map(_ error: Error) -> AgentError {
        #if canImport(FoundationModels)
        return FoundationModelsErrorMapping.map(error)
        #else
        if error is CancellationError {
            return .cancelled
        }
        if stringMatches(error) {
            return .contextWindowExceeded(tokenCount: 0, limit: 0)
        }
        return .generationFailed(reason: error.localizedDescription)
        #endif
    }

    static func stringMatches(_ error: Error) -> Bool {
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return text.contains("context size exceeded")
            || text.contains("exceededcontextwindowsize")
            || text.contains("exceeded context window")
    }
}
