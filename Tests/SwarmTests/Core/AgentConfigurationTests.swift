// AgentConfigurationTests.swift
// SwarmTests
//
// Mutation-proof write-path tests for AgentConfiguration: post-initialization
// property writes (and builder writes, which mutate a copy) must self-correct
// exactly like initializer-time coercion.
//
// Initializer and general fluent-builder coverage lives in CoreTests.swift
// (`AgentConfigurationTests` suite); this file covers write-path coercion only.

import Foundation
@testable import Swarm
import Testing

// MARK: - AgentConfigurationPostInitClampTests

@Suite("AgentConfiguration Post-Init Clamp Tests")
struct AgentConfigurationPostInitClampTests {
    @Test("Writing zero maxIterations self-corrects to 1")
    func zeroMaxIterationsSelfCorrects() {
        var config = AgentConfiguration.default
        config.maxIterations = 0
        #expect(config.maxIterations == 1)
    }

    @Test("Writing negative maxIterations self-corrects to 1")
    func negativeMaxIterationsSelfCorrects() {
        var config = AgentConfiguration.default
        config.maxIterations = -7
        #expect(config.maxIterations == 1)
    }

    @Test("Builder write of zero maxIterations self-corrects to 1")
    func builderZeroMaxIterationsSelfCorrects() {
        let config = AgentConfiguration.default.maxIterations(0)
        #expect(config.maxIterations == 1)
    }

    @Test("Writing zero timeout falls back to the 60 second default")
    func zeroTimeoutFallsBackToDefault() {
        var config = AgentConfiguration.default
        config.timeout = .zero
        #expect(config.timeout == .seconds(60))
    }

    @Test("Writing a negative timeout falls back to the 60 second default")
    func negativeTimeoutFallsBackToDefault() {
        var config = AgentConfiguration.default
        config.timeout = .seconds(-30)
        #expect(config.timeout == .seconds(60))
    }

    @Test("Writing an out-of-range temperature falls back to 1.0")
    func outOfRangeTemperatureFallsBackToDefault() {
        var config = AgentConfiguration.default

        config.temperature = 99.0
        #expect(config.temperature == 1.0)

        config.temperature = -0.5
        #expect(config.temperature == 1.0)

        config.temperature = .infinity
        #expect(config.temperature == 1.0)
    }

    @Test("Boundary temperatures survive writes unchanged")
    func boundaryTemperaturesSurvive() {
        var config = AgentConfiguration.default

        config.temperature = 0.0
        #expect(config.temperature == 0.0)

        config.temperature = 2.0
        #expect(config.temperature == 2.0)
    }

    @Test("Coerced writes leave other fields untouched")
    func coercedWriteLeavesOtherFieldsUntouched() {
        var config = AgentConfiguration.default
        config.maxIterations = -1

        #expect(config.maxIterations == 1)
        #expect(config.timeout == .seconds(60))
        #expect(config.temperature == 1.0)
        #expect(config.enableStreaming == true)
        #expect(config.name == "Agent")
    }
}
