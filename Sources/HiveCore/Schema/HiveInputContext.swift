/// Context used to derive input writes for an attempt.
public struct HiveInputContext: Sendable {
    public let threadID: HiveThreadID
    public let runID: HiveRunID
    public let stepIndex: Int

    public init(threadID: HiveThreadID, runID: HiveRunID, stepIndex: Int) {
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
    }
}
