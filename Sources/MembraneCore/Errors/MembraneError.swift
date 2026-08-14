public enum MembraneError: Error, Sendable {
    case budgetExceeded(bucket: BucketID, requested: Int, available: Int)
    case pointerResolutionFailed(pointerID: String)
}
