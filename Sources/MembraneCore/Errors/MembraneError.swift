public enum RecoveryStrategy: Sendable {
    case compressMore
    case fail
}

public enum MembraneError: Error, Sendable {
    case budgetExceeded(bucket: BucketID, requested: Int, available: Int)
    case pointerResolutionFailed(pointerID: String)

    public var recoveryStrategy: RecoveryStrategy {
        switch self {
        case .budgetExceeded:
            return .compressMore
        case .pointerResolutionFailed:
            return .fail
        }
    }
}
