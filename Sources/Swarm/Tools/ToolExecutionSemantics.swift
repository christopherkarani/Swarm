import Foundation

/// Declares the side-effect profile of a tool.
enum ToolSideEffectLevel: String, Codable, Sendable, Equatable {
    case unspecified
    case readOnly = "read_only"
    case localMutation = "local_mutation"
    case externalMutation = "external_mutation"
}

/// Declares whether a tool call may be retried safely by an orchestrator.
enum ToolRetryPolicy: String, Codable, Sendable, Equatable {
    case automatic
    case safe
    case unsafe
    case callerManaged = "caller_managed"
}

/// Declares whether a tool call should require approval independently of runtime defaults.
enum ToolApprovalRequirement: String, Codable, Sendable, Equatable {
    case automatic
    case never
    case always
}

/// Declares how durable a tool result is expected to be outside the live transcript.
enum ToolResultDurability: String, Codable, Sendable, Equatable {
    case unspecified
    case transcriptOnly = "transcript_only"
    case artifactBacked = "artifact_backed"
    case externalReference = "external_reference"
}

/// Swarm-owned execution semantics that higher layers can use for governance decisions.
///
/// The struct remains public because it appears in public signatures outside
/// this file (`Tool.executionSemantics`, `FunctionTool`, `WebSearchTool`);
/// its payload enums are internal.
public struct ToolExecutionSemantics: Codable, Sendable, Equatable {
    var sideEffectLevel: ToolSideEffectLevel
    var retryPolicy: ToolRetryPolicy
    var approvalRequirement: ToolApprovalRequirement
    var resultDurability: ToolResultDurability

    init(
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

    /// Default semantics used across public tool initializers. Kept
    /// `@usableFromInline` so existing default arguments in public
    /// initializers keep compiling without re-exposing the payload enums.
    @usableFromInline
    static let automatic = ToolExecutionSemantics()
}
