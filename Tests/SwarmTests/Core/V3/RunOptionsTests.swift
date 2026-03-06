// RunOptionsTests.swift
// Tests for the V3 RunOptions struct.

@testable import Swarm
import Testing

@Suite("RunOptions")
struct RunOptionsTests {
    @Test("Default values")
    func defaults() {
        let opts = RunOptions.default
        #expect(opts.maxIterations == 10)
        #expect(opts.timeout == .seconds(60))
        #expect(opts.temperature == 1.0)
        #expect(opts.maxTokens == nil)
        #expect(opts.stream == true)
        #expect(opts.parallelTools == false)
    }

    @Test("Creative preset")
    func creative() {
        let opts = RunOptions.creative
        #expect(opts.temperature == 1.5)
        #expect(opts.maxIterations == 10) // other defaults unchanged
    }

    @Test("Precise preset")
    func precise() {
        let opts = RunOptions.precise
        #expect(opts.temperature == 0.2)
    }

    @Test("Fast preset")
    func fast() {
        let opts = RunOptions.fast
        #expect(opts.maxIterations == 3)
        #expect(opts.timeout == .seconds(15))
    }

    @Test("maxIterations clamped to 1")
    func maxIterationsClamped() {
        let opts = RunOptions(maxIterations: -5)
        #expect(opts.maxIterations == 1)
    }

    @Test("Zero maxIterations clamped to 1")
    func zeroMaxIterations() {
        let opts = RunOptions(maxIterations: 0)
        #expect(opts.maxIterations == 1)
    }

    @Test("Negative timeout falls back to 60s")
    func negativeTimeout() {
        let opts = RunOptions(timeout: .seconds(-10))
        #expect(opts.timeout == .seconds(60))
    }

    @Test("Zero timeout falls back to 60s")
    func zeroTimeout() {
        let opts = RunOptions(timeout: .zero)
        #expect(opts.timeout == .seconds(60))
    }

    @Test("Out-of-range temperature falls back to 1.0")
    func outOfRangeTemperature() {
        let high = RunOptions(temperature: 3.0)
        #expect(high.temperature == 1.0)

        let negative = RunOptions(temperature: -0.5)
        #expect(negative.temperature == 1.0)
    }

    @Test("Non-finite temperature falls back to 1.0")
    func nonFiniteTemperature() {
        let inf = RunOptions(temperature: .infinity)
        #expect(inf.temperature == 1.0)

        let nan = RunOptions(temperature: .nan)
        #expect(nan.temperature == 1.0)
    }

    @Test("Equatable conformance")
    func equatable() {
        #expect(RunOptions.default == RunOptions())
        #expect(RunOptions.creative != RunOptions.precise)
        #expect(RunOptions(maxIterations: 5) != RunOptions(maxIterations: 10))
    }
}
