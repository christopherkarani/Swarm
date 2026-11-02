import Foundation

/// A durable workflow paused for human approval of a tool call.
///
/// `DurableWorkflow.execute(_:)` throws this error instead of returning when a
/// step reaches a tool whose ``ToolExecutionSemantics/runtimePolicy()``
/// reports `requiresApproval`. The tool has not executed. Inspect
/// ``toolName``/``arguments``, then continue with
/// ``DurableWorkflow/resume(decision:from:)``: ``WorkflowApprovalDecision/approve``
/// replays the step and lets this call through once,
/// ``WorkflowApprovalDecision/reject`` ends the run durably and fails with
/// ``WorkflowError/humanApprovalRejected(prompt:reason:)``.
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
/// edited-arguments resume.
public enum WorkflowApprovalDecision: String, Sendable, Equatable, Codable {
    /// Approve the paused call and continue the run.
    ///
    /// The resumed run replays the paused step from its start, inference
    /// included. The approved call executes only if the replay regenerates the
    /// same tool name and arguments; otherwise the run pauses again with a new
    /// ``WorkflowApprovalRequired`` carrying the regenerated call.
    case approve
    /// Fail the run with ``WorkflowError/humanApprovalRejected(prompt:reason:)``.
    ///
    /// The rejection is checkpointed and final: later decisions or resumes on
    /// the run report the same error without executing.
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

    /// Builds a call whose arguments went through the same JSON round-trip as
    /// the checkpointed envelopes, so a live call compares equal to its stored
    /// approval (for example `.double(2.0)` decodes back as `.int(2)`).
    static func normalized(toolName: String, arguments: [String: SendableValue]) -> Self {
        guard let data = try? JSONEncoder().encode(arguments),
              let decoded = try? JSONDecoder().decode([String: SendableValue].self, from: data)
        else {
            return Self(toolName: toolName, arguments: arguments)
        }
        return Self(toolName: toolName, arguments: decoded)
    }
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

/// Approvals available to one durable step execution, each usable once.
///
/// Within one step execution a human approval authorizes one execution of the
/// approved call (a later resume replays the step with a fresh ledger). Approving `delete_vm(id: vm-1)` does not let the step run that call a second
/// time: the second identical call consumes nothing and pauses for its own
/// approval. Approvals are matched by tool name and exact arguments, as a
/// multiset, so the order in which a replay reaches them does not matter.
actor WorkflowApprovalLedger {
    private var remaining: [WorkflowApprovedCall]

    init(approved: [WorkflowApprovedCall]) {
        remaining = approved
    }

    /// Consumes one matching approval. Returns `false` when none is left.
    func consume(_ call: WorkflowApprovedCall) -> Bool {
        guard let index = remaining.firstIndex(of: call) else { return false }
        remaining.remove(at: index)
        return true
    }
}

/// Task-local gate that pauses durable runs on approval-required tools.
///
/// `nil` (the default) disables the gate, so direct `Agent.run` and direct
/// workflow execution are unaffected. The durable workflow node arms it around
/// step execution with a fresh ``WorkflowApprovalLedger``: empty pauses on
/// every approval-required tool, and an approved resume holds the calls
/// approved so far in the pause chain, each consumable once.
enum WorkflowDurableApprovalGate {
    @TaskLocal static var ledger: WorkflowApprovalLedger?

    static func check(
        call: ToolCall,
        registry: ToolRegistry,
        agent: any AgentRuntime,
        context: AgentContext?,
        observer: (any AgentObserver)?
    ) async throws {
        guard let ledger else { return }
        guard let tool = await registry.tool(named: call.toolName) else { return }
        guard tool.executionSemantics.runtimePolicy().requiresApproval else { return }
        let candidate = WorkflowApprovedCall.normalized(toolName: call.toolName, arguments: call.arguments)
        guard await !ledger.consume(candidate) else { return }
        await observer?.onToolApprovalRequested(context: context, agent: agent, call: call)
        throw WorkflowToolApprovalRequest(toolName: call.toolName, arguments: call.arguments)
    }
}

#if SWARM_INTEGRATIONS

/// In-process mutual exclusion for approval decisions on one checkpoint thread.
///
/// Serializes "read pending interrupt → resume → commit" so two concurrent
/// decisions for the same run cannot both observe the same pending interrupt.
/// The second caller sees the committed outcome instead. It does not span
/// processes: deliver each decision once per checkpoint across processes.
actor WorkflowDurableDecisionLock {
    static let shared = WorkflowDurableDecisionLock()

    private var held: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    nonisolated func withLock<T: Sendable>(
        _ key: String,
        _ body: () async throws -> T
    ) async throws -> T {
        await acquire(key)
        do {
            let value = try await body()
            await release(key)
            return value
        } catch {
            await release(key)
            throw error
        }
    }

    private func acquire(_ key: String) async {
        guard held.contains(key) else {
            held.insert(key)
            return
        }
        // Ownership is handed over by `release`, so the key stays held.
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }

    private func release(_ key: String) {
        guard var queue = waiters[key], !queue.isEmpty else {
            held.remove(key)
            return
        }
        let next = queue.removeFirst()
        waiters[key] = queue.isEmpty ? nil : queue
        next.resume()
    }
}

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
