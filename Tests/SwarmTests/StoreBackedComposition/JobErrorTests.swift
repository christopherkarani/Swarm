import Foundation
@testable import Swarm
import Testing

@Suite("JobError")
struct JobErrorTests {
    @Test("each case has a user-facing description", arguments: [
        (JobError.emptyChildName, "Job child name is empty"),
        (JobError.duplicateChildName("alpha"), "Job child name is duplicated: alpha"),
        (JobError.emptyFanOut, "Job fan-out requires at least one child"),
        (JobError.fanOutAlreadyUsed, "Job allows only one fan-out")
    ])
    func descriptions(error: JobError, expected: String) {
        #expect(error.errorDescription == expected)
        #expect(error.localizedDescription == expected)
    }
}
