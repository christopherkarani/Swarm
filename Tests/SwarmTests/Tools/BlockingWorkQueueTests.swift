#if SWARM_INTEGRATIONS
import Foundation
@testable import Swarm
import Testing

@Suite("BlockingWorkQueue")
struct BlockingWorkQueueTests {
    @Test("Blocking work runs on the dedicated queue, not the cooperative pool")
    func runsOnDedicatedQueue() async throws {
        let key = DispatchSpecificKey<Bool>()
        BlockingWorkQueue.queue.setSpecific(key: key, value: true)
        defer { BlockingWorkQueue.queue.setSpecific(key: key, value: nil) }

        let onDedicatedQueue = try await BlockingWorkQueue.run {
            DispatchQueue.getSpecific(key: key) == true
        }
        #expect(onDedicatedQueue)
    }

    @Test("Errors from blocking work propagate")
    func propagatesErrors() async {
        await #expect(throws: AgentError.self) {
            try await BlockingWorkQueue.run {
                throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Unable to resolve URL host")
            }
        }
    }

    @Test("Cancellation resumes the caller without waiting for the blocking call")
    func cancellationDoesNotWaitForBlockingCall() async throws {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }

        let task = Task {
            try await BlockingWorkQueue.run {
                _ = release.wait(timeout: .now() + 5)
                return true
            }
        }
        try await Task.sleep(for: .milliseconds(50))

        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(clock.now - start < .seconds(2))
    }
}
#endif
