#if SWARM_INTEGRATIONS
// HiveRuntimeEnqueueTests.swift
// HiveSwarm
//
// Regression tests for the shared run/resume/applyExternalWrites enqueue path
// (P2-1 dedupe). Self-contained on HiveCore: no Swarm imports.

import Foundation
import HiveCore
import Testing

private enum EnqueueTestSchema: HiveSchema {
    typealias Context = Void
    typealias Input = String

    enum Channels {
        static let messages = HiveChannelKey<EnqueueTestSchema, [String]>(HiveChannelID("messages"))
    }

    static let channelSpecs: [AnyHiveChannelSpec<EnqueueTestSchema>] = [
        AnyHiveChannelSpec(
            HiveChannelSpec(
                key: Channels.messages,
                scope: .global,
                reducer: .append(),
                updatePolicy: .multi,
                initial: { [] },
                persistence: .untracked
            )
        )
    ]

    static func inputWrites(
        _ input: String,
        inputContext: HiveInputContext
    ) throws -> [AnyHiveWrite<EnqueueTestSchema>] {
        [AnyHiveWrite(Channels.messages, [input])]
    }
}

private struct EnqueueNoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct EnqueueNoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

@Suite("HiveRuntime shared enqueue path")
struct HiveRuntimeEnqueueTests {
    private func makeRuntime() throws -> HiveRuntime<EnqueueTestSchema> {
        var builder = HiveGraphBuilder<EnqueueTestSchema>(start: [HiveNodeID("Start")])
        builder.addNode(HiveNodeID("Start")) { input in
            let messages = try input.store.get(EnqueueTestSchema.Channels.messages)
            return HiveNodeOutput(
                writes: [AnyHiveWrite(EnqueueTestSchema.Channels.messages, messages + ["done"])],
                next: .end
            )
        }
        let graph = try builder.compile()
        let environment = HiveEnvironment<EnqueueTestSchema>(
            context: (),
            clock: EnqueueNoopClock(),
            logger: EnqueueNoopLogger(),
            checkpointStore: nil
        )
        return try HiveRuntime(graph: graph, environment: environment)
    }

    private func expectInvalidBoundsMaxSteps(
        _ expression: () async throws -> HiveRunOutcome<EnqueueTestSchema>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            _ = try await expression()
            Issue.record("Expected HiveRunOptionsValidationError", sourceLocation: sourceLocation)
        } catch let error as HiveRunOptionsValidationError {
            #expect(
                error == .invalidBounds(option: "maxSteps", reason: "must be >= 0"),
                sourceLocation: sourceLocation
            )
        } catch {
            Issue.record("Wrong error type: \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test("run/resume/applyExternalWrites share fail-fast validation")
    func allEntryPointsFailFastOnInvalidOptions() async throws {
        let runtime = try makeRuntime()
        let badOptions = HiveRunOptions(maxSteps: -1)

        let runHandle = await runtime.run(
            threadID: HiveThreadID("enqueue-failfast"),
            input: "hello",
            options: badOptions
        )
        await expectInvalidBoundsMaxSteps { try await runHandle.outcome.value }

        // Bogus interrupt: validation must fail before interrupt lookup.
        let resumeHandle = await runtime.resume(
            threadID: HiveThreadID("enqueue-failfast"),
            interruptID: HiveInterruptID("bogus"),
            payload: "",
            options: badOptions
        )
        await expectInvalidBoundsMaxSteps { try await resumeHandle.outcome.value }

        let writesHandle = await runtime.applyExternalWrites(
            threadID: HiveThreadID("enqueue-failfast"),
            writes: [],
            options: badOptions
        )
        await expectInvalidBoundsMaxSteps { try await writesHandle.outcome.value }
    }

    @Test("attempts on the same thread serialize through the shared queue")
    func sameThreadAttemptsSerialize() async throws {
        let runtime = try makeRuntime()
        let options = HiveRunOptions(maxSteps: 5, checkpointPolicy: .disabled)
        let threadID = HiveThreadID("enqueue-serial")

        let first = await runtime.run(threadID: threadID, input: "one", options: options)
        let second = await runtime.run(threadID: threadID, input: "two", options: options)

        let firstOutcome = try await first.outcome.value
        let secondOutcome = try await second.outcome.value

        guard case .finished = firstOutcome else {
            Issue.record("First attempt did not finish: \(firstOutcome)")
            return
        }
        guard case .finished = secondOutcome else {
            Issue.record("Second attempt did not finish: \(secondOutcome)")
            return
        }
    }
}
#endif
