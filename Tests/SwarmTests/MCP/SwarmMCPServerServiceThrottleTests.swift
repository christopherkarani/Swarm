#if SWARM_MCP
import Foundation
import MCP
@_spi(ColonyInternal) @testable import Swarm
@testable import SwarmMCP
import Testing

// MARK: - Pure admission table

@Suite("SwarmMCPServerService throttle admission")
struct SwarmMCPServerServiceThrottleAdmissionTests {
    private static let halfSecond: UInt64 = 500_000_000

    struct Row: Sendable, CustomTestStringConvertible {
        let label: String
        let start: SwarmMCPThrottle
        let now: UInt64
        let expected: SwarmMCPThrottle.Decision
        let expectedTokens: Double
        let expectedActive: Int

        var testDescription: String { label }
    }

    static let rows: [Row] = [
        Row(
            label: "full bucket admits and consumes one token",
            start: SwarmMCPThrottle(maxRequestsPerSecond: 2, maxConcurrentRequests: 5, nowNanoseconds: 0),
            now: 0,
            expected: .admitted,
            expectedTokens: 1,
            expectedActive: 1
        ),
        Row(
            label: "empty bucket rejects without consuming or counting in-flight",
            start: SwarmMCPThrottle(
                maxRequestsPerSecond: 2, maxConcurrentRequests: 5, tokens: 0.5,
                lastRefillNanoseconds: 0, activeRequests: 0
            ),
            now: 0,
            expected: .rateLimited,
            expectedTokens: 0.5,
            expectedActive: 0
        ),
        Row(
            label: "1/rate of elapsed time refills exactly one token",
            start: SwarmMCPThrottle(
                maxRequestsPerSecond: 2, maxConcurrentRequests: 5, tokens: 0,
                lastRefillNanoseconds: 0, activeRequests: 0
            ),
            now: halfSecond,
            expected: .admitted,
            expectedTokens: 0,
            expectedActive: 1
        ),
        Row(
            label: "refill is capped at bucket capacity",
            start: SwarmMCPThrottle(
                maxRequestsPerSecond: 2, maxConcurrentRequests: 5, tokens: 0,
                lastRefillNanoseconds: 0, activeRequests: 0
            ),
            now: 60_000_000_000,
            expected: .admitted,
            expectedTokens: 1,
            expectedActive: 1
        ),
        Row(
            label: "in-flight cap rejects when tokens remain",
            start: SwarmMCPThrottle(
                maxRequestsPerSecond: 2, maxConcurrentRequests: 1, tokens: 2,
                lastRefillNanoseconds: 0, activeRequests: 1
            ),
            now: 0,
            expected: .concurrencyLimited,
            expectedTokens: 2,
            expectedActive: 1
        ),
        Row(
            label: "rate limit is checked before the in-flight cap",
            start: SwarmMCPThrottle(
                maxRequestsPerSecond: 2, maxConcurrentRequests: 1, tokens: 0,
                lastRefillNanoseconds: 0, activeRequests: 1
            ),
            now: 0,
            expected: .rateLimited,
            expectedTokens: 0,
            expectedActive: 1
        ),
    ]

    @Test("Admission decision table", arguments: rows)
    func admissionTable(_ row: Row) {
        let (decision, next) = row.start.admitting(atNanoseconds: row.now)

        #expect(decision == row.expected)
        #expect(next.tokens == row.expectedTokens)
        #expect(next.activeRequests == row.expectedActive)
        #expect(next.lastRefillNanoseconds == row.now)
    }

    @Test("Release frees one in-flight slot and never goes negative")
    func releaseFloorsAtZero() {
        let busy = SwarmMCPThrottle(
            maxRequestsPerSecond: 2, maxConcurrentRequests: 1, tokens: 1,
            lastRefillNanoseconds: 0, activeRequests: 1
        )

        #expect(busy.releasing().activeRequests == 0)
        #expect(busy.releasing().releasing().activeRequests == 0)
    }

    @Test("Burst beyond capacity is rejected until 1/rate elapses")
    func burstThenRefill() {
        let fresh = SwarmMCPThrottle(maxRequestsPerSecond: 2, maxConcurrentRequests: 100, nowNanoseconds: 0)

        let (first, afterFirst) = fresh.admitting(atNanoseconds: 0)
        let (second, afterSecond) = afterFirst.admitting(atNanoseconds: 0)
        let (third, afterThird) = afterSecond.admitting(atNanoseconds: 0)
        let (fourth, _) = afterThird.admitting(atNanoseconds: Self.halfSecond)

        #expect([first, second, third, fourth] == [.admitted, .admitted, .rateLimited, .admitted])
    }
}

// MARK: - Service integration over a virtual clock

@Suite("SwarmMCPServerService throttle")
struct SwarmMCPServerServiceThrottleTests {
    @Test("Burst beyond capacity is rejected; advancing the clock by 1/rate admits again")
    func burstRejectedThenAdmittedAfterRefill() async throws {
        let clock = VirtualClock()
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "noop", description: "noop", parameters: [])]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in .null }
        let harness = try await SwarmMCPTestHarness.make(
            catalog: catalog,
            executor: executor,
            maxRequestsPerSecond: 2,
            maxConcurrentRequests: 100,
            clock: clock
        )
        defer {
            Task { await harness.shutdown() }
        }

        _ = try await harness.client.listTools()
        _ = try await harness.client.listTools()
        await expectRateLimited("too many requests") {
            _ = try await harness.client.listTools()
        }

        clock.advance(by: .milliseconds(500))
        let listed = try await harness.client.listTools()

        #expect(listed.tools.map(\.name) == ["noop"])
        #expect(await harness.service.snapshotMetrics().listToolsRequests == 3)
    }

    @Test("Concurrency cap rejects the N+1th in-flight request and frees the slot on completion")
    func concurrencyCapRejectsExtraInFlightRequest() async throws {
        let clock = VirtualClock()
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "slow", description: "slow", parameters: [])]
        )
        let (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let executor = SwarmMCPToolExecutorStub { _, _ in
            enteredContinuation.yield()
            for await _ in release {
                break
            }
            return .string("done")
        }
        let harness = try await SwarmMCPTestHarness.make(
            catalog: catalog,
            executor: executor,
            maxRequestsPerSecond: 100,
            maxConcurrentRequests: 1,
            clock: clock
        )
        defer {
            Task { await harness.shutdown() }
        }

        async let inFlight = harness.client.callTool(name: "slow", arguments: nil)
        var enteredIterator = entered.makeAsyncIterator()
        _ = await enteredIterator.next()

        await expectRateLimited("too many concurrent requests") {
            _ = try await harness.client.listTools()
        }

        releaseContinuation.yield()
        let completed = try await inFlight
        #expect(completed.isError != true)

        let listed = try await harness.client.listTools()
        #expect(listed.tools.map(\.name) == ["slow"])
    }
}

private func expectRateLimited(
    _ reason: String,
    sourceLocation: Testing.SourceLocation = #_sourceLocation,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("Expected rate-limit rejection", sourceLocation: sourceLocation)
    } catch let error as MCP.MCPError {
        #expect(error.code == MCP.MCPError.invalidRequest(nil).code, sourceLocation: sourceLocation)
        #expect((error.errorDescription ?? "").contains(reason), sourceLocation: sourceLocation)
    } catch {
        Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
    }
}
#endif
