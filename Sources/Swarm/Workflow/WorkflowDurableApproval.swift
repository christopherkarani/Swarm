import Foundation

/// A durable workflow paused for human approval of a tool call.
///
/// `DurableWorkflow.execute(_:)` throws this error instead of returning when a
/// step reaches a tool whose ``ToolExecutionSemantics/runtimePolicy()``
/// reports `requiresApproval`. The tool has not executed. Inspect
/// ``toolName``/``arguments``, then continue with
/// ``DurableWorkflow/resume(decision:from:)``: ``WorkflowApprovalDecision/approve``
/// executes the tool and continues the run, ``WorkflowApprovalDecision/reject``
/// fails with ``WorkflowError/humanApprovalRejected(prompt:reason:)``.
///
/// The pause survives process restarts: the checkpoint holds the paused step
/// cursor, and a fresh process can resume from the same checkpoint store.
public struct WorkflowApprovalRequired: Error, Sendable, Equatable {
    /// Name of the tool awaiting approval.
    public let toolName: String

    /// Arguments the tool would execute with.
    public let arguments: [String: SendableValue]

    /// Step cursor of the paused step. The checkpoint preserves this cursor;
    /// the resumed run replays the step from its start.
    public let stepCursor: Int

    /// Checkpoint thread holding the paused state.
    public let checkpointID: WorkflowCheckpointID

    /// Runtime interrupt identifier for this pause, for log correlation.
    public let interruptID: String

    /// Creates an approval-required error.
    public init(
        toolName: String,
        arguments: [String: SendableValue],
        stepCursor: Int,
        checkpointID: WorkflowCheckpointID,
        interruptID: String
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.stepCursor = stepCursor
        self.checkpointID = checkpointID
        self.interruptID = interruptID
    }
}

extension WorkflowApprovalRequired: LocalizedError {
    public var errorDescription: String? {
        "Tool '\(toolName)' requires approval at workflow step \(stepCursor) "
            + "(checkpoint: \(checkpointID.rawValue))"
    }
}

extension WorkflowApprovalRequired: CustomDebugStringConvertible {
    public var debugDescription: String {
        "WorkflowApprovalRequired(toolName: \(toolName), stepCursor: \(stepCursor), "
            + "checkpointID: \(checkpointID.rawValue), interruptID: \(interruptID))"
    }
}

/// Human decision for a paused durable tool approval.
///
/// Pass to ``DurableWorkflow/resume(decision:from:)``. There is no
/// edited-arguments resume: `.approve` executes the paused call exactly as
/// requested, `.reject` fails the run.
public enum WorkflowApprovalDecision: String, Sendable, Equatable, Codable {
    /// Execute the paused tool call and continue the run.
    case approve
    /// Fail the run with ``WorkflowError/humanApprovalRejected(prompt:reason:)``.
    case reject
}

/// A tool call approved earlier in the current pause chain.
///
/// Approvals accumulate across replays so a resumed step that reaches a second
/// approval-required tool pauses for that tool without losing the first
/// approval. Carried inside the versioned JSON envelopes only.
struct WorkflowApprovedCall: Sendable, Equatable, Hashable, Codable {
    var toolName: String
    var arguments: [String: SendableValue]
}

/// Throw-and-replay carrier from the tool gate to the durable workflow node.
///
/// Thrown by ``WorkflowDurableApprovalGate/check(call:registry:agent:context:observer:)``
/// instead of executing an approval-required tool. Never escapes the durable
/// engine: `workflowNode` catches it and returns an interrupt output.
struct WorkflowToolApprovalRequest: Error, Sendable {
    let toolName: String
    let arguments: [String: SendableValue]
}

/// Task-local gate that pauses durable runs on approval-required tools.
///
/// `nil` (the default) disables the gate, so direct `Agent.run` and direct
/// workflow execution are unaffected. The durable workflow node arms it around
/// step execution: `[]` pauses on every approval-required tool, and an
/// approved resume arms it with the calls approved so far in the pause chain.
enum WorkflowDurableApprovalGate {
    @TaskLocal static var allowed: [WorkflowApprovedCall]?

    static func check(
        call: ToolCall,
        registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        observer: (any AgentObserver)?
    ) async throws {
        guard let allowed else { return }
        guard let tool = await registry.tool(named: call.toolName) else { return }
        guard tool.executionSemantics.runtimePolicy().requiresApproval else { return }
        let candidate = WorkflowApprovedCall(toolName: call.toolName, arguments: call.arguments)
        guard !allowed.contains(candidate) else { return }
        await observer?.onToolApprovalRequested(context: context, agent: agent, call: call)
        throw WorkflowToolApprovalRequest(toolName: call.toolName, arguments: call.arguments)
    }
}

#if SWARM_INTEGRATIONS

/// Versioned JSON envelope for a durable approval interrupt payload.
///
/// `WorkflowDurableSchema` keeps `String` interrupt/resume payloads for schema
/// compatibility; the structure lives inside these envelopes. Unknown versions
/// or kinds decode to ``WorkflowError/invalidWorkflow(reason:)`` so old code
/// rejects new envelopes loudly instead of misbehaving.
struct WorkflowApprovalRequestEnvelope: Sendable, Equatable, Codable {
    static let currentVersion = 1
    static let kindValue = "swarm.toolApprovalRequest"

    var version: Int = 1
    var kind: String = kindValue
    var toolName: String
    var arguments: [String: SendableValue]
    var stepCursor: Int
    var approved: [WorkflowApprovedCall] = []

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WorkflowError.invalidWorkflow(reason: "durable approval request payload is not valid UTF-8")
        }
        return string
    }

    static func decoded(from string: String) throws -> Self {
        guard let data = string.data(using: .utf8) else {
            throw WorkflowError.invalidWorkflow(reason: "durable approval request payload is not valid UTF-8")
        }
        let envelope: Self
        do {
            envelope = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw WorkflowError.invalidWorkflow(reason: "durable approval request payload is not valid JSON")
        }
        guard envelope.version == currentVersion, envelope.kind == kindValue else {
            throw WorkflowError.invalidWorkflow(
                reason: "unsupported durable approval request payload "
                    + "(version: \(envelope.version), kind: \(envelope.kind))"
            )
        }
        return envelope
    }
}

/// Versioned JSON envelope for a durable approval resume payload.
struct WorkflowApprovalDecisionEnvelope: Sendable, Equatable, Codable {
    static let currentVersion = 1
    static let kindValue = "swarm.toolApprovalDecision"

    var version: Int = 1
    var kind: String = kindValue
    var decision: WorkflowApprovalDecision
    var toolName: String
    var arguments: [String: SendableValue]
    var approved: [WorkflowApprovedCall] = []

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WorkflowError.invalidWorkflow(reason: "durable approval decision payload is not valid UTF-8")
        }
        return string
    }

    static func decoded(from string: String) throws -> Self {
        guard let data = string.data(using: .utf8) else {
            throw WorkflowError.invalidWorkflow(reason: "durable approval decision payload is not valid UTF-8")
        }
        let envelope: Self
        do {
            envelope = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw WorkflowError.invalidWorkflow(reason: "durable approval decision payload is not valid JSON")
        }
        guard envelope.version == currentVersion, envelope.kind == kindValue else {
            throw WorkflowError.invalidWorkflow(
                reason: "unsupported durable approval decision payload "
                    + "(version: \(envelope.version), kind: \(envelope.kind))"
            )
        }
        return envelope
    }
}

#endif
