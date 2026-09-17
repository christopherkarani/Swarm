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

    @Test("Typed and erased effectiveToolName share HandoffToolName derivation")
    func typedAndErasedEffectiveToolNameShareDerivation() {
        let target = MockAgentRuntime(
            instructions: "named-target",
            configuration: AgentConfiguration(name: "named-target", defaultTracingEnabled: false)
        )
        let typed = HandoffConfiguration(targetAgent: target)
        let erased = AnyHandoffConfiguration(typed)
        let derived = HandoffToolName(derivedFrom: target, override: nil)

        #expect(typed.effectiveToolName == derived.rawValue)
        #expect(erased.effectiveToolName == derived.rawValue)
        #expect(derived.rawValue.hasPrefix("handoff_to_"))
    }

    @Test("HandoffContextFilter drops reserved prefixes and keeps safe keys")
    func handoffContextFilterDropsReservedPrefixes() {
        let filtered = HandoffContextFilter.allowedValues([
            "user_id": .string("secret"),
            "USER_ID": .string("upper"),
            "auth_token": .string("tok"),
            "authorization": .string("bearer"),
            "session": .string("sess"),
            "session_id": .string("sid"),
            "internal.secret": .string("nope"),
            "ticket": .string("t-1"),
            "reason": .string("ok"),
            "internal": .string("kept"),
        ])

        #expect(filtered["user_id"] == nil)
        #expect(filtered["USER_ID"] == nil)
        #expect(filtered["auth_token"] == nil)
        #expect(filtered["authorization"] == nil)
        #expect(filtered["session"] == nil)
        #expect(filtered["session_id"] == nil)
        #expect(filtered["internal.secret"] == nil)
        #expect(filtered["ticket"] == .string("t-1"))
        #expect(filtered["reason"] == .string("ok"))
        #expect(filtered["internal"] == .string("kept"))
    }

    @Test("Coordinator handleHandoff path drops reserved user_id for a plain Agent")
    func coordinatorDropsReservedUserIDForPlainAgent() async throws {
        let provider = MockInferenceProvider(responses: ["done"])
        let agent = try Agent(
            "Handle work.",
            configuration: AgentConfiguration(name: "target", defaultTracingEnabled: false),
            inferenceProvider: provider
        )
        let coordinator = HandoffCoordinator()
        await coordinator.register(agent, as: "target")
        let context = AgentContext(input: "orig")

        let result = try await coordinator.executeHandoff(
            HandoffRequest(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: "do work",
                reason: "specialist",
                context: [
                    "user_id": .string("secret"),
                    "ticket": .string("t-1"),
                ]
            ),
            context: context
        )

        #expect(result.result.output == "done")
        #expect(await context.get("user_id") == nil)
        #expect(await context.get("ticket") == .string("t-1"))
        #expect(await context.get("handoff_source") == .string("source"))
        #expect(await context.get("handoff_reason") == .string("specialist"))
    }

    @Test("Coordinator invokes custom handleHandoff without HandoffReceiver")
    func coordinatorInvokesCustomHandleHandoffWithoutReceiverCast() async throws {
        let target = CoordinatorRecordingRuntime()
        let coordinator = HandoffCoordinator()
        await coordinator.register(target, as: "target")
        let context = AgentContext(input: "orig")

        let result = try await coordinator.executeHandoff(
            HandoffRequest(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: "payload"
            ),
            context: context
        )

        #expect(result.result.output == "handoff payload")
        #expect(await target.handoffCount == 1)
        #expect(await target.runCount == 0)
    }
}

private actor CoordinatorRecordingRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Record coordinator handoffs"
    nonisolated let configuration = AgentConfiguration(name: "target", defaultTracingEnabled: false)
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil
    nonisolated let inputGuardrails: [any InputGuardrail] = []
    nonisolated let outputGuardrails: [any OutputGuardrail] = []
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private(set) var runCount = 0
    private(set) var handoffCount = 0

    func run(_: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        runCount += 1
        return AgentResult(output: "ran")
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: "ran \(input)"))))
            continuation.finish()
        }
    }

    func cancel() async {}

    func handleHandoff(
        _ request: HandoffRequest,
        context _: AgentContext,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) async throws -> AgentResult {
        handoffCount += 1
        return AgentResult(output: "handoff \(request.input)")
    }
}

private actor HandoffCallbackRecorder {
    private(set) var transferCount = 0

    func recordTransfer(_: HandoffInputData) {
        transferCount += 1
    }
}
