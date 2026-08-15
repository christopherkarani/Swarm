// ReasoningConfigTests.swift
// SwarmTests
//
// Tests for ReasoningConfig and ReasoningEffort.

import Foundation
@testable import Swarm
import Testing

// MARK: - ReasoningConfigInitializationTests

@Suite("ReasoningConfig Initialization Tests")
struct ReasoningConfigInitializationTests {
    @Test("Default initialization - all values are nil")
    func defaultInitialization() {
        let config = ReasoningConfig()

        #expect(config.effort == nil)
        #expect(config.maxTokens == nil)
        #expect(config.exclude == nil)
        #expect(config.enabled == nil)
    }

    @Test("Full initialization - all values set")
    func fullInitialization() {
        let config = ReasoningConfig(
            effort: .high,
            maxTokens: 4096,
            exclude: true,
            enabled: false
        )

        #expect(config.effort == .high)
        #expect(config.maxTokens == 4096)
        #expect(config.exclude == true)
        #expect(config.enabled == false)
    }

    @Test("Partial initialization - only effort")
    func partialInitializationEffort() {
        let config = ReasoningConfig(effort: .low)

        #expect(config.effort == .low)
        #expect(config.maxTokens == nil)
        #expect(config.exclude == nil)
        #expect(config.enabled == nil)
    }
}

// MARK: - ReasoningConfigCodableTests

@Suite("ReasoningConfig Codable Tests")
struct ReasoningConfigCodableTests {
    @Test("Encoding and decoding with all properties")
    func fullCodable() throws {
        let original = ReasoningConfig(
            effort: .medium,
            maxTokens: 2048,
            exclude: true,
            enabled: true
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReasoningConfig.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.effort == .medium)
        #expect(decoded.maxTokens == 2048)
        #expect(decoded.exclude == true)
        #expect(decoded.enabled == true)
    }

    @Test("Encoding and decoding with nil values")
    func codableWithNilValues() throws {
        let original = ReasoningConfig()

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReasoningConfig.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Encoding and decoding with ReasoningEffort.none")
    func codableWithNoneEffort() throws {
        let original = ReasoningConfig(effort: ReasoningEffort.none)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReasoningConfig.self, from: encoded)

        #expect(decoded.effort == ReasoningEffort.none)
        #expect(decoded == original)
    }

    @Test("Decoding partial JSON with only effort set")
    func decodePartialJSON() throws {
        let json = Data(#"{"effort":"high"}"#.utf8)
        let decoded = try JSONDecoder().decode(ReasoningConfig.self, from: json)

        #expect(decoded.effort == .high)
        #expect(decoded.maxTokens == nil)
        #expect(decoded.exclude == nil)
        #expect(decoded.enabled == nil)
    }

    @Test("Decoding partial JSON with only maxTokens set")
    func decodePartialJSONMaxTokens() throws {
        let json = Data(#"{"maxTokens":2048}"#.utf8)
        let decoded = try JSONDecoder().decode(ReasoningConfig.self, from: json)

        #expect(decoded.effort == nil)
        #expect(decoded.maxTokens == 2048)
        #expect(decoded.exclude == nil)
        #expect(decoded.enabled == nil)
    }
}

// MARK: - ReasoningConfigEquatableTests

@Suite("ReasoningConfig Equatable Tests")
struct ReasoningConfigEquatableTests {
    @Test("Equal configs are equal")
    func equalConfigs() {
        let config1 = ReasoningConfig(effort: .high, maxTokens: 4096)
        let config2 = ReasoningConfig(effort: .high, maxTokens: 4096)

        #expect(config1 == config2)
    }

    @Test("Different configs are not equal")
    func differentConfigs() {
        let config1 = ReasoningConfig(effort: .low)
        let config2 = ReasoningConfig(effort: .high)

        #expect(config1 != config2)
    }

    @Test("Different maxTokens are not equal")
    func differentMaxTokens() {
        let config1 = ReasoningConfig(maxTokens: 1000)
        let config2 = ReasoningConfig(maxTokens: 2000)

        #expect(config1 != config2)
    }

    @Test("Equal configs have equal hash values")
    func equalHashValues() {
        let config1 = ReasoningConfig(effort: .high, maxTokens: 4096)
        let config2 = ReasoningConfig(effort: .high, maxTokens: 4096)

        #expect(config1.hashValue == config2.hashValue)
    }
}

// MARK: - ReasoningEffortTests

@Suite("ReasoningEffort Tests")
struct ReasoningEffortTests {
    @Test("All cases have expected raw values")
    func rawValues() {
        #expect(ReasoningEffort.xhigh.rawValue == "xhigh")
        #expect(ReasoningEffort.high.rawValue == "high")
        #expect(ReasoningEffort.medium.rawValue == "medium")
        #expect(ReasoningEffort.low.rawValue == "low")
        #expect(ReasoningEffort.minimal.rawValue == "minimal")
        #expect(ReasoningEffort.none.rawValue == "none")
    }

    @Test("CaseIterable contains all cases")
    func caseIterable() {
        let allCases = ReasoningEffort.allCases
        #expect(allCases.count == 6)
        #expect(allCases.contains(.xhigh))
        #expect(allCases.contains(.high))
        #expect(allCases.contains(.medium))
        #expect(allCases.contains(.low))
        #expect(allCases.contains(.minimal))
        #expect(allCases.contains(.none))
    }

    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        for effort in ReasoningEffort.allCases {
            let encoded = try JSONEncoder().encode(effort)
            let decoded = try JSONDecoder().decode(ReasoningEffort.self, from: encoded)
            #expect(decoded == effort)
        }
    }
}
