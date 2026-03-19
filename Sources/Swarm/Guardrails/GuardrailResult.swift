// GuardrailResult.swift
// Swarm Framework
//
// Result type for guardrail validation checks.
// Indicates whether a tripwire was triggered and provides diagnostic information.

import Foundation

// MARK: - GuardrailResult

/// The result of a guardrail validation check.
///
/// `GuardrailResult` encapsulates the outcome of a guardrail check, indicating whether
/// validation passed or a tripwire was triggered. Use the static factory methods to create results:
///
/// | Method | Purpose | Tripwire Triggered |
/// |--------|---------|-------------------|
/// | ``passed(message:outputInfo:metadata:)`` | Validation succeeded | `false` |
/// | ``tripwire(message:outputInfo:metadata:)`` | Validation failed | `true` |
///
/// ## Creating Results
///
/// ### Passed Results
///
/// Use ``passed(message:outputInfo:metadata:)`` for successful validations:
///
/// ```swift
/// // Simple pass
/// return .passed()
///
/// // Pass with message
/// return .passed(message: "Input validation successful")
///
/// // Pass with diagnostic info
/// return .passed(
///     message: "Content approved",
///     outputInfo: .dictionary(["category": .string("safe")]),
///     metadata: ["tokensChecked": .int(42)]
/// )
/// ```
///
/// ### Tripwire Results
///
/// Use ``tripwire(message:outputInfo:metadata:)`` when validation fails:
///
/// ```swift
/// // Simple tripwire
/// return .tripwire(message: "Sensitive data detected")
///
/// // Tripwire with detailed info
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
/// ## Understanding Fields
///
/// ### `tripwireTriggered`
///
/// The primary indicator of validation result:
/// - `false`: Validation passed, processing continues
/// - `true`: Validation failed, ``GuardrailError`` is thrown
///
/// ### `message`
///
/// A human-readable description of the result. For tripwires, this becomes the
/// error message in ``GuardrailError``.
///
/// ### `outputInfo`
///
/// Structured diagnostic information about what was validated or what violation
/// was detected. This is typed as ``SendableValue`` for flexibility.
///
/// ```swift
/// // For PII detection
/// outputInfo: .dictionary([
///     "type": .string("EMAIL"),
///     "count": .int(2),
///     "positions": .array([.int(10), .int(50)])
/// ])
///
/// // For content classification
/// outputInfo: .dictionary([
///     "category": .string("safe"),
///     "confidence": .double(0.98)
/// ])
/// ```
///
/// ### `metadata`
///
/// Operational data about the guardrail execution itself:
///
/// ```swift
/// metadata: [
///     "executionTimeMs": .double(42.5),
///     "modelVersion": .string("v2.1"),
///     "cacheHit": .bool(true),
///     "tokensProcessed": .int(150)
/// ]
/// ```
///
/// ## Complete Example
///
/// ```swift
/// struct ContentModerationGuardrail: InputGuardrail {
///     let name = "ContentModeration"
///
///     func validate(_ input: String, context: AgentContext?) async -> GuardrailResult {
///         let startTime = Date()
///
///         // Perform moderation check
///         let result = await moderationService.check(input)
///
///         let executionTime = Date().timeIntervalSince(startTime) * 1000
///
///         if result.isFlagged {
///             return .tripwire(
///                 message: "Content violates usage policy",
///                 outputInfo: .dictionary([
///                     "categories": .array(result.categories.map { .string($0) }),
///                     "scores": .dictionary(result.scores.mapValues { .double($0) })
///                 ]),
///                 metadata: [
///                     "executionTimeMs": .double(executionTime),
///                     "model": .string("moderation-v1")
///                 ]
///             )
///         }
///
///         return .passed(
///             message: "Content is safe",
///             outputInfo: .dictionary(["safetyScore": .double(result.safetyScore)]),
///             metadata: [
///                 "executionTimeMs": .double(executionTime),
///                 "tokensChecked": .int(input.count)
///             ]
///         )
///     }
/// }
/// ```
///
/// ## Handling Results
///
/// When running guardrails directly:
///
/// ```swift
/// let guardrail = SensitiveDataGuardrail()
/// let result = try await guardrail.validate(userInput, context: context)
///
/// if result.tripwireTriggered {
///     print("Blocked: \(result.message ?? "Unknown reason")")
///     if let info = result.outputInfo {
///         print("Details: \(info)")
///     }
/// } else {
///     print("Passed: \(result.message ?? "OK")")
/// }
/// ```
///
/// - SeeAlso: ``InputGuardrail``, ``OutputGuardrail``, ``GuardrailError``
public struct GuardrailResult: Sendable, Equatable {
    /// Indicates whether a tripwire was triggered during the check.
    ///
    /// `true` if the guardrail blocked the input/output, `false` if it passed.
    /// This is the primary indicator of validation success or failure.
    public let tripwireTriggered: Bool

    /// Optional diagnostic information about what was detected or validated.
    ///
    /// Use this to provide structured data about the validation result:
    /// - For tripwires: Details about what triggered the violation (e.g., detected patterns, PII types)
    /// - For passes: Optional summary of what was checked
    ///
    /// The value is typed as ``SendableValue`` to support various data structures
    /// while maintaining `Sendable` conformance.
    ///
    /// Example:
    /// ```swift
    /// // For a PII detection tripwire
    /// outputInfo: .dictionary([
    ///     "violationType": .string("PII_DETECTED"),
    ///     "patterns": .array([.string("SSN"), .string("email")]),
    ///     "positions": .array([.int(10), .int(45)])
    /// ])
    ///
    /// // For a content classification pass
    /// outputInfo: .dictionary([
    ///     "category": .string("general"),
    ///     "confidence": .double(0.95)
    /// ])
    /// ```
    public let outputInfo: SendableValue?

    /// Optional human-readable message describing the result.
    ///
    /// For tripwire results, this message is included in the thrown ``GuardrailError``.
    /// For passed results, this can be used for logging or debugging.
    ///
    /// Example messages:
    /// - `"Input contains sensitive data"`
    /// - `"Content passed safety check"`
    /// - `"Output exceeds maximum length of 1000 characters"`
    public let message: String?

    /// Additional metadata about the guardrail execution.
    ///
    /// Use this for operational/diagnostic data about the guardrail execution itself:
    /// - Execution time
    /// - Model version used
    /// - Confidence scores
    /// - Cache hits
    /// - Tokens processed
    ///
    /// This metadata is useful for monitoring, debugging, and optimizing guardrail performance.
    ///
    /// Example:
    /// ```swift
    /// metadata: [
    ///     "executionTimeMs": .double(42.5),
    ///     "modelVersion": .string("v2.1"),
    ///     "cacheHit": .bool(true),
    ///     "tokensProcessed": .int(150)
    /// ]
    /// ```
    public let metadata: [String: SendableValue]

    // MARK: - Initializer

    /// Creates a guardrail result with all properties.
    ///
    /// Generally, you should use the static factory methods ``passed(message:outputInfo:metadata:)``
    /// or ``tripwire(message:outputInfo:metadata:)`` instead of this initializer.
    ///
    /// - Parameters:
    ///   - tripwireTriggered: Whether a tripwire was triggered.
    ///   - outputInfo: Optional diagnostic information.
    ///   - message: Optional descriptive message.
    ///   - metadata: Additional metadata about the check.
    public init(
        tripwireTriggered: Bool,
        outputInfo: SendableValue? = nil,
        message: String? = nil,
        metadata: [String: SendableValue] = [:]
    ) {
        self.tripwireTriggered = tripwireTriggered
        self.outputInfo = outputInfo
        self.message = message
        self.metadata = metadata
    }

    // MARK: - Factory Methods

    /// Creates a result indicating the check passed successfully.
    ///
    /// Use this method when validation succeeds and the input/output should be allowed.
    ///
    /// - Parameters:
    ///   - message: Optional message describing what passed. Example: `"Content is safe"`
    ///   - outputInfo: Optional diagnostic information about what was checked.
    ///   - metadata: Additional metadata about the check execution.
    /// - Returns: A result with `tripwireTriggered = false`.
    ///
    /// Example:
    /// ```swift
    /// return .passed()
    ///
    /// return .passed(message: "Validation successful")
    ///
    /// return .passed(
    ///     message: "No PII detected",
    ///     outputInfo: .dictionary(["scanType": .string("PII")]),
    ///     metadata: ["durationMs": .double(15.2)]
    /// )
    /// ```
    public static func passed(
        message: String? = nil,
        outputInfo: SendableValue? = nil,
        metadata: [String: SendableValue] = [:]
    ) -> GuardrailResult {
        GuardrailResult(
            tripwireTriggered: false,
            outputInfo: outputInfo,
            message: message,
            metadata: metadata
        )
    }

    /// Creates a result indicating a tripwire was triggered.
    ///
    /// Use this method when validation fails and the input/output should be blocked.
    /// The runner will convert this to a ``GuardrailError`` and throw it.
    ///
    /// - Parameters:
    ///   - message: **Required** description of why the tripwire was triggered.
    ///              This becomes the error message in ``GuardrailError``.
    ///   - outputInfo: Optional diagnostic information about the violation.
    ///   - metadata: Additional metadata about the check execution.
    /// - Returns: A result with `tripwireTriggered = true`.
    ///
    /// Example:
    /// ```swift
    /// return .tripwire(message: "Sensitive data detected")
    ///
    /// return .tripwire(
    ///     message: "PII detected in output",
    ///     outputInfo: .dictionary([
    ///         "type": .string("EMAIL"),
    ///         "value": .string("user@example.com")
    ///     ]),
    ///     metadata: ["detectionConfidence": .double(0.98)]
    /// )
    /// ```
    public static func tripwire(
        message: String,
        outputInfo: SendableValue? = nil,
        metadata: [String: SendableValue] = [:]
    ) -> GuardrailResult {
        GuardrailResult(
            tripwireTriggered: true,
            outputInfo: outputInfo,
            message: message,
            metadata: metadata
        )
    }
}

// MARK: CustomDebugStringConvertible

extension GuardrailResult: CustomDebugStringConvertible {
    public var debugDescription: String {
        var components: [String] = []

        components.append("GuardrailResult(")
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
