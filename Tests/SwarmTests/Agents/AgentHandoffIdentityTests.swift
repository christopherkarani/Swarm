@testable import Swarm
import Testing

@Suite("Agent handoff identity", .ephemeralDefaultStores)
struct AgentHandoffIdentityTests {

    @Test("Two Agent values as handoffAgents throw duplicateHandoffToolName (AC-001)")
    func twoAgentHandoffAgentsThrowDuplicateToolName() throws {
        let billing = try Agent("billing")
        let support = try Agent("support")

        #expect(throws: AgentError.duplicateHandoffToolName(name: "handoff_to_agent")) {
            _ = try Agent(
                instructions: "triage",
                handoffAgents: [billing, support]
            )
        }
    }

    @Test("Handoff name colliding with a tool throws handoffToolNameCollidesWithTool (AC-002)")
    func handoffNameCollidingWithToolThrows() throws {
        let writer = try Agent("writer")
        let search = MockTool(name: "search", description: "Look things up")

        #expect(throws: AgentError.handoffToolNameCollidesWithTool(name: "search")) {
            _ = try Agent(
                tools: [search],
                instructions: "triage",
                handoffs: [
                    AnyHandoffConfiguration(targetAgent: writer, toolNameOverride: "search"),
                ]
            )
        }
    }

    @Test("Unique handoff name overrides succeed")
    func uniqueHandoffNameOverridesSucceed() throws {
        let billing = try Agent("billing")
        let support = try Agent("support")

        let triage = try Agent(
            "triage",
            handoffs: [
                AnyHandoffConfiguration(targetAgent: billing, toolNameOverride: "handoff_to_billing"),
                AnyHandoffConfiguration(targetAgent: support, toolNameOverride: "handoff_to_support"),
            ]
        )

        #expect(triage.handoffs.map(\.effectiveToolName) == [
            "handoff_to_billing",
            "handoff_to_support",
        ])
    }

    @Test("Disabled tool names still collide with handoffs")
    func disabledToolNameStillCollidesWithHandoff() throws {
        let writer = try Agent("writer")
        let disabled = DisabledHandoffCollisionTool()

        #expect(throws: AgentError.handoffToolNameCollidesWithTool(name: "search")) {
            _ = try Agent(
                tools: [disabled],
                instructions: "triage",
                handoffs: [
                    AnyHandoffConfiguration(targetAgent: writer, toolNameOverride: "search"),
                ]
            )
        }
    }

    @Test("Identical overrides on distinct targets throw duplicateHandoffToolName")
    func identicalOverridesThrowDuplicateToolName() throws {
        let billing = try Agent("billing")
        let support = try Agent("support")

        #expect(throws: AgentError.duplicateHandoffToolName(name: "route_to_specialist")) {
            _ = try Agent(
                "triage",
                handoffs: [
                    AnyHandoffConfiguration(
                        targetAgent: billing,
                        toolNameOverride: "route_to_specialist"
                    ),
                    AnyHandoffConfiguration(
                        targetAgent: support,
                        toolNameOverride: "route_to_specialist"
                    ),
                ]
            )
        }
    }

    @Test("Typed and erased effectiveToolName project HandoffToolName")
    func effectiveToolNamesProjectHandoffToolName() throws {
        let target = try Agent("support")
        let derived = HandoffToolName(derivedFrom: target, override: nil)
        let overridden = HandoffToolName(derivedFrom: target, override: "route_to_support")

        #expect(derived.rawValue == "handoff_to_agent")
        #expect(HandoffConfiguration(targetAgent: target).effectiveToolName == derived.rawValue)
        #expect(AnyHandoffConfiguration(targetAgent: target).effectiveToolName == derived.rawValue)
        #expect(
            HandoffConfiguration(targetAgent: target, toolNameOverride: "route_to_support")
                .effectiveToolName == overridden.rawValue
        )
        #expect(
            AnyHandoffConfiguration(targetAgent: target, toolNameOverride: "route_to_support")
                .effectiveToolName == overridden.rawValue
        )
    }

    @Test("Handoff identity errors are Equatable, described, and not retryable")
    func handoffIdentityErrorsAreDescribedAndNotRetryable() {
        let duplicate = AgentError.duplicateHandoffToolName(name: "handoff_to_agent")
        let collision = AgentError.handoffToolNameCollidesWithTool(name: "search")

        #expect(duplicate == AgentError.duplicateHandoffToolName(name: "handoff_to_agent"))
        #expect(duplicate != AgentError.duplicateHandoffToolName(name: "other"))
        #expect(collision == AgentError.handoffToolNameCollidesWithTool(name: "search"))
        #expect(collision != duplicate)
        #expect(duplicate.errorDescription?.contains("handoff_to_agent") == true)
        #expect(collision.errorDescription?.contains("search") == true)
        #expect(!duplicate.isRetryable)
        #expect(!collision.isRetryable)
    }
}

private struct DisabledHandoffCollisionTool: AnyJSONTool, Sendable {
    var name: String { "search" }
    var description: String { "Disabled lookup" }
    var parameters: [ToolParameter] { [] }
    var isEnabled: Bool { false }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        .null
    }
}
