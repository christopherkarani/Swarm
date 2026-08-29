import Foundation

/// Declares the side-effect profile of a tool.
public enum ToolSideEffectLevel: String, Codable, Sendable, Equatable {
    case unspecified
    case readOnly = "read_only"
    case localMutation = "local_mutation"
    case externalMutation = "external_mutation"
}

/// Declares whether a tool call may be retried safely by an orchestrator.
public enum ToolRetryPolicy: String, Codable, Sendable, Equatable {
    case automatic
    case safe
    case unsafe
    case callerManaged = "caller_managed"
}

/// Declares whether a tool call should require approval independently of runtime defaults.
public enum ToolApprovalRequirement: String, Codable, Sendable, Equatable {
    case automatic
    case never
    case always
}

/// Declares how durable a tool result is expected to be outside the live transcript.
public enum ToolResultDurability: String, Codable, Sendable, Equatable {
    case unspecified
    case transcriptOnly = "transcript_only"
    case artifactBacked = "artifact_backed"
    case externalReference = "external_reference"
}

/// Swarm-owned execution semantics that higher layers can use for governance decisions.
public struct ToolExecutionSemantics: Codable, Sendable, Equatable {
    public var sideEffectLevel: ToolSideEffectLevel
    public var retryPolicy: ToolRetryPolicy
    public var approvalRequirement: ToolApprovalRequirement
    public var resultDurability: ToolResultDurability

    public init(
        sideEffectLevel: ToolSideEffectLevel = .unspecified,
        retryPolicy: ToolRetryPolicy = .automatic,
        approvalRequirement: ToolApprovalRequirement = .automatic,
        resultDurability: ToolResultDurability = .unspecified
    ) {
        self.sideEffectLevel = sideEffectLevel
        self.retryPolicy = retryPolicy
        self.approvalRequirement = approvalRequirement
        self.resultDurability = resultDurability
    }

    public static let automatic = ToolExecutionSemantics()

    /// Governance bits derived from declared semantics.
    ///
    /// ``ParallelToolExecutor`` uses ``mayRunInParallel`` so explicit
    /// ``ToolSideEffectLevel/externalMutation`` does not overlap other calls.
    /// The Engine host path does not add approval or retry gates from these values.
    public struct RuntimePolicy: Equatable, Sendable {
        /// Whether an orchestrator may retry this tool without caller intervention.
        public var mayRetryAutomatically: Bool
        /// Whether a higher layer should require approval before running the tool.
        public var requiresApproval: Bool
        /// Whether the tool may share a concurrent batch with other calls.
        public var mayRunInParallel: Bool
    }

    /// Pure runtime decision for retry, approval, and parallel eligibility.
    ///
    /// ``automatic`` preserves today's Engine behavior: automatic retry is
    /// allowed, approval is not required, and the tool may run in parallel.
    /// Explicit ``ToolSideEffectLevel/externalMutation`` is not parallel-eligible.
    public func runtimePolicy() -> RuntimePolicy {
        let mayRetryAutomatically: Bool = switch retryPolicy {
        case .automatic, .safe: true
        case .unsafe, .callerManaged: false
        }
        let requiresApproval: Bool = switch approvalRequirement {
        case .automatic, .never: false
        case .always: true
        }
        let mayRunInParallel: Bool = switch sideEffectLevel {
        case .unspecified, .readOnly, .localMutation: true
        case .externalMutation: false
        }
        return RuntimePolicy(
            mayRetryAutomatically: mayRetryAutomatically,
            requiresApproval: requiresApproval,
            mayRunInParallel: mayRunInParallel
        )
    }
}
