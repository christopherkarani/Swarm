// ContextProfileTests.swift
// SwarmTests
//
// Tests for ContextProfile presets and budgeting behavior.

import Foundation
@testable import Swarm
import Testing

@Suite("ContextProfile Preset Tests")
struct ContextProfilePresetTests {
    @Test("Presets define stable ratio ordering")
    func presetRatioOrdering() {
        let lite = ContextProfile.lite
        let balanced = ContextProfile.balanced
        let heavy = ContextProfile.heavy

        #expect(lite.workingTokenRatio < balanced.workingTokenRatio)
        #expect(balanced.workingTokenRatio < heavy.workingTokenRatio)

        #expect(lite.memoryTokenRatio > balanced.memoryTokenRatio)
        #expect(balanced.memoryTokenRatio > heavy.memoryTokenRatio)

        #expect(lite.toolIOTokenRatio == balanced.toolIOTokenRatio)
        #expect(balanced.toolIOTokenRatio == heavy.toolIOTokenRatio)

        #expect(lite.summaryTokenRatio > balanced.summaryTokenRatio)
        #expect(balanced.summaryTokenRatio > heavy.summaryTokenRatio)
    }

    @Test("Preset ratios sum to 1.0")
    func presetRatioSum() {
        let presets = [ContextProfile.lite, ContextProfile.balanced, ContextProfile.heavy]
        for preset in presets {
            let sum = preset.workingTokenRatio + preset.memoryTokenRatio + preset.toolIOTokenRatio
            #expect(abs(sum - 1.0) < 0.0001)
        }
    }
}

@Suite("ContextProfile Budget Tests")
struct ContextProfileBudgetTests {
    @Test("Budget splits follow ratios for lite preset")
    func budgetSplitsLite() {
        let profile = ContextProfile.lite(maxContextTokens: 4000)
        let budget = profile.budget

        #expect(budget.maxContextTokens == 4000)
        #expect(budget.workingTokens == 2000)
        #expect(budget.memoryTokens == 1400)
        #expect(budget.toolIOTokens == 600)
        #expect(budget.workingTokens + budget.memoryTokens + budget.toolIOTokens == 4000)
        #expect(profile.memoryTokenLimit == 1400)
        #expect(profile.summaryTokenLimit == 840)
    }

    @Test("Budget splits follow ratios for balanced preset")
    func budgetSplitsBalanced() {
        let profile = ContextProfile.balanced(maxContextTokens: 4000)
        let budget = profile.budget

        #expect(budget.workingTokens == 2200)
        #expect(budget.memoryTokens == 1200)
        #expect(budget.toolIOTokens == 600)
        #expect(profile.summaryTokenLimit == 600)
    }

    @Test("Budget splits follow ratios for heavy preset")
    func budgetSplitsHeavy() {
        let profile = ContextProfile.heavy(maxContextTokens: 4000)
        let budget = profile.budget

        #expect(budget.workingTokens == 2400)
        #expect(budget.memoryTokens == 1000)
        #expect(budget.toolIOTokens == 600)
        #expect(profile.summaryTokenLimit == 400)
    }

    @Test("Invalid values are normalized to non-crashing safe values")
    func invalidValuesAreNormalized() {
        let profile = ContextProfile(
            preset: .balanced,
            maxContextTokens: 0,
            workingTokenRatio: 2.0,
            memoryTokenRatio: -1.0,
            toolIOTokenRatio: 0.0,
            summaryTokenRatio: 2.0,
            maxToolOutputTokens: 0,
            maxRetrievedItems: 0,
            maxRetrievedItemTokens: 0,
            summaryCadenceTurns: 0,
            summaryTriggerUtilization: -1.0
        )

        let ratioSum = profile.workingTokenRatio + profile.memoryTokenRatio + profile.toolIOTokenRatio
        #expect(abs(ratioSum - 1.0) < 0.0001)
        #expect(profile.maxContextTokens == 1)
        #expect(profile.maxToolOutputTokens == 1)
        #expect(profile.maxRetrievedItems == 1)
        #expect(profile.maxRetrievedItemTokens == 1)
        #expect(profile.summaryCadenceTurns == 1)
        #expect(profile.summaryTokenRatio == 1.0)
        #expect(profile.summaryTriggerUtilization == 0.0)

        // Minimum ratio floor ensures all budgets remain usable after clamping
        // extreme inputs. Even with workingRatio=2.0 and memoryRatio=-1.0, no
        // ratio should collapse to zero, preventing broken callers.
        #expect(profile.workingTokenRatio > 0)
        #expect(profile.memoryTokenRatio > 0)
        #expect(profile.toolIOTokenRatio > 0)
    }
}

@Suite("ContextProfile Platform Defaults")
struct ContextProfilePlatformDefaultsTests {
    @Test("Platform defaults expose expected max context tokens")
    func platformDefaultTokens() {
        #if os(macOS)
        #expect(ContextProfile.platformDefault.maxContextTokens == ContextProfile.PlatformDefaults.macOS.maxContextTokens)
        #else
        #expect(ContextProfile.platformDefault.maxContextTokens == ContextProfile.PlatformDefaults.iOS.maxContextTokens)
        #endif
    }

    @Test("macOS default context tokens >= iOS default")
    func platformDefaultOrdering() {
        #expect(ContextProfile.PlatformDefaults.macOS.maxContextTokens >= ContextProfile.PlatformDefaults.iOS.maxContextTokens)
    }
}

@Suite("ContextProfile strict4k")
struct ContextProfileStrict4kTests {
    @Test("strict4k exposes 4096 total context envelope and 3412 max input")
    func strict4kDefaults() {
        let profile = ContextProfile.strict4k
        let budget = profile.budget

        #expect(profile.preset == .strict4k)
        #expect(budget.maxTotalContextTokens == 4096)
        #expect(budget.maxInputTokens == 3412)
        #expect(budget.maxOutputTokens == 500)
        #expect(budget.outputReserveTokens == 500)
        #expect(budget.protocolOverheadReserveTokens == 120)
        #expect(budget.safetyMarginTokens == 64)
        #expect(profile.maxContextTokens == 3412)
        #expect(profile.maxTotalContextTokens == 4096)
        #expect(budget.workingTokens == 1912)
        #expect(budget.memoryTokens == 900)
        #expect(budget.toolIOTokens == 600)
        #expect(budget.workingTokens + budget.memoryTokens + budget.toolIOTokens == budget.maxInputTokens)
        #expect(profile.memoryTokenLimit == 900)
        #expect(profile.summaryTokenLimit == 450)
        #expect(budget.bucketCaps?.system == 512)
        #expect(budget.bucketCaps?.history == 1400)
        #expect(budget.bucketCaps?.memory == 900)
        #expect(budget.bucketCaps?.toolIO == 600)
    }

    @Test("strict4k default template matches throwing init defaults")
    func strict4kDefaultMatchesThrowingInit() throws {
        let explicit = try ContextProfile.Strict4kTemplate()

        #expect(ContextProfile.Strict4kTemplate.default == explicit)
        #expect(ContextProfile.Strict4kTemplate.default.maxInputTokens == 3412)
    }

    @Test("strict4k template overrides are honored")
    func strict4kTemplateOverrides() throws {
        let template = try ContextProfile.Strict4kTemplate(
            systemTokens: 600,
            historyTokens: 1200,
            memoryTokens: 900,
            toolIOTokens: 500,
            outputReserveTokens: 600,
            protocolOverheadReserveTokens: 100,
            safetyMarginTokens: 100
        )
        let profile = ContextProfile.strict4k(template: template)
        let budget = profile.budget

        #expect(budget.maxTotalContextTokens == 4096)
        #expect(budget.maxInputTokens == 3296)
        #expect(budget.maxOutputTokens == 600)
        #expect(budget.workingTokens == 1896)
        #expect(budget.memoryTokens == 900)
        #expect(budget.toolIOTokens == 500)
        #expect(budget.workingTokens + budget.memoryTokens + budget.toolIOTokens == budget.maxInputTokens)
        #expect(profile.memoryTokenLimit == 900)
        #expect(profile.summaryTokenLimit == 450)
        #expect(budget.bucketCaps?.system == 600)
        #expect(budget.bucketCaps?.history == 1200)
        #expect(budget.bucketCaps?.memory == 900)
        #expect(budget.bucketCaps?.toolIO == 500)
    }
}

@Suite("ContextProfile Strict4kTemplate validation")
struct Strict4kTemplateValidationTests {
    private func invalidInputReason(
        for operation: () throws -> ContextProfile.Strict4kTemplate
    ) -> String {
        do {
            _ = try operation()
        } catch let error as AgentError {
            guard case let .invalidInput(reason) = error else {
                Issue.record("expected invalidInput, got \(error)")
                return ""
            }
            return reason
        } catch {
            Issue.record("expected AgentError, got \(error)")
            return ""
        }
        Issue.record("expected init to throw")
        return ""
    }

    @Test("invalid bucket values throw instead of crashing")
    func invalidBucketsThrow() {
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(maxTotalContextTokens: 0) } == "maxTotalContextTokens must be positive")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(systemTokens: -1) } == "systemTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(historyTokens: -1) } == "historyTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(memoryTokens: -1) } == "memoryTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(toolIOTokens: -1) } == "toolIOTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(outputReserveTokens: -1) } == "outputReserveTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(protocolOverheadReserveTokens: -1) } == "protocolOverheadReserveTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(safetyMarginTokens: -1) } == "safetyMarginTokens cannot be negative")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(maxToolOutputTokens: 0) } == "maxToolOutputTokens must be positive")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(maxRetrievedItems: 0) } == "maxRetrievedItems must be positive")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(maxRetrievedItemTokens: 0) } == "maxRetrievedItemTokens must be positive")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(summaryCadenceTurns: 0) } == "summaryCadenceTurns must be positive")
        #expect(invalidInputReason { try ContextProfile.Strict4kTemplate(summaryTriggerUtilization: 1.5) } == "summaryTriggerUtilization must be 0.0-1.0")
    }

    @Test("non-positive derived input budget throws")
    func nonPositiveMaxInputThrows() {
        #expect(
            invalidInputReason {
                try ContextProfile.Strict4kTemplate(
                    maxTotalContextTokens: 100,
                    systemTokens: 0,
                    historyTokens: 0,
                    memoryTokens: 0,
                    toolIOTokens: 0,
                    outputReserveTokens: 50,
                    protocolOverheadReserveTokens: 30,
                    safetyMarginTokens: 20
                )
            } == "Strict4k maxInputTokens must be positive"
        )
    }

    @Test("buckets exceeding the input budget throw")
    func bucketsExceedingMaxInputThrow() {
        #expect(
            invalidInputReason {
                try ContextProfile.Strict4kTemplate(
                    systemTokens: 2000,
                    historyTokens: 2000,
                    memoryTokens: 0,
                    toolIOTokens: 0
                )
            } == "Strict4k buckets exceed maxInputTokens"
        )
    }

    @Test("overflowing token arithmetic throws")
    func overflowingArithmeticThrows() throws {
        let huge = try ContextProfile.Strict4kTemplate(maxTotalContextTokens: Int.max)
        #expect(huge.maxInputTokens == Int.max - 684)
        #expect(
            invalidInputReason {
                try ContextProfile.Strict4kTemplate(
                    systemTokens: Int.max,
                    historyTokens: Int.max,
                    memoryTokens: 0,
                    toolIOTokens: 0
                )
            } == "Strict4k bucket allocation overflows Int"
        )
        #expect(
            invalidInputReason {
                try ContextProfile.Strict4kTemplate(
                    maxTotalContextTokens: 4096,
                    systemTokens: 0,
                    historyTokens: 0,
                    memoryTokens: 0,
                    toolIOTokens: 0,
                    outputReserveTokens: Int.max,
                    protocolOverheadReserveTokens: Int.max,
                    safetyMarginTokens: Int.max
                )
            } == "Strict4k reserve arithmetic overflows Int"
        )
    }

    @Test("maxInputTokens saturates on extreme post-init values")
    func maxInputTokensSaturates() throws {
        var template = try ContextProfile.Strict4kTemplate()
        template.outputReserveTokens = Int.max
        template.protocolOverheadReserveTokens = Int.max
        template.safetyMarginTokens = Int.max

        #expect(template.maxInputTokens == Int.min)
    }

    @Test("strict4k factory saturates on extreme post-init values")
    func strict4kFactorySaturates() throws {
        var template = try ContextProfile.Strict4kTemplate()
        template.systemTokens = Int.max
        template.historyTokens = Int.max
        template.memoryTokens = Int.max
        template.toolIOTokens = Int.max

        let profile = ContextProfile.strict4k(template: template)

        #expect(profile.maxContextTokens == 3412)
        #expect(profile.preset == .strict4k)
        #expect(profile.budget.workingTokens == 0)
        #expect(profile.budget.memoryTokens == Int.max)
        #expect(profile.budget.toolIOTokens == Int.max)
    }

    @Test("strict4k factory clamps negative post-init buckets")
    func strict4kFactoryClampsNegativeBuckets() throws {
        var template = try ContextProfile.Strict4kTemplate()
        template.systemTokens = -10
        template.historyTokens = -20
        template.memoryTokens = -30
        template.toolIOTokens = -40

        let profile = ContextProfile.strict4k(template: template)
        let budget = profile.budget

        #expect(budget.bucketCaps?.system == 0)
        #expect(budget.bucketCaps?.history == 0)
        #expect(budget.bucketCaps?.memory == 0)
        #expect(budget.bucketCaps?.toolIO == 0)
        #expect(budget.workingTokens == 3412)
    }

    @Test("ContextProfile reserves saturate on extreme values")
    func contextProfileReservesSaturate() {
        let profile = ContextProfile(
            preset: .balanced,
            maxContextTokens: 4000,
            workingTokenRatio: 0.55,
            memoryTokenRatio: 0.30,
            toolIOTokenRatio: 0.15,
            summaryTokenRatio: 0.50,
            maxToolOutputTokens: 1000,
            maxRetrievedItems: 3,
            maxRetrievedItemTokens: 400,
            summaryCadenceTurns: 3,
            summaryTriggerUtilization: 0.65,
            outputReserveTokens: Int.max,
            protocolOverheadReserveTokens: Int.max,
            safetyMarginTokens: Int.max
        )

        #expect(profile.maxTotalContextTokens == Int.max)
    }
}
