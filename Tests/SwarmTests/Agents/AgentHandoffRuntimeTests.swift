// P2-1 grandfather: split pending; new files are gated at 1000 lines.
// swiftlint:disable file_length
import Foundation
@testable import Swarm
import Testing

@Suite("Agent handoff runtime", .ephemeralDefaultStores)
struct AgentHandoffRuntimeTests {

    @Test("Disabled handoffs are not advertised as tools")
    func disabledHandoffsAreNotAdvertisedAsTools() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(content: "done", finishReason: .completed),
        ])
        let target = RecordingHandoffReceiver(name: "target-agent")
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            when: { _, _ in false }
        )
        let regularTool = MockTool(name: "regular_tool", description: "A regular callable tool")
        let agent = try Agent(
            tools: [regularTool],
            instructions: "Route only when enabled.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        _ = try await agent.run("do not route")

        let toolCalls = await provider.toolCallMessageCalls
        #expect(toolCalls.count == 1)
        let toolNames = toolCalls[0].tools.map(\.name)
        #expect(toolNames.contains("regular_tool"))
        #expect(!toolNames.contains("handoff_to_target"))
        #expect(await target.runInputs.isEmpty)
        #expect(await target.handoffRequests.isEmpty)
    }

    @Test("Runtime handoff executes callbacks transform and nested history")
    func runtimeHandoffExecutesCallbacksTransformAndNestedHistory() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("needs specialist")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffReceiver(name: "target-agent")
        let callbackRecorder = HandoffCallbackRecorder()
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            onTransfer: { context, data in
                await callbackRecorder.recordTransfer(data)
                await context.set("transfer_seen", value: .string(data.input))
                await context.set(.originalInput, "callback-updated-original-input")
            },
            transform: { data in
                HandoffInputData(
                    sourceAgentName: data.sourceAgentName,
                    targetAgentName: data.targetAgentName,
                    input: "transformed: \(data.input)",
                    context: data.context,
                    metadata: data.metadata.merging(["transformed": .bool(true)]) { _, new in new }
                )
            },
            when: { context, _ in
                context.originalInput.contains("route")
            },
            nestHandoffHistory: true
        )
        let agent = try Agent(
            tools: [],
            instructions: "Route to target when needed.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        let result = try await agent.run("please route this")

        #expect(result.output == "handled transformed: please route this")
        #expect(await callbackRecorder.transferCount == 1)
        #expect(await callbackRecorder.lastTransfer?.input == "please route this")

        let requests = await target.handoffRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.sourceAgentName == "source-agent")
        #expect(request.targetAgentName == "target-agent")
        #expect(request.input == "transformed: please route this")
        #expect(request.reason == "needs specialist")
        #expect(request.context["transformed"] == .bool(true))

        let snapshots = await target.contextSnapshots
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        #expect(snapshot["transfer_seen"] == .string("please route this"))
        #expect(snapshot[AgentContextKey.originalInput.rawValue] == .string("callback-updated-original-input"))
        #expect(snapshot[AgentContextKey.executionPath.rawValue] == .array([.string("source-agent")]))

        let nestedMessages = await target.contextMessages
        #expect(nestedMessages.count == 1)
        let messages = try #require(nestedMessages.first)
        #expect(messages.contains { $0.content == "please route this" })

        let paths = await target.executionPaths
        #expect(paths.first == ["source-agent"])
        let session = try #require(await target.handoffSessions.first)
        let sessionItems = try await session.getAllItems()
        #expect(sessionItems.contains { $0.content == "please route this" })
    }

    @Test("Handoff with no history does not nest source transcript for regular Agent targets (AC-002)")
    func handoffWithNoHistoryOmitsNestedTranscriptForRegularAgentTargets() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let targetProvider = MockInferenceProvider(responses: ["target done"])
        let target = try Agent(
            tools: [],
            instructions: "Use prior context.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: targetProvider
        )
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            transform: { data in
                HandoffInputData(
                    sourceAgentName: data.sourceAgentName,
                    targetAgentName: data.targetAgentName,
                    input: "target-only payload",
                    context: data.context,
                    metadata: data.metadata
                )
            },
            history: .none
        )
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: sourceProvider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        _ = try await source.run("please route this")

        let targetCalls = await targetProvider.generateMessageCalls
        let messages = try #require(targetCalls.first?.messages)
        #expect(!messages.contains { $0.role == .user && $0.content == "please route this" })
        #expect(messages.contains { $0.role == .user && $0.content == "target-only payload" })
    }

    @Test("Summarized handoff history is passed to regular Agent targets (AC-002)")
    func summarizedHandoffHistoryIsPassedToRegularAgentTargets() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let targetProvider = MockInferenceProvider(responses: ["target done"])
        let target = try Agent(
            tools: [],
            instructions: "Use prior context.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: targetProvider
        )
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            history: .summarized(maxTokens: 80)
        )
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: sourceProvider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        _ = try await source.run("please route this")

        let targetCalls = await targetProvider.generateMessageCalls
        let messages = try #require(targetCalls.first?.messages)
        #expect(messages.contains { $0.role == .user && $0.content == "please route this" })
    }

    @Test("Summarized handoff annotates metadata for typed configuration (AC-002)")
    func summarizedHandoffAnnotatesMetadataForTypedConfiguration() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffReceiver(name: "target-agent")
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            history: .summarized(maxTokens: 80)
        )
        let agent = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        _ = try await agent.run("please route this")

        let request = try #require(await target.handoffRequests.first)
        #expect(request.context["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(request.context["swarm.handoff.history.maxTokens"] == .int(80))

        let snapshot = try #require(await target.contextSnapshots.first)
        #expect(snapshot["swarm.handoff.history.mode"] == .string("summarized"))
        #expect(snapshot["swarm.handoff.history.maxTokens"] == .int(80))

        let messages = try #require(await target.contextMessages.first)
        #expect(messages.contains { $0.content == "please route this" })
    }

    @Test("Nested handoff history is passed to regular Agent targets")
    func nestedHandoffHistoryIsPassedToRegularAgentTargets() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let targetProvider = MockInferenceProvider(responses: ["target done"])
        let target = try Agent(
            tools: [],
            instructions: "Use prior context.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: targetProvider
        )
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            transform: { data in
                HandoffInputData(
                    sourceAgentName: data.sourceAgentName,
                    targetAgentName: data.targetAgentName,
                    input: "target-only payload",
                    context: data.context,
                    metadata: data.metadata
                )
            },
            history: .nested
        )
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: sourceProvider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        let result = try await source.run("please route this")

        #expect(result.output == "target done")
        let targetCalls = await targetProvider.generateMessageCalls
        let messages = try #require(targetCalls.first?.messages)
        #expect(messages.contains { $0.role == .user && $0.content == "please route this" })
        #expect(messages.contains { $0.role == .user && $0.content == "target-only payload" })
    }

    @Test("Nested handoff history preserves completed tool pairs for regular Agent targets")
    func nestedHandoffHistoryPreservesCompletedToolPairsForRegularAgentTargets() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_lookup",
                        name: "lookup_tool",
                        arguments: [:]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let targetProvider = MockInferenceProvider(responses: ["target done"])
        let target = try Agent(
            tools: [],
            instructions: "Use prior context.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: targetProvider
        )
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            nestHandoffHistory: true
        )
        let source = try Agent(
            tools: [MockTool(name: "lookup_tool", result: .string("lookup result"))],
            instructions: "Look up context, then route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: sourceProvider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        _ = try await source.run("please route this")

        let targetCalls = await targetProvider.generateMessageCalls
        let messages = try #require(targetCalls.first?.messages)
        let assistantMessages = messages.filter { $0.role == .assistant }
        let toolMessages = messages.filter { $0.role == .tool }

        #expect(assistantMessages.contains {
            $0.toolCalls.contains { $0.id == "call_lookup" && $0.name == "lookup_tool" }
        })
        #expect(toolMessages.contains {
            $0.toolCallID == "call_lookup" && $0.name == "lookup_tool" && $0.content == "lookup result"
        })
        #expect(!assistantMessages.contains {
            $0.toolCalls.contains { $0.id == "call_handoff" || $0.name == "handoff_to_target" }
        })
        #expect(!toolMessages.contains { $0.toolCallID == "call_handoff" || $0.name == "handoff_to_target" })
    }

    @Test("Handoff tool call is recorded on parent result")
    func handoffToolCallIsRecordedOnParentResult() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])
        let target = RecordingHandoffReceiver(name: "target-agent")
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target"
        )
        let agent = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        let result = try await agent.run("route this")

        let handoffCall = try #require(result.toolCalls.first)
        #expect(handoffCall.toolName == "handoff_to_target")
        #expect(handoffCall.providerCallId == "call_handoff")
        #expect(handoffCall.arguments["reason"] == .string("delegate"))

        let handoffResult = try #require(result.toolResults.first)
        #expect(handoffResult.callId == handoffCall.id)
        #expect(handoffResult.isSuccess)
        #expect(handoffResult.output == .string("handled route this"))
    }

    @Test("Disabled handoff tool call is recoverable by default")
    func disabledHandoffToolCallIsRecoverableByDefault() async throws {
        let gate = HandoffPredicateGate(isEnabled: true)
        let provider = GateDisablingToolCallProvider(gate: gate)
        let target = RecordingHandoffReceiver(name: "target-agent")
        let handoff = HandoffConfiguration(
            targetAgent: target,
            toolNameOverride: "handoff_to_target",
            when: { _, _ in await gate.isEnabled }
        )
        let agent = try Agent(
            tools: [],
            instructions: "Route only when enabled.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [AnyHandoffConfiguration(handoff)]
        )

        let result = try await agent.run("do not route")

        #expect(result.output == "recovered")
        #expect(await target.runInputs.isEmpty)
        #expect(await target.handoffRequests.isEmpty)

        let handoffCall = try #require(result.toolCalls.first)
        #expect(handoffCall.toolName == "handoff_to_target")
        #expect(handoffCall.providerCallId == "call_disabled_handoff")

        let handoffResult = try #require(result.toolResults.first)
        #expect(!handoffResult.isSuccess)
        #expect(handoffResult.errorMessage == "Handoff is not enabled")
    }

    @Test("Unique handoff name overrides execute two Agent targets without trapping")
    func uniqueHandoffNameOverridesExecuteTwoAgentTargets() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_billing",
                        arguments: ["reason": .string("invoice")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let billing = try Agent(
            "Handle billing.",
            configuration: AgentConfiguration(name: "billing", defaultTracingEnabled: false),
            inferenceProvider: MockInferenceProvider(responses: ["billing handled"])
        )
        let support = try Agent(
            "Handle support.",
            configuration: AgentConfiguration(name: "support", defaultTracingEnabled: false),
            inferenceProvider: MockInferenceProvider(responses: ["support handled"])
        )
        let triage = try Agent(
            "Route requests.",
            configuration: AgentConfiguration(name: "triage", defaultTracingEnabled: false),
            inferenceProvider: sourceProvider,
            handoffs: [
                AnyHandoffConfiguration(targetAgent: billing, toolNameOverride: "handoff_to_billing"),
                AnyHandoffConfiguration(targetAgent: support, toolNameOverride: "handoff_to_support"),
            ]
        )

        let result = try await triage.run("invoice question")

        #expect(result.output == "billing handled")
    }

    @Test("Default handleHandoff on Agent drops reserved keys and writes provenance")
    func defaultHandleHandoffOnAgentDropsReservedKeysAndWritesProvenance() async throws {
        let provider = MockInferenceProvider(responses: ["done"])
        let agent = try Agent(
            "Handle work.",
            configuration: AgentConfiguration(name: "target", defaultTracingEnabled: false),
            inferenceProvider: provider
        )
        let context = AgentContext(input: "orig")
        let session = InMemorySession()

        let result = try await agent.handleHandoff(
            HandoffRequest(
                sourceAgentName: "source",
                targetAgentName: "target",
                input: "do work",
                reason: "specialist",
                context: [
                    "user_id": .string("secret"),
                    "auth_token": .string("tok"),
                    "ticket": .string("t-1"),
                ]
            ),
            context: context,
            session: session,
            observer: nil
        )

        #expect(result.output == "done")
        #expect(await context.get("user_id") == nil)
        #expect(await context.get("auth_token") == nil)
        #expect(await context.get("ticket") == .string("t-1"))
        #expect(await context.get("handoff_source") == .string("source"))
        #expect(await context.get("handoff_reason") == .string("specialist"))
        #expect(await context.getExecutionPath() == ["target"])
        let messages = try await session.getAllItems()
        #expect(messages.contains { $0.role == .user && $0.content == "do work" })
    }

    @Test("In-loop nested handoff to a plain Agent keeps session history (AC-006, AC-007)")
    func inLoopNestedHandoffToPlainAgentKeepsSessionHistory() async throws {
        let sourceProvider = MockInferenceProvider()
        await sourceProvider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let targetProvider = MockInferenceProvider(responses: ["target done"])
        let target = try Agent(
            tools: [],
            instructions: "Use prior context.",
            configuration: AgentConfiguration(name: "target-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: targetProvider
        )
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            memory: ConversationMemory(),
            inferenceProvider: sourceProvider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(
                        targetAgent: target,
                        toolNameOverride: "handoff_to_target",
                        transform: { data in
                            var injected = data.context
                            injected["user_id"] = .string("injected-user")
                            injected["ticket"] = .string("t-42")
                            return HandoffInputData(
                                sourceAgentName: data.sourceAgentName,
                                targetAgentName: data.targetAgentName,
                                input: "target-only payload",
                                context: injected,
                                metadata: data.metadata
                            )
                        },
                        history: .nested
                    )
                ),
            ]
        )

        let result = try await source.run("please route this")

        #expect(result.output == "target done")
        let targetCalls = await targetProvider.generateMessageCalls
        let messages = try #require(targetCalls.first?.messages)
        #expect(messages.contains { $0.role == .user && $0.content == "please route this" })
        #expect(messages.contains { $0.role == .user && $0.content == "target-only payload" })
    }

    @Test("In-loop handoff invokes AgentRuntime handleHandoff without HandoffReceiver (AC-006)")
    func inLoopHandoffInvokesCustomHandleHandoffWithoutReceiverCast() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("needs specialist")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffRuntime(name: "target-agent")
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(
                        targetAgent: target,
                        toolNameOverride: "handoff_to_target",
                        transform: { data in
                            var injected = data.context
                            injected["user_id"] = .string("injected-user")
                            injected["ticket"] = .string("t-42")
                            return HandoffInputData(
                                sourceAgentName: data.sourceAgentName,
                                targetAgentName: data.targetAgentName,
                                input: data.input,
                                context: injected,
                                metadata: data.metadata
                            )
                        }
                    )
                ),
            ]
        )

        let result = try await source.run("please route this")

        #expect(result.output == "handled please route this")
        #expect(await target.handoffCount == 1)
        #expect(await target.runCount == 0)
        let snapshot = try #require(await target.contextSnapshots.first)
        #expect(snapshot["user_id"] == nil)
        #expect(snapshot["ticket"] == .string("t-42"))
        let request = try #require(await target.handoffRequests.first)
        #expect(request.context["user_id"] == .string("injected-user"))
        #expect(request.reason == "needs specialist")
    }

    @Test("Nested handoff history passes a session into handleHandoff (AC-007)")
    func nestedHandoffHistoryPassesSessionIntoHandleHandoff() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffRuntime(name: "target-agent")
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(
                        targetAgent: target,
                        toolNameOverride: "handoff_to_target",
                        history: .nested
                    )
                ),
            ]
        )

        _ = try await source.run("please route this")

        let session = try #require(await target.handoffSessions.first)
        let items = try await session.getAllItems()
        #expect(items.contains { $0.role == .user && $0.content == "please route this" })
    }

    @Test("EnvironmentAgent forwards handleHandoff to the base runtime")
    func environmentAgentForwardsHandleHandoff() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffRuntime(name: "target-agent")
        let wrapped = target.memory(ConversationMemory())
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(targetAgent: wrapped, toolNameOverride: "handoff_to_target")
                ),
            ]
        )

        let result = try await source.run("please route this")

        #expect(result.output == "handled please route this")
        #expect(await target.handoffCount == 1)
        #expect(await target.runCount == 0)
    }

    @Test("ObservedAgent forwards handleHandoff and combines observers")
    func observedAgentForwardsHandleHandoffAndCombinesObservers() async throws {
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "call_handoff",
                        name: "handoff_to_target",
                        arguments: ["reason": .string("delegate")]
                    ),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
        ])

        let target = RecordingHandoffRuntime(name: "target-agent")
        let attached = RecordingStartObserver()
        let runObserver = RecordingStartObserver()
        let wrapped = target.observed(by: attached)
        let source = try Agent(
            tools: [],
            instructions: "Route to target.",
            configuration: AgentConfiguration(name: "source-agent", defaultTracingEnabled: false),
            inferenceProvider: provider,
            handoffs: [
                AnyHandoffConfiguration(
                    HandoffConfiguration(targetAgent: wrapped, toolNameOverride: "handoff_to_target")
                ),
            ]
        )

        let result = try await source.run("please route this", observer: runObserver)

        #expect(result.output == "handled please route this")
        #expect(await target.handoffCount == 1)
        #expect(await target.runCount == 0)
        #expect(await attached.startAgentNames == ["target-agent"])
        #expect(await runObserver.startAgentNames.contains("target-agent"))
    }
}

private actor HandoffPredicateGate {
    private(set) var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func disable() {
        isEnabled = false
    }
}

private actor GateDisablingToolCallProvider: InferenceProvider, MessagesFromPromptInference {
    private let gate: HandoffPredicateGate

    init(gate: HandoffPredicateGate) {
        self.gate = gate
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        "recovered"
    }

    nonisolated func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield("recovered")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        await gate.disable()
        return disabledHandoffToolCallResponse()
    }

    func generate(messages _: [InferenceMessage], options _: InferenceOptions) async throws -> String {
        "recovered"
    }

    nonisolated func stream(
        messages _: [InferenceMessage],
        options _: InferenceOptions
    ) -> AsyncThrowingStream<String, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield("recovered")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        messages _: [InferenceMessage],
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        await gate.disable()
        return disabledHandoffToolCallResponse()
    }

    func countTokens(in text: String) async throws -> Int {
        max(1, text.count)
    }

    private func disabledHandoffToolCallResponse() -> InferenceResponse {
        InferenceResponse(
            content: nil,
            toolCalls: [
                InferenceResponse.ParsedToolCall(
                    id: "call_disabled_handoff",
                    name: "handoff_to_target",
                    arguments: ["reason": .string("stale route")]
                ),
            ],
            finishReason: .toolCall,
            usage: nil
        )
    }
}

private actor RecordingHandoffReceiver: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Record handoff requests"
    nonisolated let configuration: AgentConfiguration
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil
    nonisolated let inputGuardrails: [any InputGuardrail] = []
    nonisolated let outputGuardrails: [any OutputGuardrail] = []
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private(set) var runInputs: [String] = []
    private(set) var handoffRequests: [HandoffRequest] = []
    private(set) var handoffSessions: [any Session] = []
    private(set) var contextSnapshots: [[String: SendableValue]] = []
    private(set) var contextMessages: [[MemoryMessage]] = []
    private(set) var executionPaths: [[String]] = []

    init(name: String) {
        configuration = AgentConfiguration(name: name, defaultTracingEnabled: false)
    }

    func run(_ input: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        runInputs.append(input)
        return AgentResult(output: "handled \(input)")
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: "handled \(input)"))))
            continuation.finish()
        }
    }

    func cancel() async {}

    func handleHandoff(
        _ request: HandoffRequest,
        context: AgentContext,
        session: (any Session)?,
        observer _: (any AgentObserver)?
    ) async throws -> AgentResult {
        handoffRequests.append(request)
        if let session {
            handoffSessions.append(session)
        }
        contextSnapshots.append(await context.snapshot)
        contextMessages.append(await context.getMessages())
        executionPaths.append(await context.getExecutionPath())
        return AgentResult(output: "handled \(request.input)")
    }
}

private actor RecordingHandoffRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Record handleHandoff without HandoffReceiver"
    nonisolated let configuration: AgentConfiguration
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil
    nonisolated let inputGuardrails: [any InputGuardrail] = []
    nonisolated let outputGuardrails: [any OutputGuardrail] = []
    nonisolated let handoffs: [AnyHandoffConfiguration] = []

    private(set) var runCount = 0
    private(set) var handoffCount = 0
    private(set) var handoffRequests: [HandoffRequest] = []
    private(set) var handoffSessions: [any Session] = []
    private(set) var contextSnapshots: [[String: SendableValue]] = []

    init(name: String) {
        configuration = AgentConfiguration(name: name, defaultTracingEnabled: false)
    }

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
        context: AgentContext,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        handoffCount += 1
        handoffRequests.append(request)
        if let session {
            handoffSessions.append(session)
        }
        contextSnapshots.append(await context.snapshot)
        await observer?.onAgentStart(context: context, agent: self, input: request.input)
        return AgentResult(output: "handled \(request.input)")
    }
}

private actor RecordingStartObserver: AgentObserver {
    private(set) var startAgentNames: [String] = []

    func onAgentStart(context _: AgentContext?, agent: any AgentRuntime, input _: String) async {
        startAgentNames.append(agent.name)
    }
}

private actor HandoffCallbackRecorder {
    private(set) var transferCount = 0
    private(set) var lastTransfer: HandoffInputData?

    func recordTransfer(_ data: HandoffInputData) {
        transferCount += 1
        lastTransfer = data
    }
}
