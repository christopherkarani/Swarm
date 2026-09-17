import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models prewarm policy")
struct FoundationModelsPrewarmTests {
    @Test("prewarmOnInit default stays false; existing inits compile")
    func prewarmOnInitDefaultIsFalse() {
        let defaulted = FoundationModelsProviderConfiguration()
        #expect(defaulted.prewarmOnInit == false)
        #expect(FoundationModelsProviderConfiguration.default.prewarmOnInit == false)

        let twoArgument = FoundationModelsProviderConfiguration(
            instructions: "Be brief.",
            prewarmOnInit: false
        )
        #expect(twoArgument.instructions == "Be brief.")
        #expect(twoArgument.prewarmOnInit == false)
        #expect(twoArgument.reasoningLevel == nil)
    }

    @Test(
        "capture with flag false does not prewarm on OS 26 or 27",
        arguments: [false, true]
    )
    func captureFlagFalseDoesNotPrewarm(os27Available: Bool) {
        #expect(
            FoundationModelsPrewarm.shouldPrewarm(
                prewarmOnInit: false,
                ownsToolLoop: false,
                os27Available: os27Available
            ) == false
        )
    }

    @Test(
        "capture with flag true prewarms on OS 26 and 27",
        arguments: [false, true]
    )
    func captureFlagTruePrewarms(os27Available: Bool) {
        #expect(
            FoundationModelsPrewarm.shouldPrewarm(
                prewarmOnInit: true,
                ownsToolLoop: false,
                os27Available: os27Available
            )
        )
    }

    @Test("owned-loop with flag false does not prewarm on OS 26")
    func ownedLoopFlagFalseOnOS26DoesNotPrewarm() {
        #expect(
            FoundationModelsPrewarm.shouldPrewarm(
                prewarmOnInit: false,
                ownsToolLoop: true,
                os27Available: false
            ) == false
        )
    }

    @Test("owned-loop with flag false prewarms on OS 27")
    func ownedLoopFlagFalseOnOS27Prewarms() {
        #expect(
            FoundationModelsPrewarm.shouldPrewarm(
                prewarmOnInit: false,
                ownsToolLoop: true,
                os27Available: true
            )
        )
    }

    @Test(
        "owned-loop with flag true prewarms on OS 26 and 27",
        arguments: [false, true]
    )
    func ownedLoopFlagTruePrewarms(os27Available: Bool) {
        #expect(
            FoundationModelsPrewarm.shouldPrewarm(
                prewarmOnInit: true,
                ownsToolLoop: true,
                os27Available: os27Available
            )
        )
    }

    @Test("policy is one boolean so a session is prewarmed at most once")
    func policyIsASingleDecision() {
        var prewarmCount = 0
        if FoundationModelsPrewarm.shouldPrewarm(
            prewarmOnInit: true,
            ownsToolLoop: true,
            os27Available: true
        ) {
            prewarmCount += 1
        }
        #expect(prewarmCount == 1)
    }
}
