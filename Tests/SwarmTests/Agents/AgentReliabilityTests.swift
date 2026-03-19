import Foundation
@testable import Swarm
import Testing

@Suite("Agent Reliability Tests")
struct AgentReliabilityTests {
    @Test("Agent.cancel() terminates in-flight run promptly")
    func agentInstanceCancelTerminatesInflightRun() async throws {
        let provider = HangingInferenceProvider(delay: .seconds(2))
        let agent = try Agent(
            tools: [],
            instructions: "Cancellation test agent",
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("cancel me")
        }

        try await Task.sleep(for: .milliseconds(50))
        await agent.cancel()

        let completion = await awaitTaskResult(runTask, timeout: .milliseconds(500))
        guard let completion else {
            runTask.cancel()
            Issue.record("Agent run did not stop promptly after agent.cancel()")
            return
        }

        switch completion {
        case .success:
            Issue.record("Expected cancellation error after agent.cancel(), but run succeeded")
        case let .failure(error as AgentError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected AgentError.cancelled after agent.cancel(), got \(error)")
        }
    }

    @Test("Task cancellation terminates in-flight run promptly")
    func taskCancelTerminatesInflightRun() async throws {
        let provider = HangingInferenceProvider(delay: .seconds(2))
        let agent = try Agent(
            tools: [],
            instructions: "Cancellation test agent",
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("cancel me")
        }

        try await Task.sleep(for: .milliseconds(50))
        runTask.cancel()

        let completion = await awaitTaskResult(runTask, timeout: .milliseconds(500))
        guard let completion else {
            runTask.cancel()
            Issue.record("Agent run did not stop promptly after cancel()")
            return
        }

        switch completion {
        case .success:
            Issue.record("Expected cancellation error but run succeeded")
        case let .failure(error as AgentError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected AgentError.cancelled, got \(error)")
        }
    }

    @Test("Agent timeout terminates in-flight provider work promptly")
    func timeoutTerminatesInflightProviderWork() async throws {
        let provider = HangingInferenceProvider(delay: .seconds(2))
        let agent = try Agent(
            tools: [],
            instructions: "Timeout test agent",
            configuration: .default.timeout(.milliseconds(50)),
            inferenceProvider: provider
        )

        let runTask = Task {
            try await agent.run("time out")
        }

        let completion = await awaitTaskResult(runTask, timeout: .milliseconds(500))
        guard let completion else {
            runTask.cancel()
            Issue.record("Agent run did not stop promptly after timing out")
            return
        }

        switch completion {
        case .success:
            Issue.record("Expected timeout error but run succeeded")
        case let .failure(error as AgentError):
            #expect(error == .timeout(duration: .milliseconds(50)))
        case let .failure(error):
            Issue.record("Expected AgentError.timeout, got \(error)")
        }
    }

    @Test("Agent emits onIterationEnd for terminal no-tool return")
    func agentAlwaysEmitsIterationEndOnTerminalReturn() async throws {
        let provider = MockInferenceProvider(responses: ["terminal output"])
        let observer = IterationRecordingObserver()
        let agent = try Agent(
            tools: [],
            instructions: "Iteration hook test agent",
            inferenceProvider: provider
        )

        _ = try await agent.run("test", observer: observer)
        let recorded = await observer.recorded()

        #expect(recorded.started == [1])
        #expect(recorded.ended == [1])
    }

    @Test("Agent emits onIterationEnd for terminal final-answer return")
    func reactAlwaysEmitsIterationEndOnTerminalReturn() async throws {
        let provider = MockInferenceProvider(responses: ["Final Answer: done"])
        let observer = IterationRecordingObserver()
        let agent = try Agent(
            tools: [],
            instructions: "Iteration hook test ReAct agent",
            inferenceProvider: provider
        )

        _ = try await agent.run("test", observer: observer)
        let recorded = await observer.recorded()

        #expect(recorded.started == [1])
        #expect(recorded.ended == [1])
    }
}

private actor IterationRecordingObserver: AgentObserver {
    private var started: [Int] = []
    private var ended: [Int] = []

    func onIterationStart(context _: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        started.append(number)
    }

    func onIterationEnd(context _: AgentContext?, agent _: any AgentRuntime, number: Int) async {
        ended.append(number)
    }

    func recorded() -> (started: [Int], ended: [Int]) {
        (started, ended)
    }
}

private actor HangingInferenceProvider: InferenceProvider {
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        try await Task.sleep(for: delay)
        return "Final Answer: delayed"
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            let token = try await self.generate(prompt: prompt, options: options)
            continuation.yield(token)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools _: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        let content = try await generate(prompt: prompt, options: options)
        return InferenceResponse(content: content, finishReason: .completed)
    }
}

private func awaitTaskResult<T: Sendable>(
    _ task: Task<T, Error>,
    timeout: Duration
) async -> Result<T, Error>? {
    await withTaskGroup(of: Result<T, Error>?.self) { group in
        group.addTask {
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }

        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }

        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
