import Foundation

/// Errors from `Job` fan-out validation.
///
/// Child agent failures are not wrapped. They propagate as-is so callers
/// still see `AgentError` (and friends). `JobError` is only for Job's own
/// rules: names, empty fan-out, and the one-fan-out limit.
public enum JobError: Error, Sendable, Equatable {
    /// A child name was empty or whitespace.
    case emptyChildName

    /// Two children used the same trimmed name.
    case duplicateChildName(String)

    /// `fanOut` was called with no children.
    case emptyFanOut

    /// This `Job.run` already used its one fan-out.
    case fanOutAlreadyUsed
}

extension JobError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyChildName:
            return "Job child name is empty"
        case let .duplicateChildName(name):
            return "Job child name is duplicated: \(name)"
        case .emptyFanOut:
            return "Job fan-out requires at least one child"
        case .fanOutAlreadyUsed:
            return "Job allows only one fan-out"
        }
    }
}
