// GuardrailV3.swift
// Swarm Framework
//
// Unified guardrail type replacing InputGuardrail, OutputGuardrail, and 16 other types.

import Foundation

/// Unified guardrail type for input and output validation.
///
/// Replaces 18 separate guardrail types with a single enum using dot-syntax.
///
/// ```swift
/// let agent = AgentV3("assistant", guardrails: [.maxInput(500), .inputNotEmpty]) {
///     MyTool()
/// }
/// ```
public enum GuardrailV3: @unchecked Sendable {
    /// Rejects input exceeding the character limit.
    case maxInput(Int)

    /// Rejects output exceeding the character limit.
    case maxOutput(Int)

    /// Rejects empty or whitespace-only input.
    case inputNotEmpty

    /// Custom input validation with a name and handler.
    case inputCustom(String, @Sendable (String) async throws -> GuardrailResult)

    /// Custom output validation with a name and handler.
    case outputCustom(String, @Sendable (String) async throws -> GuardrailResult)
}

// MARK: - Validation

extension GuardrailV3 {
    /// Runs this guardrail against the given text.
    ///
    /// - Parameter text: The input or output text to validate.
    /// - Returns: A `GuardrailResult` indicating pass or tripwire.
    public func validate(_ text: String) async throws -> GuardrailResult {
        switch self {
        case .maxInput(let limit):
            return text.count > limit
                ? .tripwire(message: "Input exceeds maximum length of \(limit)")
                : .passed()

        case .maxOutput(let limit):
            return text.count > limit
                ? .tripwire(message: "Output exceeds maximum length of \(limit)")
                : .passed()

        case .inputNotEmpty:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .tripwire(message: "Input cannot be empty")
                : .passed()

        case .inputCustom(_, let handler):
            return try await handler(text)

        case .outputCustom(_, let handler):
            return try await handler(text)
        }
    }

    /// The display name of this guardrail.
    public var name: String {
        switch self {
        case .maxInput(let limit): return "MaxInput(\(limit))"
        case .maxOutput(let limit): return "MaxOutput(\(limit))"
        case .inputNotEmpty: return "InputNotEmpty"
        case .inputCustom(let name, _): return name
        case .outputCustom(let name, _): return name
        }
    }
}
