// GraphAgent.swift
// HiveSwarm
//
// Bridge adapter that exposes a Hive-native agent graph as a Swarm `AgentRuntime`.

import CryptoKit
import Foundation
import HiveCore
import Swarm

// MARK: - GraphAgent

/// Bridges a Hive-native agent graph into Swarm's `AgentRuntime` protocol.
///
/// This allows `GraphRuntimeAdapter` (which uses Hive's deterministic graph engine
/// for the model-tool loop) to participate in Swarm orchestrations as a regular agent step.
///
/// The adapter translates between the two execution models:
/// - Hive's channel-based results (`finalAnswerKey`, `messagesKey`, `pendingToolCallsKey`)
///   are mapped to `AgentResult` fields (`output`, `toolCalls`, `toolResults`).
/// - Hive's `HiveEvent` stream is mapped to Swarm's `AgentEvent` enum for streaming.
///
/// Example:
/// ```swift
/// let hiveAgent = GraphAgent(
///     runtime: hiveAgentsRuntime,
///     name: "research-agent",
///     instructions: "You are a research assistant."
/// )
///
/// // Use in an orchestration alongside native Swarm agents
/// let result = try await hiveAgent.run("Summarize the latest findings.")
/// print(result.output)
/// ```
struct GraphAgent: AgentRuntime, Sendable {
    // MARK: - Properties

    /// The wrapped Hive agents runtime.
    private let runtime: GraphRuntimeAdapter

    /// The thread ID used for Hive run invocations.
    private let threadID: HiveThreadID

    /// Hive run options applied to each invocation.
    private let runOptions: HiveRunOptions

    /// The current cancellation task handle (actor-isolated for safe mutation).
    private let cancellation: CancellationController

    // MARK: - AgentRuntime Properties

    nonisolated let tools: [any AnyJSONTool]
    nonisolated let instructions: String
    nonisolated let configuration: AgentConfiguration

    // MARK: - Initialization

    /// Creates a new Hive-backed agent bridge.
    ///
    /// - Parameters:
    ///   - runtime: The `GraphRuntimeAdapter` to delegate execution to.
    ///   - name: Display name for this agent in Swarm orchestrations.
    ///   - instructions: LegacyAgent instructions (for display/logging; the actual
    ///     system prompt is managed by the Hive graph's `preModel` node).
    ///   - threadID: The Hive thread to run on. Default: a new UUID-based thread.
    ///   - runOptions: Hive run options. Default: 20 max steps, checkpointing disabled.
    ///   - configuration: Swarm agent configuration. If not provided, a default
    ///     is created using the given name.
    init(
        runtime: GraphRuntimeAdapter,
        name: String,
        instructions: String = "",
        threadID: HiveThreadID = HiveThreadID(UUID().uuidString),
        runOptions: HiveRunOptions = HiveRunOptions(maxSteps: 20, checkpointPolicy: .disabled),
        configuration: AgentConfiguration? = nil
    ) {
        self.runtime = runtime
        self.threadID = threadID
        self.runOptions = runOptions
        self.instructions = instructions
        self.cancellation = CancellationController()
        tools = []

        var config = configuration ?? .default
        config.name = name
        self.configuration = config
    }

    // MARK: - AgentRuntime Methods

    /// Executes the Hive agent graph with the given input.
    ///
    /// This sends a user message through `GraphRunController.start()`,
    /// waits for the outcome, and translates the final channel state into an `AgentResult`.
    ///
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Ignored. Hive manages its own thread-based state.
    ///   - observer: Optional observer for lifecycle callbacks.
    /// - Returns: The translated `AgentResult`.
    /// - Throws: `AgentError` wrapping any `HiveRuntimeError`.
    func run(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResult {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Input cannot be empty")
        }

        let resultBuilder = AgentResult.Builder()
        _ = resultBuilder.start()

        await observer?.onAgentStart(context: nil, agent: self, input: input)

        do {
            let handle = try await runtime.runControl.start(
                threadID: threadID,
                input: input,
                options: runOptions
            )
            await cancellation.track(handle)

            let outcome = try await handle.outcome.value
            let result = try buildResult(from: outcome, builder: resultBuilder)

            await observer?.onAgentEnd(context: nil, agent: self, result: result)
            return result
        } catch let error as HiveRuntimeError {
            let agentError = mapHiveError(error)
            await observer?.onError(context: nil, agent: self, error: agentError)
            throw agentError
        } catch {
            await observer?.onError(context: nil, agent: self, error: error)
            throw error
        }
    }

    /// Streams the agent's execution, mapping Hive events to Swarm `AgentEvent`.
    ///
    /// Unlike `run()`, this method consumes the Hive event stream (`handle.events`)
    /// and maps each `HiveEventKind` to the corresponding `AgentEvent`, providing
    /// real-time visibility into model token generation, tool invocations, and
    /// step lifecycle.
    ///
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - session: Ignored. Hive manages its own thread-based state.
    ///   - observer: Optional observer for lifecycle callbacks.
    /// - Returns: An async stream of `AgentEvent`.
    nonisolated func stream(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { [self] continuation in
            actor FinishGate {
                private var finished = false

                func isFinished() -> Bool {
                    finished
                }

                func markFinished() -> Bool {
                    if finished { return false }
                    finished = true
                    return true
                }
            }

            let finishGate = FinishGate()

            guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let error = AgentError.invalidInput(reason: "Input cannot be empty")
                continuation.yield(.lifecycle(.failed(error: error)))
                continuation.finish(throwing: error)
                return
            }

            continuation.yield(.lifecycle(.started(input: input)))

            let resultBuilder = AgentResult.Builder()
            _ = resultBuilder.start()

            await observer?.onAgentStart(context: nil, agent: self, input: input)

            do {
                let handle = try await runtime.runControl.start(
                    threadID: threadID,
                    input: input,
                    options: runOptions
                )
                await cancellation.track(handle)

                // Fork a task to consume Hive events and yield mapped AgentEvents.
                let eventsTask = Task {
                    do {
                        for try await event in handle.events {
                            if Task.isCancelled { break }
                            if let agentEvent = Self.mapHiveEvent(event) {
                                continuation.yield(agentEvent)
                            }
                        }
                    } catch {
                        if Task.isCancelled { return }
                        guard await finishGate.markFinished() else { return }

                        let mapped: AgentError
                        if let hiveError = error as? HiveRuntimeError {
                            mapped = mapHiveError(hiveError)
                        } else {
                            mapped = AgentError.internalError(reason: "Hive event stream failed: \(error.localizedDescription)")
                        }
                        await observer?.onError(context: nil, agent: self, error: mapped)
                        continuation.yield(.lifecycle(.failed(error: mapped)))
                        continuation.finish(throwing: mapped)
                        handle.outcome.cancel()
                    }
                }

                let outcome: HiveRunOutcome<ChatGraph.Schema>
                do {
                    outcome = try await handle.outcome.value
                } catch {
                    eventsTask.cancel()
                    throw error
                }

                // Wait for all events to be consumed before building the result.
                await eventsTask.value
                if await finishGate.isFinished() { return }

                let result = try buildResult(from: outcome, builder: resultBuilder)

                await observer?.onAgentEnd(context: nil, agent: self, result: result)
                continuation.yield(.lifecycle(.completed(result: result)))
                _ = await finishGate.markFinished()
                continuation.finish()
            } catch let error as HiveRuntimeError {
                guard await finishGate.markFinished() else { return }
                let agentError = mapHiveError(error)
                await observer?.onError(context: nil, agent: self, error: agentError)
                continuation.yield(.lifecycle(.failed(error: agentError)))
                continuation.finish(throwing: agentError)
            } catch {
                guard await finishGate.markFinished() else { return }
                await observer?.onError(context: nil, agent: self, error: error)
                let wrapped = AgentError.internalError(reason: error.localizedDescription)
                continuation.yield(.lifecycle(.failed(error: wrapped)))
                continuation.finish(throwing: error)
            }
        }
    }

    /// Cancels any ongoing Hive run.
    func cancel() async {
        await cancellation.cancelCurrent()
    }

    // MARK: - Event Mapping

    /// Maps a `HiveEvent` to an `AgentEvent`, returning `nil` for events
    /// that have no meaningful Swarm equivalent (e.g., checkpoint, write-applied).
    private static func mapHiveEvent(_ event: HiveEvent) -> AgentEvent? {
        switch event.kind {
        case .runResumed(let interruptID):
            return .observation(.decision(
                "hive.runResumed",
                options: [interruptID.rawValue]
            ))

        case .runInterrupted(let interruptID):
            return .observation(.decision(
                "hive.runInterrupted",
                options: [interruptID.rawValue]
            ))

        case .runCancelled:
            return .lifecycle(.cancelled)

        case .modelInvocationStarted(let model):
            return .observation(.llmStarted(model: model, promptTokens: nil))

        case .modelToken(let text):
            return .output(.token(text))

        case .modelInvocationFinished:
            return .observation(.llmCompleted(model: nil, promptTokens: nil, completionTokens: nil, duration: 0))

        case .toolInvocationStarted(let name):
            let call = toolCall(from: event, toolName: name)
            return .tool(.started(call: call))

        case .toolInvocationFinished(let name, let success):
            let call = toolCall(from: event, toolName: name)
            if success {
                let result = ToolResult(callId: call.id, isSuccess: true, output: .null, duration: .zero)
                return .tool(.completed(call: call, result: result))
            } else {
                let error = AgentError.toolExecutionFailed(toolName: name, underlyingError: "Tool invocation failed")
                return .tool(.failed(call: call, error: error))
            }

        case .stepStarted(let stepIndex, _):
            return .lifecycle(.iterationStarted(number: stepIndex + 1))

        case .stepFinished(let stepIndex, _):
            return .lifecycle(.iterationCompleted(number: stepIndex + 1))

        case .checkpointSaved(let checkpointID):
            return .observation(.decision(
                "hive.checkpointSaved",
                options: [checkpointID.rawValue]
            ))

        case .checkpointLoaded(let checkpointID):
            return .observation(.decision(
                "hive.checkpointLoaded",
                options: [checkpointID.rawValue]
            ))

        case .writeApplied(let channelID, let payloadHash):
            return .observation(.decision(
                "hive.writeApplied.\(channelID.rawValue)",
                options: [payloadHash]
            ))

        default:
            return nil
        }
    }

    private static func toolCall(from event: HiveEvent, toolName: String) -> ToolCall {
        let providerCallId = event.metadata["toolCallID"]
        let stableID = stableUUID(
            for: providerCallId ?? "\(event.id.eventIndex)|\(event.id.stepIndex.map(String.init) ?? "nil")|\(toolName)"
        )
        return ToolCall(
            id: stableID,
            providerCallId: providerCallId,
            toolName: toolName,
            arguments: [:],
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private static func stableUUID(for input: String) -> UUID {
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest)
        precondition(bytes.count >= 16)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Private Methods

    /// Extracts an `AgentResult` from a `HiveRunOutcome`.
    private func buildResult(
        from outcome: HiveRunOutcome<ChatGraph.Schema>,
        builder: AgentResult.Builder
    ) throws -> AgentResult {
        let store: HiveGlobalStore<ChatGraph.Schema>

        switch outcome {
        case let .finished(output, _):
            switch output {
            case let .fullStore(s):
                store = s
            case .channels:
                throw AgentError.internalError(reason: "Hive returned channel-only output; full store required.")
            }

        case let .outOfSteps(maxSteps, output, _):
            switch output {
            case let .fullStore(s):
                store = s
                Log.agents.warning("Hive run hit max steps (\(maxSteps)); returning partial result.")
            case .channels:
                throw AgentError.maxIterationsExceeded(iterations: maxSteps)
            }

        case .interrupted:
            throw AgentError.internalError(reason: "Hive run was interrupted (tool approval required).")

        case let .cancelled(output, _):
            switch output {
            case let .fullStore(s):
                store = s
                Log.agents.info("Hive run was cancelled; returning partial result.")
            case .channels:
                throw AgentError.cancelled
            }
        }

        // Extract final answer
        let finalAnswer: String
        do {
            let answer = try store.get(ChatGraph.Schema.finalAnswerKey)
            finalAnswer = answer ?? ""
        } catch {
            Log.agents.error("Failed to read finalAnswerKey from Hive store: \(error)")
            throw AgentError.internalError(reason: "Failed to extract final answer from Hive: \(error.localizedDescription)")
        }
        _ = builder.setOutput(finalAnswer)

        // Extract tool call information from messages.
        // We correlate ToolCall.id and ToolResult.callId using the Hive tool call ID
        // so that runWithResponse() can build proper ToolCallRecords.
        do {
            let messages = try store.get(ChatGraph.Schema.messagesKey)

            // Map from Hive tool call ID → Swarm UUID for correlation.
            var hiveToSwarmID: [String: UUID] = [:]

            for message in messages where !message.toolCalls.isEmpty {
                for hiveToolCall in message.toolCalls {
                    let swarmID = UUID()
                    hiveToSwarmID[hiveToolCall.id] = swarmID
                    let toolCall = ToolCall(
                        id: swarmID,
                        providerCallId: hiveToolCall.id,
                        toolName: hiveToolCall.name,
                        arguments: parseToolArguments(hiveToolCall.argumentsJSON)
                    )
                    _ = builder.addToolCall(toolCall)
                }
            }

            for message in messages where message.role == .tool {
                guard let hiveCallID = message.toolCallID else { continue }
                let callID: UUID
                if let existing = hiveToSwarmID[hiveCallID] {
                    callID = existing
                } else {
                    // Preserve ToolCall/ToolResult linkage deterministically using a stable UUID.
                    let syntheticID = Self.stableUUID(for: hiveCallID)
                    hiveToSwarmID[hiveCallID] = syntheticID
                    let syntheticCall = ToolCall(
                        id: syntheticID,
                        providerCallId: hiveCallID,
                        toolName: "unknown_tool",
                        arguments: [:]
                    )
                    _ = builder.addToolCall(syntheticCall)
                    callID = syntheticID
                }

                let toolResult = ToolResult(
                    callId: callID,
                    isSuccess: true,
                    output: .string(message.content),
                    duration: .zero
                )
                _ = builder.addToolResult(toolResult)
            }

            // Count model invocations as iterations (assistant messages)
            let assistantCount = messages.filter { $0.role == .assistant }.count
            for _ in 0 ..< max(assistantCount, 1) {
                _ = builder.incrementIteration()
            }
        } catch {
            Log.agents.error("Failed to extract tool calls from Hive messages: \(error)")
            // Set metadata to indicate extraction failure
            _ = builder.setMetadata("extraction_error", .string("Failed to extract tool calls: \(error.localizedDescription)"))
            _ = builder.incrementIteration()
        }

        return builder.build()
    }

    /// Parses Hive tool call argument JSON string into a Swarm-compatible dictionary.
    private func parseToolArguments(_ jsonString: String) -> [String: SendableValue] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["raw": .string(jsonString)]
        }

        var result: [String: SendableValue] = [:]
        for (key, value) in json {
            result[key] = SendableValue.fromJSONValue(value)
        }
        return result
    }

    /// Maps a `HiveRuntimeError` to an appropriate `AgentError`.
    private func mapHiveError(_ error: HiveRuntimeError) -> AgentError {
        switch error {
        case let .invalidRunOptions(reason):
            return .invalidInput(reason: "Invalid Hive run options: \(reason)")
        case let .stepIndexOutOfRange(stepIndex):
            return .internalError(reason: "Hive stepIndex out of range: \(stepIndex)")
        case let .taskOrdinalOutOfRange(ordinal):
            return .internalError(reason: "Hive task ordinal out of range: \(ordinal)")
        case let .invalidTaskLocalFingerprintLength(expected, actual):
            return .internalError(
                reason: "Hive task-local fingerprint invalid length (expected \(expected), got \(actual))."
            )

        case .modelClientMissing:
            return .inferenceProviderUnavailable(reason: "Hive model client is not configured.")
        case .toolRegistryMissing:
            return .internalError(reason: "Hive tool registry is not configured.")
        case .checkpointStoreMissing:
            return .internalError(reason: "Hive checkpoint store required for tool approval policy.")
        case let .checkpointOverrideNotCheckpointed(channelID):
            return .internalError(
                reason: "Hive output projection override includes non-checkpointed channel '\(channelID.rawValue)'."
            )
        case let .checkpointVersionMismatch(expectedSchema, expectedGraph, foundSchema, foundGraph):
            return .internalError(
                reason: """
                Hive checkpoint version mismatch.
                expected(schema=\(expectedSchema), graph=\(expectedGraph))
                found(schema=\(foundSchema), graph=\(foundGraph))
                """
            )
        case let .checkpointDecodeFailed(channelID, errorDescription):
            return .internalError(
                reason: "Hive checkpoint decode failed for channel '\(channelID.rawValue)': \(errorDescription)"
            )
        case let .checkpointEncodeFailed(channelID, errorDescription):
            return .internalError(
                reason: "Hive checkpoint encode failed for channel '\(channelID.rawValue)': \(errorDescription)"
            )
        case let .checkpointCorrupt(field, errorDescription):
            return .internalError(reason: "Hive checkpoint corrupt at '\(field)': \(errorDescription)")
        case let .interruptPending(interruptID):
            return .invalidInput(reason: "Hive interrupt pending: \(interruptID.rawValue)")
        case .noCheckpointToResume:
            return .invalidInput(reason: "Hive resume requested with no checkpoint to resume.")
        case let .checkpointNotFound(id):
            return .invalidInput(reason: "Hive checkpoint not found: \(id.rawValue)")
        case .noInterruptToResume:
            return .invalidInput(reason: "Hive resume requested with no pending interrupt.")
        case let .resumeInterruptMismatch(expected, found):
            return .invalidInput(
                reason: """
                Hive resume interrupt mismatch.
                expected=\(expected.rawValue), found=\(found.rawValue)
                """
            )
        case let .forkSourceCheckpointMissing(threadID, checkpointID):
            return .internalError(
                reason: """
                Hive fork source checkpoint missing for thread '\(threadID.rawValue)' and checkpoint '\(checkpointID?.rawValue ?? "nil")'.
                """
            )
        case .forkCheckpointStoreMissing:
            return .internalError(reason: "Hive fork requested without a checkpoint store.")
        case .forkCheckpointQueryUnsupported:
            return .internalError(reason: "Hive fork requested on a checkpoint store that cannot query checkpoints.")
        case let .forkTargetThreadConflict(threadID):
            return .invalidInput(reason: "Hive fork target thread conflict: \(threadID.rawValue)")
        case let .forkSchemaGraphMismatch(expectedSchema, expectedGraph, foundSchema, foundGraph):
            return .internalError(
                reason: """
                Hive fork checkpoint schema/graph mismatch.
                expected(schema=\(expectedSchema), graph=\(expectedGraph))
                found(schema=\(foundSchema), graph=\(foundGraph))
                """
            )
        case let .forkMalformedCheckpoint(field, errorDescription):
            return .internalError(
                reason: "Hive fork checkpoint malformed at '\(field)': \(errorDescription)"
            )

        case let .unknownNodeID(nodeID):
            return .internalError(reason: "Hive unknown node ID: \(nodeID.rawValue)")
        case let .unknownChannelID(channelID):
            return .invalidInput(reason: "Hive unknown channel ID: \(channelID.rawValue)")
        case let .storeValueMissing(channelID):
            return .internalError(reason: "Hive store value missing for channel: \(channelID.rawValue)")
        case let .channelTypeMismatch(channelID, expectedValueTypeID, actualValueTypeID):
            return .invalidInput(
                reason: """
                Hive channel type mismatch for '\(channelID.rawValue)'.
                expected '\(expectedValueTypeID)', got '\(actualValueTypeID)'.
                """
            )
        case let .scopeMismatch(channelID, expected, actual):
            return .internalError(
                reason: "Hive scope mismatch for channel '\(channelID.rawValue)' (expected \(expected), actual \(actual))."
            )
        case let .missingCodec(channelID):
            return .internalError(reason: "Hive missing codec for channel '\(channelID.rawValue)'.")
        case let .taskLocalFingerprintEncodeFailed(channelID, errorDescription):
            return .internalError(
                reason: """
                Hive task-local fingerprint encode failed for channel '\(channelID.rawValue)': \(errorDescription)
                """
            )

        case let .updatePolicyViolation(channelID, policy, writeCount):
            return .invalidInput(
                reason: """
                Hive update policy violation for '\(channelID.rawValue)' (\(policy)); writeCount=\(writeCount).
                """
            )
        case .taskLocalWriteNotAllowed:
            return .invalidInput(reason: "Hive task-local writes are not allowed for this operation.")
        case let .modelStreamInvalid(reason):
            return .generationFailed(reason: "Hive model stream error: \(reason)")
        case .invalidMessagesUpdate:
            return .internalError(reason: "Hive messages channel received invalid update.")
        case let .missingTaskLocalValue(channelID):
            return .internalError(reason: "Hive missing task-local value for channel '\(channelID.rawValue)'.")
        case let .modelToolLoopMaxModelInvocationsExceeded(maxModelInvocations):
            return .maxIterationsExceeded(iterations: maxModelInvocations)
        case let .internalInvariantViolation(reason):
            return .internalError(reason: "Hive internal invariant violation: \(reason)")
        @unknown default:
            return .internalError(reason: "Unknown Hive runtime error: \(error)")
        }
    }
}

extension GraphAgent: ConversationBranchingRuntime {
    func branchConversationRuntime() async throws -> any AgentRuntime {
        let branchedThreadID = try await runtime.runControl.branch(
            threadID: threadID,
            options: runOptions
        )
        return GraphAgent(
            runtime: runtime,
            name: configuration.name,
            instructions: instructions,
            threadID: branchedThreadID,
            runOptions: runOptions,
            configuration: configuration
        )
    }
}

// MARK: - CancellationController

/// Actor that safely tracks and cancels the current Hive run handle.
///
/// Stores the actual `HiveRunHandle` so cancellation propagates to the Hive runtime,
/// not just to an awaiting wrapper task.
private actor CancellationController {
    private var currentHandle: HiveRunHandle<ChatGraph.Schema>?

    /// Records a new run handle for potential cancellation.
    func track(_ handle: HiveRunHandle<ChatGraph.Schema>) {
        // Cancel any previously tracked run.
        currentHandle?.outcome.cancel()
        currentHandle = handle
    }

    /// Cancels the currently tracked run.
    func cancelCurrent() {
        currentHandle?.outcome.cancel()
        currentHandle = nil
    }
}

// HiveChatRole typed constants are defined in ChatGraph.swift (internal)
// and shared across the HiveSwarm module.
