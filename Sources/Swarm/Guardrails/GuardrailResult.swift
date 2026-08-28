// GuardrailResult.swift
// Swarm Framework
//
// Result type for guardrail validation checks.
// Indicates whether a tripwire was triggered and provides diagnostic information.

import Foundation

// MARK: - GuardrailResult

/// The result of a guardrail validation check.
///
/// `GuardrailResult` is a closed outcome: validation either passed or a tripwire
/// fired. Construct values with the enum cases (the historical factory names):
///
/// | Case | Purpose | Tripwire |
/// |------|---------|----------|
/// | ``passed(message:outputInfo:metadata:)`` | Validation succeeded | `false` |
/// | ``tripwire(message:outputInfo:metadata:)`` | Validation failed | `true` |
///
/// A tripwire always carries a ``message``. Compatibility accessors
/// (``tripwireTriggered``, ``message``, ``outputInfo``, ``metadata``) preserve
/// the previous stored-property surface for runners, observers, and tests.
///
/// ## Creating Results
///
/// ```swift
/// return .passed()
/// return .passed(message: "Input validation successful")
/// return .tripwire(message: "Sensitive data detected")
/// return .tripwire(
///     message: "PII detected in input",
///     outputInfo: .dictionary([
///         "violationType": .string("EMAIL_DETECTED"),
///         "position": .int(42)
///     ]),
///     metadata: [
///         "severity": .string("high"),
///         "confidence": .double(0.95)
///     ]
/// )
/// ```
///
/// - SeeAlso: ``InputGuardrail``, ``OutputGuardrail``, ``GuardrailError``
public enum GuardrailResult: Sendable, Equatable {
    /// Validation succeeded; processing continues.
    ///
    /// - Parameters:
    ///   - message: Optional description of what passed.
    ///   - outputInfo: Optional structured diagnostics about what was checked.
    ///   - metadata: Operational data about the check (timing, model version, cache).
    case passed(
        message: String? = nil,
        outputInfo: SendableValue? = nil,
        metadata: [String: SendableValue] = [:]
    )

    /// Validation failed; the runner converts this to a ``GuardrailError``.
    ///
    /// - Parameters:
    ///   - message: Required description of the tripwire. Included in ``GuardrailError``.
    ///   - outputInfo: Optional structured diagnostics about the violation.
    ///   - metadata: Operational data about the check.
    case tripwire(
        message: String,
        outputInfo: SendableValue? = nil,
        metadata: [String: SendableValue] = [:]
    )

    /// Indicates whether a tripwire was triggered during the check.
    public var tripwireTriggered: Bool {
        switch self {
        case .passed:
            false
        case .tripwire:
            true
        }
    }

    /// Diagnostic information about what was validated or what violation was detected.
    public var outputInfo: SendableValue? {
        switch self {
        case let .passed(_, outputInfo, _), let .tripwire(_, outputInfo, _):
            outputInfo
        }
    }

    /// Human-readable description of the result.
    ///
    /// For tripwires this is always non-nil (the associated ``tripwire(message:outputInfo:metadata:)``
    /// message). For passes it matches the optional associated message.
    public var message: String? {
        switch self {
        case let .passed(message, _, _):
            message
        case let .tripwire(message, _, _):
            message
        }
    }

    /// Operational metadata about the guardrail execution itself.
    public var metadata: [String: SendableValue] {
        switch self {
        case let .passed(_, _, metadata), let .tripwire(_, _, metadata):
            metadata
        }
    }

    /// Creates a result from the historical boolean stored-property shape.
    ///
    /// Prefer ``passed(message:outputInfo:metadata:)`` or
    /// ``tripwire(message:outputInfo:metadata:)``. A tripwire with a nil message
    /// is stored as `"Tripwire triggered"`.
    @available(*, deprecated, message: "Use GuardrailResult.passed(...) or .tripwire(message:)")
    public init(
        tripwireTriggered: Bool,
        outputInfo: SendableValue? = nil,
        message: String? = nil,
        metadata: [String: SendableValue] = [:]
    ) {
        if tripwireTriggered {
            self = .tripwire(
                message: message ?? "Tripwire triggered",
                outputInfo: outputInfo,
                metadata: metadata
            )
        } else {
            self = .passed(
                message: message,
                outputInfo: outputInfo,
                metadata: metadata
            )
        }
    }
}

// MARK: CustomDebugStringConvertible

extension GuardrailResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        var components: [String] = ["GuardrailResult("]
        components.append("tripwireTriggered: \(tripwireTriggered)")
        if let message {
            components.append("message: \"\(message)\"")
        }
        if let outputInfo {
            components.append("outputInfo: \(outputInfo.debugDescription)")
        }
        if !metadata.isEmpty {
            components.append("metadata: \(metadata)")
        }
        return components.joined(separator: ", ") + ")"
    }
}
