#if SWARM_INTEGRATIONS && canImport(ContextCore)
import Testing

@testable import Swarm

@Suite("ContextCore Integration")
struct ContextCoreIntegrationTests {
    @Test("ContextCoreMemory can ingest messages and build a context window")
    func contextCoreMemoryBuildWindow() async throws {
        let memory = try ContextCoreMemory(
            configuration: ContextCoreMemoryConfiguration(
                promptTitle: "ContextCore Test Memory",
                promptGuidance: "Test guidance"
            )
        )

        await memory.beginMemorySession()
        await memory.add(.user("alpha"))
        await memory.add(.assistant("beta"))

        let context = await memory.context(for: "alpha", tokenLimit: 256)

        #expect(await memory.count == 2)
        #expect(await memory.isEmpty == false)
        #expect(context.contains("alpha"))
        #expect(context.contains("beta"))
    }

    @Test("ContextCoreMemory clear ends an active session")
    func contextCoreMemoryClearEndsActiveSession() async throws {
        let recorder = EndSessionRecorder()
        let memory = try ContextCoreMemory(
            configuration: ContextCoreMemoryConfiguration(
                promptTitle: "ContextCore Test Memory",
                promptGuidance: "Test guidance"
            ),
            endSession: { _ in
                await recorder.record()
            }
        )

        await memory.beginMemorySession()
        await memory.clear()

        #expect(await recorder.count == 1)
    }
}

private actor EndSessionRecorder {
    private var recordedCount = 0

    var count: Int {
        recordedCount
    }

    func record() {
        recordedCount += 1
    }
}
#endif
