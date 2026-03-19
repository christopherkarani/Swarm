// Guardrail.swift
// Swarm Framework
//
// Shared guardrail marker protocol.

import Foundation

/// Base protocol for all guardrail types.
///
/// `Guardrail` is the foundation of the Swarm validation system, serving as a marker protocol
/// shared by input, output, and tool guardrails. It provides a common interface for
/// identifying and naming guardrails across the framework.
///
/// ## Guardrail Types
///
/// The Swarm framework provides four specialized guardrail protocols:
///
/// | Protocol | Purpose | Execution Point |
/// |----------|---------|-----------------|
/// | ``InputGuardrail`` | Validate user input | Before agent processing |
/// | ``OutputGuardrail`` | Validate agent output | After agent response |
/// | ``ToolInputGuardrail`` | Validate tool arguments | Before tool execution |
/// | ``ToolOutputGuardrail`` | Validate tool results | After tool execution |
///
/// ## Creating Custom Guardrails
///
/// Implement one of the specialized protocols and provide a stable name:
///
/// ```swift
/// struct SensitiveDataGuardrail: InputGuardrail {
///     let name = "SensitiveDataGuardrail"
///
///     func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
///         if input.contains("password") {
///             return .tripwire(message: "Sensitive data detected")
///         }
///         return .passed()
///     }
/// }
/// ```
///
/// ## Using Built-in Guardrails
///
/// Use ``InputGuard`` and ``OutputGuard`` for common validations:
///
/// ```swift
/// let agent = Agent(
///     instructions: "You are a helpful assistant",
///     inputGuardrails: [
///         InputGuard.maxLength(5000),
///         InputGuard.notEmpty()
///     ],
///     outputGuardrails: [
///         OutputGuard.maxLength(10000)
///     ]
/// )
/// ```
///
/// ## Composition
///
/// Guardrails are composable and can be chained to create validation pipelines:
///
/// ```swift
/// let validationPipeline: [any InputGuardrail] = [
///     InputGuard.notEmpty(),
///     InputGuard.maxLength(1000),
///     SensitiveDataGuardrail(),
///     RateLimitGuardrail(maxRequests: 10)
/// ]
/// ```
///
/// - SeeAlso: ``InputGuardrail``, ``OutputGuardrail``, ``ToolInputGuardrail``, ``ToolOutputGuardrail``,
///   ``InputGuard``, ``OutputGuard``, ``GuardrailResult``
public protocol Guardrail: Sendable {
    /// A stable name for identification, logging, and error reporting.
    ///
    /// The name should be unique within your application to identify the guardrail
    /// in logs, metrics, and error messages. Use descriptive names that indicate
    /// the guardrail's purpose:
    ///
    /// ```swift
    /// let name = "PIIDetectionGuardrail"      // Good
    /// let name = "MaxLength_1000"             // Good
    /// let name = "guardrail1"                 // Avoid - not descriptive
    /// ```
    var name: String { get }
}
