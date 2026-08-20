// GuardrailError.swift
// Swarm Framework
//
// Comprehensive error types for guardrail execution.

import Foundation

// MARK: - GuardrailError

/// Errors related to guardrail execution.
public enum GuardrailError: Error, Sendable, LocalizedError, Equatable {
    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .inputTripwireTriggered(name, message, _):
            "Input guardrail '\(name)' tripwire triggered: \(message)"
        case let .outputTripwireTriggered(name, agentName, message, _):
            "Output guardrail '\(name)' tripwire triggered for agent '\(agentName)': \(message)"
        case let .toolInputTripwireTriggered(name, toolName, message, _):
            "Tool input guardrail '\(name)' tripwire triggered for tool '\(toolName)': \(message)"
        case let .toolOutputTripwireTriggered(name, toolName, message, _):
            "Tool output guardrail '\(name)' tripwire triggered for tool '\(toolName)': \(message)"
        case let .executionFailed(name, error):
            "Guardrail '\(name)' execution failed: \(error)"
        }
    }

    /// Input guardrail tripwire was triggered
    case inputTripwireTriggered(
        guardrailName: String,
        message: String,
        outputInfo: SendableValue?
    )

    /// Output guardrail tripwire was triggered
    case outputTripwireTriggered(
        guardrailName: String,
        agentName: String,
        message: String,
        outputInfo: SendableValue?
    )

    /// Tool input guardrail tripwire was triggered
    case toolInputTripwireTriggered(
        guardrailName: String,
        toolName: String,
        message: String,
        outputInfo: SendableValue?
    )

    /// Tool output guardrail tripwire was triggered
    case toolOutputTripwireTriggered(
        guardrailName: String,
        toolName: String,
        message: String,
        outputInfo: SendableValue?
    )

    /// Guardrail execution failed
    case executionFailed(guardrailName: String, underlyingError: String)
}

// MARK: CustomDebugStringConvertible

extension GuardrailError: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .inputTripwireTriggered(name, message, outputInfo):
            return "GuardrailError.inputTripwireTriggered(guardrailName: \(name), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .outputTripwireTriggered(name, agentName, message, outputInfo):
            return "GuardrailError.outputTripwireTriggered(guardrailName: \(name), agentName: \(agentName), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .toolInputTripwireTriggered(name, toolName, message, outputInfo):
            return "GuardrailError.toolInputTripwireTriggered(guardrailName: \(name), toolName: \(toolName), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .toolOutputTripwireTriggered(name, toolName, message, outputInfo):
            return "GuardrailError.toolOutputTripwireTriggered(guardrailName: \(name), toolName: \(toolName), message: \(String(describing: message)), outputInfo: \(String(describing: outputInfo)))"
        case let .executionFailed(name, error):
            return "GuardrailError.executionFailed(guardrailName: \(name), underlyingError: \(error))"
        }
    }
}
