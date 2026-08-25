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
}
