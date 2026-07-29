public enum RecoveryStrategy: Sendable {
    case compressMore
    case evictAndRetry
    case offloadToDisk
    case fallbackToInMemory
    case fail
}

public enum MembraneError: Error, Sendable {
    case budgetExceeded(bucket: BucketID, requested: Int, available: Int)
    case contextWindowExceeded(totalTokens: Int, limit: Int)
    case kvMemoryExceeded(bytes: Int, limit: Int)
    case compressionFailed(stage: String, reason: String)
    case csoUpdateFailed(reason: String)
    case surrogateGenerationFailed(reason: String)
    case pagingStorageUnavailable(reason: String)
    case kvSwapIOError(reason: String)
    case pointerResolutionFailed(pointerID: String)
    case stageTimeout(stage: String, elapsed: Duration)
    case checkpointRecoveryFailed(reason: String)

    public var recoveryStrategy: RecoveryStrategy {
        switch self {
        case .budgetExceeded:
            return .compressMore
        case .contextWindowExceeded:
            return .evictAndRetry
        case .kvMemoryExceeded:
            return .offloadToDisk
        case .pagingStorageUnavailable:
            return .fallbackToInMemory
        default:
            return .fail
        }
    }
}
