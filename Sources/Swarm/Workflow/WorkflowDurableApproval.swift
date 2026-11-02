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

/// Another caller is already resuming this durable run.
///
/// Thrown by ``DurableWorkflow/resume(decision:from:)`` (and by
/// ``DurableWorkflow/resume(_:from:)``) instead of executing when a concurrent
/// resume of the same checkpoint holds the run:
///
/// - **Same process:** a second resume of a checkpoint that this process is
///   already resuming through the same checkpoint store fails immediately.
/// - **Across processes:** an approval resume first claims the pause with a
///   compare-and-swap save on the checkpoint store. The loser of that race, or
///   a resume that finds a live claim, fails with this error. A claim left by
///   a crashed process expires after a lease (10 minutes), after which the
///   pause can be resumed again.
///
/// The caller that receives this error has not executed the paused tool.
/// Retry later, or inspect the run instead of resuming it twice.
public struct WorkflowResumeConflict: Error, Sendable, Equatable {
    /// Checkpoint thread being resumed concurrently.
    public let checkpointID: WorkflowCheckpointID
    /// Human-readable explanation of the conflict.
    public let reason: String

    /// Creates a resume-conflict error.
    public init(checkpointID: WorkflowCheckpointID, reason: String) {
        self.checkpointID = checkpointID
        self.reason = reason
    }
}

extension WorkflowResumeConflict: LocalizedError {
    public var errorDescription: String? {
        "Durable workflow '\(checkpointID.rawValue)' is already being resumed: \(reason)"
    }
}

/// A resumed step keeps pausing without reaching the call it was approved for.
///
/// Durable approvals replay the paused step from its start. When the model
/// asks for something different on replay (for example `delete_vm(id: vm-2)`
/// after `delete_vm(id: vm-1)` was approved), the step pauses again for the new
/// call and the earlier approval stays unused. After ``maxAttempts``
/// consecutive approve-resumes that end in such a pause, the resume throws this
/// error instead of asking again. Nothing is executed and the run stays paused
/// on its last request: resolve it with `.reject`, or fix the step so that its
/// replay is deterministic.
public struct WorkflowApprovalReplayDiverged: Error, Sendable, Equatable {
    /// Consecutive diverging approve-resumes allowed before this error.
    public static let maxAttempts = 3

    /// Checkpoint thread whose step keeps diverging.
    public let checkpointID: WorkflowCheckpointID
    /// Tool name of an approved call that the replay never reached.
    public let toolName: String
    /// Consecutive diverging approve-resumes, including this one.
    public let attempts: Int

    /// Creates a replay-divergence error.
    public init(checkpointID: WorkflowCheckpointID, toolName: String, attempts: Int) {
        self.checkpointID = checkpointID
        self.toolName = toolName
        self.attempts = attempts
    }
}

extension WorkflowApprovalReplayDiverged: LocalizedError {
    public var errorDescription: String? {
        "Durable workflow '\(checkpointID.rawValue)' replayed \(attempts) times without reaching "
            + "the approved '\(toolName)' call; reject the pending approval or make the step deterministic"
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

/// Recorded outcome of a tool call that already executed in a paused step.
enum WorkflowJournaledOutcome: Sendable, Equatable, Codable {
    case success(SendableValue)
    case failure(String)
}

/// A tool call that executed during an earlier run of a paused step.
///
/// Carried in the approval envelopes so the replayed step returns the recorded
/// outcome instead of executing the call again.
struct WorkflowJournaledCall: Sendable, Equatable, Codable {
    var call: WorkflowApprovedCall
    var outcome: WorkflowJournaledOutcome
}

/// Per-step-execution approval and replay state for durable runs.
///
/// **Approvals are one-shot.** Within one step execution a human approval
/// authorizes one execution of the approved call. Approving `delete_vm(id: vm-1)` does not let
/// the step run that call a second time: the second identical call consumes
/// nothing and pauses for its own approval. Approvals are matched by tool name
/// and exact arguments, as a multiset, so the order in which a replay reaches
/// them does not matter.
///
/// **Executed calls replay from the journal.** Every tool call that executes
/// while the gate is armed is recorded. When the step pauses, the journal goes
/// into the interrupt payload. The resumed step replays from its start and
/// returns the recorded outcome for each call that matches a journal entry (by
/// tool name and exact arguments, first unused entry first) instead of
/// executing it again. Calls recorded during the current execution are not
/// replayable within it, so a repeated identical call still runs (or pauses)
/// on its own.
actor WorkflowApprovalLedger {
    private var remaining: [WorkflowApprovedCall]
    private let priorJournal: [WorkflowJournaledCall]
    private var replayable: [WorkflowJournaledCall]
    private var recorded: [WorkflowJournaledCall] = []

    init(approved: [WorkflowApprovedCall], journal: [WorkflowJournaledCall] = []) {
        remaining = approved
        priorJournal = journal
        replayable = journal
    }

    /// Consumes one matching approval. Returns `false` when none is left.
    func consume(_ call: WorkflowApprovedCall) -> Bool {
        guard let index = remaining.firstIndex(of: call) else { return false }
        remaining.remove(at: index)
        return true
    }

    /// Consumes and returns the recorded outcome of a matching earlier execution.
    func replay(_ call: WorkflowApprovedCall) -> WorkflowJournaledOutcome? {
        guard let index = replayable.firstIndex(where: { $0.call == call }) else { return nil }
        return replayable.remove(at: index).outcome
    }

    /// Records a call that executed in this step execution.
    func record(_ call: WorkflowApprovedCall, outcome: WorkflowJournaledOutcome) {
        recorded.append(WorkflowJournaledCall(call: call, outcome: outcome))
    }

    /// Approvals not yet consumed.
    var unusedApprovals: [WorkflowApprovedCall] {
        remaining
    }

    /// Every call executed in this step so far, across all its executions.
    var journal: [WorkflowJournaledCall] {
        priorJournal + recorded
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

    /// Recorded outcome for `call` when an earlier run of this step executed it.
    static func replay(call: ToolCall) async -> WorkflowJournaledOutcome? {
        guard let ledger else { return nil }
        return await ledger.replay(WorkflowApprovedCall(toolName: call.toolName, arguments: call.arguments))
    }

    /// Journals an executed call so a replay of this step does not execute it again.
    static func record(call: ToolCall, outcome: WorkflowJournaledOutcome) async {
        guard let ledger else { return }
        await ledger.record(WorkflowApprovedCall(toolName: call.toolName, arguments: call.arguments), outcome: outcome)
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
    /// Set while a resume holds the pause; absent in payloads written before
    /// claims existed, which decode as unclaimed.
    var claim: WorkflowApprovalClaim?
    /// Calls the paused step already executed; `nil` in older payloads.
    var journal: [WorkflowJournaledCall]?
    /// Consecutive approve-resumes that paused again without reaching an
    /// approved call; `nil` in older payloads.
    var divergentResumes: Int?

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

/// A resume's hold on a paused approval, recorded in the interrupt payload.
///
/// Written with a compare-and-swap checkpoint save before the resumed step
/// runs, so only one resume (in any process) executes the approved call.
struct WorkflowApprovalClaim: Sendable, Equatable, Codable {
    /// How long a claim blocks other resumes. Bounds the wait after a crash
    /// mid-resume; a resume that outlives it can be taken over.
    static let lease: TimeInterval = 600

    var token: String
    var claimedAt: Date

    func isLive(at now: Date) -> Bool {
        now.timeIntervalSince(claimedAt) < Self.lease
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
    /// Calls the paused step already executed; `nil` in older payloads.
    var journal: [WorkflowJournaledCall]?
    /// Divergence streak carried from the paused request; `nil` in older payloads.
    var divergentResumes: Int?

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
