// GuardrailRunnerGoldenTests.swift
// SwarmTests
//
// Golden tests pinning byte-identical runner behavior (order, short-circuit,
// error payloads, error precedence) across all four guardrail kinds in both
// sequential and parallel execution styles.

import Foundation
@testable import Swarm
import Testing

// MARK: - Fixtures

private actor ExecutionLog {
    private(set) var entries: [String] = []

    func record(_ name: String) {
        entries.append(name)
    }

    func snapshot() -> [String] {
        entries
    }
}

private actor RecordingObserver: AgentObserver {
    struct Event: Sendable, Equatable {
        let name: String
        let type: GuardrailType
        let message: String?
    }

    private(set) var events: [Event] = []

    func onGuardrailTriggered(
        context _: AgentContext?,
        guardrailName: String,
        guardrailType: GuardrailType,
        result: GuardrailResult
    ) async {
        events.append(Event(name: guardrailName, type: guardrailType, message: result.message))
    }
}

private struct KaboomError: Error {}

/// One-shot gate used to suspend validations at a deterministic point.
private final class ReleaseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func releaseAll() {
        lock.lock()
        released = true
        let waiters = waiters
        self.waiters = []
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func waitForEntries(_ log: ExecutionLog, count: Int) async throws {
    for _ in 0..<2500 {
        if await log.snapshot().count >= count {
            return
        }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Timed out waiting for \(count) guardrail entries")
}

// MARK: - Sequential Golden Tests

@Suite("Guardrail Runner Sequential Goldens")
struct GuardrailRunnerSequentialGoldens {
    @Test("Sequential input short-circuit throws first tripwire payload and skips later guards")
    func sequentialInputShortCircuit() async throws {
        let log = ExecutionLog()
        let first = InputGuard("first_blocker") { _, _ in
            await log.record("first_blocker")
            return .tripwire(
                message: "first blocked",
                outputInfo: .dictionary(["code": .string("F001")])
            )
        }
        let second = InputGuard("second_blocker") { _, _ in
            await log.record("second_blocker")
            return .tripwire(message: "second blocked")
        }
        let runner = GuardrailRunner()

        do {
            _ = try await runner.runInputGuardrails([first, second], input: "x", context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .inputTripwireTriggered(
                guardrailName: "first_blocker",
                message: "first blocked",
                outputInfo: .dictionary(["code": .string("F001")])
            ))
        }
        #expect(await log.snapshot() == ["first_blocker"])
    }

    @Test("Sequential run-all returns results in order and throws first tripwired by index")
    func sequentialRunAllFirstByIndexWins() async throws {
        let observer = RecordingObserver()
        let pass = InputGuard("pass_guard") { _, _ in
            .passed(message: "fine")
        }
        let tripA = InputGuard("trip_a") { _, _ in
            .tripwire(message: "a blocked", outputInfo: .dictionary(["id": .int(1)]))
        }
        let tripB = InputGuard("trip_b") { _, _ in
            .tripwire(message: "b blocked", outputInfo: .dictionary(["id": .int(2)]))
        }
        let runner = GuardrailRunner(
            configuration: GuardrailRunnerConfiguration(stopOnFirstTripwire: false),
            observer: observer
        )

        do {
            _ = try await runner.runInputGuardrails([pass, tripA, tripB], input: "x", context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .inputTripwireTriggered(
                guardrailName: "trip_a",
                message: "a blocked",
                outputInfo: .dictionary(["id": .int(1)])
            ))
        }

        let events = await observer.events
        #expect(events == [
            RecordingObserver.Event(name: "trip_a", type: .input, message: "a blocked"),
            RecordingObserver.Event(name: "trip_b", type: .input, message: "b blocked"),
        ])
    }

    @Test("Sequential output tripwire payload carries agent name")
    func sequentialOutputTripwirePayload() async throws {
        let agent = MockAgent(configuration: AgentConfiguration(name: "golden-agent"))
        let guardrail = OutputGuard("length_watch") { output, _, _ in
            output.count > 3 ? .tripwire(
                message: "too long",
                outputInfo: .dictionary(["len": .int(output.count)])
            ) : .passed()
        }
        let runner = GuardrailRunner()

        do {
            _ = try await runner.runOutputGuardrails([guardrail], output: "toolong", agent: agent, context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .outputTripwireTriggered(
                guardrailName: "length_watch",
                agentName: "golden-agent",
                message: "too long",
                outputInfo: .dictionary(["len": .int(7)])
            ))
        }
    }

    @Test("Sequential tool input tripwire payload carries tool name and data context")
    func sequentialToolInputTripwirePayload() async throws {
        let observer = RecordingObserver()
        let context = AgentContext(input: "tool request")
        let data = ToolGuardrailData(
            tool: MockTool(name: "lookup"),
            arguments: [:],
            agent: MockAgent(),
            context: context
        )
        let guardrail = ClosureToolInputGuardrail(name: "arg_watcher") { _ in
            .tripwire(message: "bad args", outputInfo: .dictionary(["field": .string("q")]))
        }
        let runner = GuardrailRunner(observer: observer)

        do {
            _ = try await runner.runToolInputGuardrails([guardrail], data: data)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .toolInputTripwireTriggered(
                guardrailName: "arg_watcher",
                toolName: "lookup",
                message: "bad args",
                outputInfo: .dictionary(["field": .string("q")])
            ))
        }

        let events = await observer.events
        #expect(events == [
            RecordingObserver.Event(name: "arg_watcher", type: .toolInput, message: "bad args")
        ])
    }

    @Test("Sequential tool output run-all collects results and throws first tool-output tripwire")
    func sequentialToolOutputRunAll() async throws {
        let data = ToolGuardrailData(tool: MockTool(name: "lookup"), arguments: [:], agent: MockAgent(), context: nil)
        let pass = ClosureToolOutputGuardrail(name: "shape_check") { _, _ in
            .passed(message: "shape ok")
        }
        let tripA = ClosureToolOutputGuardrail(name: "size_check") { _, _ in
            .tripwire(message: "too big")
        }
        let tripB = ClosureToolOutputGuardrail(name: "pii_check") { _, _ in
            .tripwire(message: "pii found")
        }
        let runner = GuardrailRunner(
            configuration: GuardrailRunnerConfiguration(stopOnFirstTripwire: false)
        )

        do {
            _ = try await runner.runToolOutputGuardrails([pass, tripA, tripB], data: data, output: .string("payload"))
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .toolOutputTripwireTriggered(
                guardrailName: "size_check",
                toolName: "lookup",
                message: "too big",
                outputInfo: nil
            ))
        }
    }

    @Test("Sequential mid-run cancellation aborts remaining guardrails with raw CancellationError")
    func sequentialMidRunCancellation() async throws {
        let gate = ReleaseGate()
        let log = ExecutionLog()
        let first = InputGuard("first_waiter") { _, _ in
            await log.record("first_waiter")
            await gate.waitForRelease()
            return .passed(message: "first ok")
        }
        let second = InputGuard("second_never") { _, _ in
            await log.record("second_never")
            return .passed(message: "second ok")
        }
        let runner = GuardrailRunner(
            configuration: GuardrailRunnerConfiguration(stopOnFirstTripwire: true, timeout: nil)
        )

        let task = Task {
            try await runner.runInputGuardrails([first, second], input: "x", context: nil)
        }
        try await waitForEntries(log, count: 1)
        task.cancel()
        gate.releaseAll()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            #expect(await log.snapshot() == ["first_waiter"])
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Sequential non-GuardrailError is wrapped as executionFailed for every kind")
    func sequentialExecutionFailedWrapping() async throws {
        let boom = InputGuard("in_boom") { _, _ in throw KaboomError() }
        let runner = GuardrailRunner()
        let agent = MockAgent(configuration: AgentConfiguration(name: "wrap-agent"))

        do {
            _ = try await runner.runInputGuardrails([boom], input: "x", context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "in_boom")
            #expect(underlying.contains("KaboomError"))
        }

        let outBoom = OutputGuard("out_boom") { _, _, _ in throw KaboomError() }
        do {
            _ = try await runner.runOutputGuardrails([outBoom], output: "x", agent: agent, context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "out_boom")
            #expect(underlying.contains("KaboomError"))
        }

        let toolInBoom = ClosureToolInputGuardrail(name: "tin_boom") { _ in throw KaboomError() }
        let data = ToolGuardrailData(tool: MockTool(name: "lookup"), arguments: [:], agent: agent, context: nil)
        do {
            _ = try await runner.runToolInputGuardrails([toolInBoom], data: data)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "tin_boom")
            #expect(underlying.contains("KaboomError"))
        }

        let toolOutBoom = ClosureToolOutputGuardrail(name: "tout_boom") { _, _ in throw KaboomError() }
        do {
            _ = try await runner.runToolOutputGuardrails([toolOutBoom], data: data, output: .string("x"))
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "tout_boom")
            #expect(underlying.contains("KaboomError"))
        }
    }
}

// MARK: - Parallel Golden Tests

@Suite("Guardrail Runner Parallel Goldens")
struct GuardrailRunnerParallelGoldens {
    @Test("Parallel stop-on-first throws first completed tripwire with exact payload")
    func parallelStopOnFirstCompletedWins() async throws {
        let fastTrip = OutputGuard("fast_trip") { _, _, _ in
            .tripwire(message: "fast blocked", outputInfo: .dictionary(["which": .string("fast")]))
        }
        let slowPass = OutputGuard("slow_pass") { _, _, _ in
            try? await Task.sleep(for: .milliseconds(80))
            return .passed(message: "late but fine")
        }
        let agent = MockAgent(configuration: AgentConfiguration(name: "par-agent"))
        let runner = GuardrailRunner(configuration: .parallel)

        do {
            _ = try await runner.runOutputGuardrails(
                [slowPass, fastTrip],
                output: "x",
                agent: agent,
                context: nil
            )
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .outputTripwireTriggered(
                guardrailName: "fast_trip",
                agentName: "par-agent",
                message: "fast blocked",
                outputInfo: .dictionary(["which": .string("fast")])
            ))
        }
    }

    @Test("Parallel run-all preserves index-order results and first-by-index error precedence")
    func parallelRunAllIndexOrderPrecedence() async throws {
        let observer = RecordingObserver()
        let slowPass = InputGuard("slow_pass") { _, _ in
            try? await Task.sleep(for: .milliseconds(60))
            return .passed(message: "slow ok")
        }
        let fastPass = InputGuard("fast_pass") { _, _ in
            .passed(message: "fast ok")
        }
        let lateTrip = InputGuard("late_trip") { _, _ in
            try? await Task.sleep(for: .milliseconds(30))
            return .tripwire(message: "late blocked")
        }
        let earlyTrip = InputGuard("early_trip") { _, _ in
            .tripwire(message: "early blocked")
        }
        let runner = GuardrailRunner(
            configuration: GuardrailRunnerConfiguration(runInParallel: true, stopOnFirstTripwire: false),
            observer: observer
        )

        do {
            _ = try await runner.runInputGuardrails([slowPass, fastPass, lateTrip, earlyTrip], input: "x", context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .inputTripwireTriggered(
                guardrailName: "late_trip",
                message: "late blocked",
                outputInfo: nil
            ))
        }

        let events = await observer.events
        #expect(events == [
            RecordingObserver.Event(name: "late_trip", type: .input, message: "late blocked"),
            RecordingObserver.Event(name: "early_trip", type: .input, message: "early blocked"),
        ])
    }

    @Test("Parallel passing sequence returns results in input order for every kind")
    func parallelPassingResultsInInputOrderPerKind() async throws {
        let runner = GuardrailRunner(
            configuration: GuardrailRunnerConfiguration(runInParallel: true)
        )
        let agent = MockAgent(configuration: AgentConfiguration(name: "order-agent"))
        let data = ToolGuardrailData(tool: MockTool(name: "lookup"), arguments: [:], agent: agent, context: nil)

        let inputs: [any InputGuardrail] = [
            InputGuard("i_one") { _, _ in .passed(message: "one") },
            InputGuard("i_two") { _, _ in try? await Task.sleep(for: .milliseconds(20)); return .passed(message: "two") },
        ]
        #expect(try await runner.runInputGuardrails(inputs, input: "x", context: nil).map(\.guardrailName) == ["i_one", "i_two"])

        let outputs: [any OutputGuardrail] = [
            OutputGuard("o_one") { _, _, _ in .passed(message: "one") },
            OutputGuard("o_two") { _, _, _ in try? await Task.sleep(for: .milliseconds(20)); return .passed(message: "two") },
        ]
        #expect(try await runner.runOutputGuardrails(outputs, output: "x", agent: agent, context: nil).map(\.guardrailName) == ["o_one", "o_two"])

        let toolInputs: [any ToolInputGuardrail] = [
            ClosureToolInputGuardrail(name: "ti_one") { _ in .passed(message: "one") },
            ClosureToolInputGuardrail(name: "ti_two") { _ in try? await Task.sleep(for: .milliseconds(20)); return .passed(message: "two") },
        ]
        #expect(try await runner.runToolInputGuardrails(toolInputs, data: data).map(\.guardrailName) == ["ti_one", "ti_two"])

        let toolOutputs: [any ToolOutputGuardrail] = [
            ClosureToolOutputGuardrail(name: "to_one") { _, _ in .passed(message: "one") },
            ClosureToolOutputGuardrail(name: "to_two") { _, _ in try? await Task.sleep(for: .milliseconds(20)); return .passed(message: "two") },
        ]
        #expect(try await runner.runToolOutputGuardrails(toolOutputs, data: data, output: .string("y")).map(\.guardrailName) == ["to_one", "to_two"])
    }

    @Test("Parallel tool input stop-on-first emits single event and exact tool payload")
    func parallelToolInputStopOnFirst() async throws {
        let observer = RecordingObserver()
        let data = ToolGuardrailData(
            tool: MockTool(name: "search"),
            arguments: [:],
            agent: MockAgent(),
            context: AgentContext(input: "parallel tools")
        )
        let blocker = ClosureToolInputGuardrail(name: "deny_all") { _ in
            .tripwire(message: "denied")
        }
        let runner = GuardrailRunner(configuration: .parallel, observer: observer)

        do {
            _ = try await runner.runToolInputGuardrails([blocker], data: data)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            #expect(error == .toolInputTripwireTriggered(
                guardrailName: "deny_all",
                toolName: "search",
                message: "denied",
                outputInfo: nil
            ))
        }

        let events = await observer.events
        #expect(events == [RecordingObserver.Event(name: "deny_all", type: .toolInput, message: "denied")])
    }

    @Test("Parallel mid-flight cancellation lets spawned guardrails finish and returns ordered results")
    func parallelMidFlightCancellationStillCompletes() async throws {
        let gate = ReleaseGate()
        let log = ExecutionLog()
        let slow = InputGuard("slow_waiter") { _, _ in
            await log.record("slow_waiter")
            await gate.waitForRelease()
            return .passed(message: "survived")
        }
        let quick = InputGuard("quick_pass") { _, _ in
            await log.record("quick_pass")
            return .passed(message: "quick ok")
        }
        let runner = GuardrailRunner(
            configuration: GuardrailRunnerConfiguration(runInParallel: true, timeout: nil)
        )

        let task = Task {
            try await runner.runInputGuardrails([slow, quick], input: "x", context: nil)
        }
        try await waitForEntries(log, count: 2)
        task.cancel()
        gate.releaseAll()

        let results = try await task.value
        #expect(results.map(\.guardrailName) == ["slow_waiter", "quick_pass"])
    }

    @Test("Parallel non-GuardrailError is wrapped as executionFailed for every kind")
    func parallelExecutionFailedWrapping() async throws {
        let runner = GuardrailRunner(configuration: .parallel)
        let agent = MockAgent(configuration: AgentConfiguration(name: "par-wrap"))
        let data = ToolGuardrailData(tool: MockTool(name: "lookup"), arguments: [:], agent: agent, context: nil)

        do {
            _ = try await runner.runInputGuardrails([InputGuard("pin_boom") { _, _ in throw KaboomError() }], input: "x", context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "pin_boom")
            #expect(underlying.contains("KaboomError"))
        }

        do {
            _ = try await runner.runOutputGuardrails([OutputGuard("pout_boom") { _, _, _ in throw KaboomError() }], output: "x", agent: agent, context: nil)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "pout_boom")
            #expect(underlying.contains("KaboomError"))
        }

        do {
            _ = try await runner.runToolInputGuardrails([ClosureToolInputGuardrail(name: "ptin_boom") { _ in throw KaboomError() }], data: data)
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "ptin_boom")
            #expect(underlying.contains("KaboomError"))
        }

        do {
            _ = try await runner.runToolOutputGuardrails([ClosureToolOutputGuardrail(name: "ptout_boom") { _, _ in throw KaboomError() }], data: data, output: .string("x"))
            Issue.record("Expected GuardrailError")
        } catch let error as GuardrailError {
            guard case let .executionFailed(name, underlying) = error else {
                Issue.record("Unexpected case: \(error)")
                return
            }
            #expect(name == "ptout_boom")
            #expect(underlying.contains("KaboomError"))
        }
    }

    @Test("Empty guardrail arrays return empty results in both styles for every kind")
    func emptyArraysReturnEmptyResults() async throws {
        let sequential = GuardrailRunner()
        let parallel = GuardrailRunner(configuration: .parallel)
        let agent = MockAgent()
        let data = ToolGuardrailData(tool: MockTool(), arguments: [:], agent: agent, context: nil)

        for runner in [sequential, parallel] {
            #expect(try await runner.runInputGuardrails([], input: "x", context: nil).isEmpty)
            #expect(try await runner.runOutputGuardrails([], output: "x", agent: agent, context: nil).isEmpty)
            #expect(try await runner.runToolInputGuardrails([], data: data).isEmpty)
            #expect(try await runner.runToolOutputGuardrails([], data: data, output: .string("x")).isEmpty)
        }
    }
}
