import Foundation
@testable import Swarm
import Testing

@Suite("Stream operation delivery")
struct StreamOperationsDeliveryTests {
    private static let eventCount = 300

    @Test("Operators keep every event when the consumer is slow", arguments: StreamOperator.allCases)
    func operatorsKeepEveryEvent(_ streamOperator: StreamOperator) async throws {
        let operated = streamOperator.apply(to: Self.finishedSource(count: Self.eventCount))

        // Let the operator drain its upstream before anything is consumed.
        try await Task.sleep(for: .milliseconds(200))

        let events = try await operated.collect()
        #expect(events.count == Self.eventCount)
        #expect(Self.iterationNumbers(events) == Array(1...Self.eventCount))
    }

    @Test("EnvironmentAgent.stream keeps every event when the consumer is slow")
    func environmentAgentKeepsEveryEvent() async throws {
        let base = BurstStreamingAgent(eventCount: Self.eventCount)
        let agent = EnvironmentAgent(base: base) { _ in }

        let stream = agent.stream("go", session: nil, observer: nil)
        try await Task.sleep(for: .milliseconds(200))

        let events = try await stream.collect()
        #expect(Self.iterationNumbers(events) == Array(1...Self.eventCount))
    }

    @Test("throttle always delivers terminal events")
    func throttleDeliversTerminalEvents() async throws {
        let (source, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream(bufferingPolicy: .unbounded)
        continuation.yield(.lifecycle(.started(input: "go")))
        continuation.yield(.output(.token("a")))
        continuation.yield(.lifecycle(.completed(result: AgentResult(output: "a"))))
        continuation.finish()

        let events = try await source.throttle(for: .seconds(10)).collect()

        #expect(events.count == 2)
        guard case .lifecycle(.completed) = events.last else {
            Issue.record("Expected the completed event to be delivered, got \(String(describing: events.last))")
            return
        }
    }

    @Test("debounce emits after a quiet period without waiting for the next event")
    func debounceEmitsOnTimer() async throws {
        let (source, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream(bufferingPolicy: .unbounded)
        let received = EventBox()
        let consumer = Task {
            for try await event in source.debounce(for: .milliseconds(50)) {
                await received.append(event)
            }
        }

        continuation.yield(.output(.token("a")))
        continuation.yield(.output(.token("b")))
        // Upstream stays open: only a timer can emit "b" now.
        var tokens: [String] = []
        for _ in 0..<200 {
            tokens = await received.tokens
            if !tokens.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(tokens == ["b"])

        continuation.finish()
        try await consumer.value
    }

    @Test("debounce flushes the pending event at stream end and delivers terminal events")
    func debounceFlushesAtEnd() async throws {
        let (source, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream(bufferingPolicy: .unbounded)
        continuation.yield(.output(.token("a")))
        continuation.yield(.lifecycle(.completed(result: AgentResult(output: "a"))))
        continuation.yield(.output(.token("tail")))
        continuation.finish()

        let events = try await source.debounce(for: .seconds(10)).collect()

        #expect(events.count == 3)
        guard events.count == 3, case .lifecycle(.completed) = events[1],
              case .output(.token("tail")) = events[2]
        else {
            Issue.record("Unexpected debounced events: \(events)")
            return
        }
    }

    // MARK: - Helpers

    private static func finishedSource(count: Int) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream(bufferingPolicy: .unbounded)
        for number in 1...count {
            continuation.yield(.lifecycle(.iterationStarted(number: number)))
        }
        continuation.finish()
        return stream
    }

    fileprivate static func iterationNumbers(_ events: [AgentEvent]) -> [Int] {
        events.compactMap { event in
            if case let .lifecycle(.iterationStarted(number)) = event { number } else { nil }
        }
    }
}

enum StreamOperator: CaseIterable, Sendable {
    case filter, map, onEach, take, drop, timeout, catchErrors, retry, distinctUntilChanged

    func apply(to source: AsyncThrowingStream<AgentEvent, Error>) -> AsyncThrowingStream<AgentEvent, Error> {
        switch self {
        case .filter: source.filter { _ in true }
        case .map: source.map { $0 }
        case .onEach: source.onEach { _ in }
        case .take: source.take(Int.max)
        case .drop: source.drop(0)
        case .timeout: source.timeout(after: .seconds(60))
        case .catchErrors: source.catchErrors { _ in .lifecycle(.cancelled) }
        case .retry: AsyncThrowingStream<AgentEvent, Error>.retry(maxAttempts: 1) { source }
        case .distinctUntilChanged: source.distinctUntilChanged()
        }
    }
}

private actor EventBox {
    private var events: [AgentEvent] = []

    func append(_ event: AgentEvent) {
        events.append(event)
    }

    var tokens: [String] {
        events.compactMap { event in
            if case let .output(.token(token)) = event { token } else { nil }
        }
    }
}

/// Runtime whose stream yields a burst of events as fast as possible.
private struct BurstStreamingAgent: AgentRuntime {
    let eventCount: Int

    var tools: [any AnyJSONTool] { [] }
    var instructions: String { "" }
    var configuration: AgentConfiguration { .default }

    func run(_: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        AgentResult(output: "")
    }

    nonisolated func stream(
        _: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<AgentEvent, Error>.makeStream(bufferingPolicy: .unbounded)
        for number in 1...eventCount {
            continuation.yield(.lifecycle(.iterationStarted(number: number)))
        }
        continuation.finish()
        return stream
    }

    func cancel() async {}
}
