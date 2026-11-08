// WorkflowError.swift
// Swarm Framework
//
// Comprehensive error types for multi-agent workflow operations.

import Foundation

// MARK: - WorkflowError

/// Errors that can occur during multi-agent workflow execution.
public enum WorkflowError: Error, Sendable, Equatable {
    // MARK: - Agent Registration Errors

    /// An agent with the given name was not found in the orchestrator.
    case agentNotFound(name: String)

    /// No agents are configured in the orchestrator.
    case noAgentsConfigured

    // MARK: - Handoff Errors

    /// LegacyAgent handoff failed between source and target agents.
    case handoffFailed(source: String, target: String, reason: String)

    /// LegacyAgent handoff was skipped because it was disabled.
    case handoffSkipped(from: String, to: String, reason: String)

    // MARK: - Routing Errors

    /// Routing decision failed to determine the next agent.
    case routingFailed(reason: String)

    /// Route condition is invalid or cannot be evaluated.
    case invalidRouteCondition(reason: String)

    // MARK: - Parallel Execution Errors

    /// Merge strategy failed to combine parallel agent results.
    case mergeStrategyFailed(reason: String)

    /// All agents in parallel execution failed.
    case allAgentsFailed(errors: [String])

    /// The durable workflow engine was required but unavailable for this build/runtime.
    case durableRuntimeUnavailable(reason: String)

    // MARK: - Workflow Control Errors

    /// Workflow was interrupted (e.g. by an `Interrupt` step).
    case workflowInterrupted(reason: String)

    /// User-configurable orchestration graph failed validation.
    case invalidGraph(WorkflowValidationError)

    /// Human approval request timed out.
    case humanApprovalTimeout(prompt: String)

    /// Human approval was rejected.
    case humanApprovalRejected(prompt: String, reason: String)

    /// Workflow definition is invalid or cannot be executed.
    case invalidWorkflow(reason: String)

    /// No checkpoint exists for the requested checkpoint ID.
    case checkpointNotFound(id: String)

    /// Attempted resume with a workflow definition that does not match the saved checkpoint.
    case resumeDefinitionMismatch(reason: String)
}

// MARK: LocalizedError

extension WorkflowError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .agentNotFound(name):
            return "LegacyAgent not found: \(name)"
        case .noAgentsConfigured:
            return "No agents configured in workflow coordinator"
        case let .handoffFailed(source, target, reason):
            return "Handoff failed from '\(source)' to '\(target)': \(reason)"
        case let .handoffSkipped(from, to, reason):
            return "Handoff skipped from '\(from)' to '\(to)': \(reason)"
        case let .routingFailed(reason):
            return "Routing decision failed: \(reason)"
        case let .invalidRouteCondition(reason):
            return "Invalid route condition: \(reason)"
        case let .mergeStrategyFailed(reason):
            return "Merge strategy failed: \(reason)"
        case let .allAgentsFailed(errors):
            let errorList = errors.joined(separator: ", ")
            return "All parallel agents failed: [\(errorList)]"
        case let .durableRuntimeUnavailable(reason):
            return "Workflow durable runtime unavailable: \(reason)"
        case let .workflowInterrupted(reason):
            return "Workflow interrupted: \(reason)"
        case let .invalidGraph(validationError):
            return "Invalid workflow graph: \(validationError.localizedDescription)"
        case let .humanApprovalTimeout(prompt):
            return "Human approval timed out for: \(prompt)"
        case let .humanApprovalRejected(prompt, reason):
            return "Human approval rejected for '\(prompt)': \(reason)"
        case let .invalidWorkflow(reason):
            return "Invalid workflow: \(reason)"
        case let .checkpointNotFound(id):
            return "Workflow checkpoint not found: \(id)"
        case let .resumeDefinitionMismatch(reason):
            return "Workflow resume definition mismatch: \(reason)"
        }
    }
}

// MARK: CustomDebugStringConvertible

extension WorkflowError: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .agentNotFound(name):
            return "WorkflowError.agentNotFound(name: \(name))"
        case .noAgentsConfigured:
            return "WorkflowError.noAgentsConfigured"
        case let .handoffFailed(source, target, reason):
            return "WorkflowError.handoffFailed(source: \(source), target: \(target), reason: \(reason))"
        case let .handoffSkipped(from, to, reason):
            return "WorkflowError.handoffSkipped(from: \(from), to: \(to), reason: \(reason))"
        case let .routingFailed(reason):
            return "WorkflowError.routingFailed(reason: \(reason))"
        case let .invalidRouteCondition(reason):
            return "WorkflowError.invalidRouteCondition(reason: \(reason))"
        case let .mergeStrategyFailed(reason):
            return "WorkflowError.mergeStrategyFailed(reason: \(reason))"
        case let .allAgentsFailed(errors):
            return "WorkflowError.allAgentsFailed(errors: \(errors))"
        case let .durableRuntimeUnavailable(reason):
            return "WorkflowError.durableRuntimeUnavailable(reason: \(reason))"
        case let .workflowInterrupted(reason):
            return "WorkflowError.workflowInterrupted(reason: \(reason))"
        case let .invalidGraph(validationError):
            return "WorkflowError.invalidGraph(\(validationError))"
        case let .humanApprovalTimeout(prompt):
            return "WorkflowError.humanApprovalTimeout(prompt: \(prompt))"
        case let .humanApprovalRejected(prompt, reason):
            return "WorkflowError.humanApprovalRejected(prompt: \(prompt), reason: \(reason))"
        case let .invalidWorkflow(reason):
            return "WorkflowError.invalidWorkflow(reason: \(reason))"
        case let .checkpointNotFound(id):
            return "WorkflowError.checkpointNotFound(id: \(id))"
        case let .resumeDefinitionMismatch(reason):
            return "WorkflowError.resumeDefinitionMismatch(reason: \(reason))"
        }
    }
}
