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

    @Test("Writing an out-of-range temperature clamps through ModelSettings")
    func outOfRangeTemperatureClamps() {
        #expect(AgentConfiguration.default.temperature(99.0).modelSettings.temperature == 2.0)
        #expect(AgentConfiguration.default.temperature(-0.5).modelSettings.temperature == 0.0)
        #expect(AgentConfiguration.default.temperature(.nan).modelSettings.temperature == nil)
    }

    @Test("Boundary temperatures survive writes unchanged")
    func boundaryTemperaturesSurvive() {
        var config = AgentConfiguration.default

        config.modelSettings.temperature = 0.0
        #expect(config.modelSettings.temperature == 0.0)

        config.modelSettings.temperature = 2.0
        #expect(config.modelSettings.temperature == 2.0)
    }

    @Test("Coerced writes leave other fields untouched")
    func coercedWriteLeavesOtherFieldsUntouched() {
        var config = AgentConfiguration.default
        config.maxIterations = -1

        #expect(config.maxIterations == 1)
        #expect(config.timeout == .seconds(60))
        #expect(config.modelSettings == ModelSettings())
        #expect(config.enableStreaming == true)
        #expect(config.name == "Agent")
    }
}

// MARK: - InferencePolicyPostInitClampTests

@Suite("InferencePolicy Post-Init Clamp Tests")
struct InferencePolicyPostInitClampTests {
    @Test("Initializer drops non-positive tokenBudget")
    func initializerDropsNonPositiveTokenBudget() {
        #expect(InferencePolicy(tokenBudget: -5).tokenBudget == nil)
        #expect(InferencePolicy(tokenBudget: 0).tokenBudget == nil)
        #expect(InferencePolicy(tokenBudget: 500).tokenBudget == 500)
        #expect(InferencePolicy().tokenBudget == nil)
    }

    @Test("Writing a non-positive tokenBudget drops the value on read")
    func nonPositiveTokenBudgetWriteDrops() {
        var policy = InferencePolicy(tokenBudget: 500)

        policy.tokenBudget = -5
        #expect(policy.tokenBudget == nil)

        policy.tokenBudget = 0
        #expect(policy.tokenBudget == nil)
    }

    @Test("Writing a positive tokenBudget survives unchanged")
    func positiveTokenBudgetWriteSurvives() {
        var policy = InferencePolicy()
        policy.tokenBudget = 250
        #expect(policy.tokenBudget == 250)
    }
}
