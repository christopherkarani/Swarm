// BackoffStrategyTotalityTests.swift
// Swarm Framework
//
// Property-style tests proving BackoffStrategy.delay(forAttempt:) is total:
// no input traps, and every result is a finite, non-negative delay.

import Foundation
@_spi(ColonyInternal) @testable import Swarm
import Testing

@Suite("BackoffStrategy Totality Tests")
struct BackoffStrategyTotalityTests {
    /// Edge values for every `TimeInterval` / `Double` strategy parameter.
    private static let edgeValues: [Double] = [
        -.infinity, -.greatestFiniteMagnitude, -1, -.leastNonzeroMagnitude, -0.0, 0,
        .leastNonzeroMagnitude, 1e-300, 0.5, 1, 2, 3, 1e300, .greatestFiniteMagnitude, .infinity, .nan,
    ]

    /// Edge attempt numbers, including values whose `attempt - 1` would overflow.
    private static let edgeAttempts: [Int] = [.min, -1, 0, 1, 2, 3, 64, 1100, .max]

    private static func expectTotal(
        _ strategy: BackoffStrategy,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) {
        for attempt in edgeAttempts {
            let delay = strategy.delay(forAttempt: attempt)
            #expect(delay.isFinite, "\(strategy) attempt \(attempt) -> \(delay)", sourceLocation: sourceLocation)
            #expect(delay >= 0, "\(strategy) attempt \(attempt) -> \(delay)", sourceLocation: sourceLocation)
        }
    }

    @Test("fixed and custom delays are finite and non-negative for every edge value")
    func fixedAndCustomAreTotal() {
        for value in Self.edgeValues {
            Self.expectTotal(.fixed(delay: value))
            Self.expectTotal(.custom { _ in value })
        }
    }

    @Test("Non-finite or negative delays and custom results mean no delay")
    func invalidDelaysMeanNoDelay() {
        for value: Double in [-.infinity, -1, .nan, .infinity] {
            #expect(BackoffStrategy.fixed(delay: value).delay(forAttempt: 1) == 0)
            #expect(BackoffStrategy.custom { _ in value }.delay(forAttempt: 1) == 0)
        }
        #expect(BackoffStrategy.exponential(base: 1, multiplier: 2, maxDelay: .infinity).delay(forAttempt: 4) == 8)
    }

    @Test("linear delays are finite and non-negative for every edge combination")
    func linearIsTotal() {
        for initial in Self.edgeValues {
            for increment in Self.edgeValues {
                for maxDelay in Self.edgeValues {
                    Self.expectTotal(.linear(initial: initial, increment: increment, maxDelay: maxDelay))
                }
            }
        }
    }

    @Test("exponential delays are finite and non-negative for every edge combination")
    func exponentialIsTotal() {
        for base in Self.edgeValues {
            for multiplier in Self.edgeValues {
                for maxDelay in Self.edgeValues {
                    Self.expectTotal(.exponential(base: base, multiplier: multiplier, maxDelay: maxDelay))
                }
            }
        }
    }

    @Test("exponentialWithJitter never traps and stays within 0...maxDelay")
    func exponentialWithJitterIsTotal() {
        for base in Self.edgeValues {
            for multiplier in Self.edgeValues {
                for maxDelay in Self.edgeValues {
                    let strategy = BackoffStrategy.exponentialWithJitter(
                        base: base, multiplier: multiplier, maxDelay: maxDelay
                    )
                    Self.expectTotal(strategy)
                    if maxDelay.isFinite, maxDelay >= 0 {
                        for attempt in Self.edgeAttempts {
                            #expect(strategy.delay(forAttempt: attempt) <= maxDelay)
                        }
                    }
                }
            }
        }
    }

    @Test("decorrelatedJitter never traps and stays within 0...maxDelay")
    func decorrelatedJitterIsTotal() {
        for base in Self.edgeValues {
            for maxDelay in Self.edgeValues {
                let strategy = BackoffStrategy.decorrelatedJitter(base: base, maxDelay: maxDelay)
                Self.expectTotal(strategy)
                if maxDelay.isFinite, maxDelay >= 0 {
                    for attempt in Self.edgeAttempts {
                        #expect(strategy.delay(forAttempt: attempt) <= maxDelay)
                    }
                }
            }
        }
    }

    @Test("Negative maxDelay with jitter retries without trapping (reported crash)")
    func negativeMaxDelayJitterRetries() async throws {
        let clock = VirtualClock()
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .exponentialWithJitter(base: 1, multiplier: 2, maxDelay: -1),
            clock: clock
        )
        let counter = TestCounter()

        await #expect(throws: ResilienceError.self) {
            try await policy.execute { () async throws -> Int in
                _ = await counter.increment()
                throw AgentError.generationFailed(reason: "boom")
            }
        }
        #expect(await counter.get() == 3)
        // A negative cap clamps to zero, so no sleep is requested.
        #expect(clock.recordedSleeps.isEmpty)
    }

    @Test("Overflowing uncapped jitter saturates to the one-hour sleep ceiling")
    func overflowingUncappedJitterSaturates() async throws {
        let clock = VirtualClock()
        let policy = RetryPolicy(
            maxAttempts: 2,
            backoff: .exponentialWithJitter(base: .greatestFiniteMagnitude, multiplier: 2, maxDelay: .infinity),
            clock: clock,
            random: { $0.upperBound }
        )

        await #expect(throws: ResilienceError.self) {
            try await policy.execute { () async throws -> Int in
                throw AgentError.generationFailed(reason: "boom")
            }
        }
        #expect(clock.recordedSleeps == [3_600_000_000_000])
    }
}
