@testable import Swarm
import Testing

@Suite("Handoff behavior")
struct HandoffBehaviorTests {
    @Test("Configuration callbacks, predicate, and transform are callable")
    func configurationCallbacksPredicateAndTransformAreCallable() async throws {
        let target = MockAgentRuntime(
            instructions: "handoff-target",
            configuration: AgentConfiguration(name: "handoff-target", defaultTracingEnabled: false)
        )
        let context = AgentContext(input: "route request", initialValues: ["enabled": .bool(true)])
        let inputData = HandoffInputData(
            sourceAgentName: "source",
            targetAgentName: "target",
            input: "handoff payload",
            metadata: ["attempt": .int(1)]
        )
        let callbackRecorder = HandoffCallbackRecorder()

        let configuration = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            toolDescription: "Route to target",
            onTransfer: { context, data in
                await callbackRecorder.recordTransfer(data)
                await context.set("transferred_to", value: .string(data.targetAgentName))
            },
            transform: { data in
                var transformed = data
                transformed.metadata["attempt"] = .int(2)
                transformed.metadata["transformed"] = .bool(true)
                return transformed
            },
            when: { context, _ in
                await context.get("enabled")?.boolValue == true
            },
            nestHandoffHistory: true
        )

        #expect(await configuration.when?(context, target) == true)
        try await configuration.onTransfer?(context, inputData)
        let transformed = configuration.transform?(inputData)

        #expect(await callbackRecorder.transferCount == 1)
        #expect(await context.get("transferred_to") == .string("target"))
        #expect(transformed?.metadata["attempt"] == .int(2))
        #expect(transformed?.metadata["transformed"] == .bool(true))
        #expect(configuration.effectiveToolName == "handoff_to_target")
        #expect(configuration.effectiveToolDescription == "Route to target")
        #expect(configuration.history == .nested)
        #expect(configuration.nestHandoffHistory == true)
    }

    @Test("Type erased handoff preserves callbacks, predicate, and transform")
    func erasedConfigurationPreservesBehavior() async throws {
        let target = MockAgentRuntime(
            instructions: "erased-target",
            configuration: AgentConfiguration(name: "erased-target", defaultTracingEnabled: false)
        )
        let context = AgentContext(input: "route request", initialValues: ["enabled": .bool(false)])
        let typed = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_erased",
            onTransfer: { context, data in
                await context.set("last_input", value: .string(data.input))
            },
            transform: { data in
                var transformed = data
                transformed.metadata["erased"] = .bool(true)
                return transformed
            },
            when: { context, _ in
                await context.get("enabled")?.boolValue == true
            }
        )
        let erased = AnyHandoffConfiguration(typed)
        let inputData = HandoffInputData(
            sourceAgentName: "source",
            targetAgentName: "erased-target",
            input: "payload"
        )

        #expect(await erased.when?(context, erased.targetAgent) == false)
        try await erased.onTransfer?(context, inputData)
        let transformed = erased.transform?(inputData)

        #expect(await context.get("last_input") == .string("payload"))
        #expect(transformed?.metadata["erased"] == .bool(true))
        #expect(erased.effectiveToolName == "handoff_erased")
    }

    @Test("Erased handoff preserves summarized history strategy (AC-001)")
    func erasedConfigurationPreservesSummarizedHistory() {
        let target = MockAgentRuntime(
            instructions: "summarized-target",
            configuration: AgentConfiguration(name: "summarized-target", defaultTracingEnabled: false)
        )
        let erased = target.asHandoff {
            $0.history(.summarized(maxTokens: 80))
        }

        #expect(erased.history == .summarized(maxTokens: 80))
        #expect(erased.nestHandoffHistory == true)

        let data = HandoffInputData(
            sourceAgentName: "source",
            targetAgentName: "summarized-target",
            input: "payload"
        )
        let transformed = erased.transform?(data)
        #expect(transformed?.metadata["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(transformed?.metadata["swarm.handoff.history.maxTokens"] == .int(80))
    }

    @Test("Typed wrap preserves summarized history through erasure")
    func typedWrapPreservesSummarizedHistory() {
        let target = MockAgentRuntime(
            instructions: "wrapped-target",
            configuration: AgentConfiguration(name: "wrapped-target", defaultTracingEnabled: false)
        )
        let typed = HandoffConfiguration(
            targetAgent: target,
            history: .summarized(maxTokens: 80)
        )
        let erased = AnyHandoffConfiguration(typed)

        #expect(erased.history == .summarized(maxTokens: 80))
        #expect(erased.nestHandoffHistory == true)
        #expect(erased.transform == nil)
    }

    @Test("Deprecated nestHandoffHistory true maps to nested, never summarized")
    func deprecatedBooleanInitMapsTrueToNested() {
        let target = MockAgentRuntime(
            instructions: "deprecated-target",
            configuration: AgentConfiguration(name: "deprecated-target", defaultTracingEnabled: false)
        )
        let typed = HandoffConfiguration(targetAgent: target, nestHandoffHistory: true)
        let erased = AnyHandoffConfiguration(targetAgent: target, nestHandoffHistory: true)
        let disabled = AnyHandoffConfiguration(targetAgent: target, nestHandoffHistory: false)

        #expect(typed.history == .nested)
        #expect(erased.history == .nested)
        #expect(disabled.history == .none)
    }
}

private actor HandoffCallbackRecorder {
    private(set) var transferCount = 0

    func recordTransfer(_: HandoffInputData) {
        transferCount += 1
    }
}
