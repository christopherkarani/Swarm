// OutputGuardrail.swift
// Swarm Framework
//
// Protocol and implementations for validating agent output before returning to users.

import Foundation

/// Type alias for output validation handler closures.
///
/// Use this type alias when creating custom closure-based output validation.
/// The handler receives the output string, the producing agent, and optional context.
///
/// - Parameters:
///   - String: The agent's output text to validate
///   - AgentRuntime: The agent that produced this output
///   - AgentContext?: Optional context for validation decisions
/// - Returns: A ``GuardrailResult`` indicating pass or failure
/// - Throws: Validation errors if the check cannot be completed
///
/// Example:
/// ```swift
/// let handler: OutputValidationHandler = { output, agent, context in
///     let agentName = agent.configuration.name
///     // Perform validation based on agent configuration
///     return .passed()
/// }
/// ```
public typealias OutputValidationHandler = @Sendable (String, any AgentRuntime, AgentContext?) async throws -> GuardrailResult

// MARK: - OutputGuardrail

/// Protocol for validating agent output before returning to users.
///
/// `OutputGuardrail` enables validation and filtering of agent outputs to ensure they meet
/// safety, quality, or policy requirements. Output guardrails act as a final check before
/// the user sees the agent's response.
///
/// ## Common Use Cases
///
/// | Use Case | Example |
/// |----------|---------|
/// | Content filtering | Block profanity, hate speech |
/// | PII detection | Redact emails, phone numbers |
/// | Quality checks | Minimum length, coherence |
/// | Policy compliance | Tone enforcement, formatting |
/// | Safety | Prevent harmful instructions |
///
/// ## Usage
///
/// Create a custom output guardrail by implementing the protocol:
///
/// ```swift
/// struct PIIRedactionGuardrail: OutputGuardrail {
///     let name = "PIIRedactionGuardrail"
///
///     func validate(
///         _ output: String,
///         agent: any AgentRuntime,
///         context: AgentContext?
///     ) async throws -> GuardrailResult {
///         let emailPattern = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
///         let regex = try NSRegularExpression(pattern: emailPattern, options: .caseInsensitive)
///         let range = NSRange(output.startIndex..., in: output)
///
///         if regex.firstMatch(in: output, options: [], range: range) != nil {
///             return .tripwire(
///                 message: "PII detected in output",
///                 outputInfo: .dictionary(["type": .string("EMAIL")]),
///                 metadata: ["redacted": .bool(true)]
///             )
///         }
///         return .passed()
///     }
/// }
/// ```
///
/// Attach guardrails to an agent:
///
/// ```swift
/// let agent = Agent(
///     instructions: "You are a helpful assistant",
///     outputGuardrails: [
///         PIIRedactionGuardrail(),
///         OutputGuard.maxLength(10000)
///     ]
/// )
/// ```
///
/// ## Execution Flow
///
/// Output guardrails execute after the agent generates a response:
///
/// ```
/// User Input → Agent Processing → LLM Response → Output Guardrails → (tripwire?) → User
///                                                  ↓ yes
///                             GuardrailError.outputTripwireTriggered
/// ```
///
/// ## Accessing Agent Configuration
///
/// The `agent` parameter provides access to the agent's configuration,
/// allowing context-aware validation:
///
/// ```swift
/// struct AgentSpecificGuardrail: OutputGuardrail {
///     let name = "AgentSpecificGuardrail"
///
///     func validate(
///         _ output: String,
///         agent: any AgentRuntime,
///         context: AgentContext?
///     ) async throws -> GuardrailResult {
///         // Access agent configuration
///         let agentName = agent.configuration.name
///         let model = agent.configuration.model
///
///         // Different validation for different agents
///         if agentName == "child-friendly-assistant" {
///             if containsInappropriateContent(output) {
///                 return .tripwire(message: "Content not suitable for children")
///             }
///         }
///
///         return .passed()
///     }
/// }
/// ```
///
/// ## Error Handling
///
/// When a guardrail detects a violation, it returns ``GuardrailResult/tripwire(message:outputInfo:metadata:)``.
/// The runner converts this to ``GuardrailError/outputTripwireTriggered(guardrailName:agentName:message:outputInfo:)``.
///
/// ```swift
/// do {
///     let result = try await swarm.run(agent, input: "user input")
/// } catch let error as GuardrailError {
///     switch error {
///     case .outputTripwireTriggered(let name, let agentName, let message, _):
///         print("Guardrail '\(name)' blocked output from '\(agentName)': \(message ?? "")")
///     default:
///         break
///     }
/// }
/// ```
///
/// - SeeAlso: ``OutputGuard``, ``InputGuardrail``, ``GuardrailResult``, ``GuardrailError``
public protocol OutputGuardrail: Guardrail {
    /// Validates an agent's output before returning to the user.
    ///
    /// Implement this method to perform custom validation logic on agent output.
    /// Return ``GuardrailResult/passed(message:outputInfo:metadata:)`` if validation succeeds,
    /// or ``GuardrailResult/tripwire(message:outputInfo:metadata:)`` if a violation is detected.
    ///
    /// - Parameters:
    ///   - output: The output text from the agent to validate
    ///   - agent: The agent instance that produced this output. Use this to access
    ///            agent configuration and make context-aware validation decisions.
    ///   - context: Optional ``AgentContext`` for accessing shared state from the
    ///              orchestration session
    /// - Returns: A ``GuardrailResult`` indicating whether validation passed or failed
    /// - Throws: Only throw errors for unexpected failures (network errors, model failures).
    ///           Do not throw for validation failures - use ``GuardrailResult/tripwire(message:outputInfo:metadata:)`` instead.
    func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - OutputGuard

/// A lightweight, closure-based implementation of ``OutputGuardrail``.
///
/// `OutputGuard` provides a convenient way to create output guardrails without defining
/// a new struct. Use the static factory methods or initializers to create guards:
///
/// ## Creating Output Guards
///
/// ### Using Static Factories
///
/// ```swift
/// let agent = Agent(
///     instructions: "Assistant",
///     outputGuardrails: [
///         OutputGuard.maxLength(10000)
///     ]
/// )
/// ```
///
/// ### Using Closures
///
/// ```swift
/// // Minimal signature (output only)
/// let simpleGuard = OutputGuard("block_bad_words") { output in
///     output.contains("BAD") ? .tripwire(message: "blocked") : .passed()
/// }
///
/// // Context-aware
/// let strictGuard = OutputGuard("strict_mode") { output, context in
///     let enabled = await context?.get("strict")?.boolValue ?? false
///     return enabled && output.contains("forbidden")
///         ? .tripwire(message: "blocked")
///         : .passed()
/// }
///
/// // Full signature with agent access
/// let agentAwareGuard = OutputGuard("agent_check") { output, agent, context in
///     let maxLength = agent.configuration.name == "concise" ? 100 : 10000
///     return output.count <= maxLength ? .passed() : .tripwire(message: "Too long")
/// }
/// ```
///
/// ## Protocol Extension Factory Methods
///
/// Use these methods when you need type inference for the protocol:
///
/// ```swift
/// func createGuardrails() -> [any OutputGuardrail] {
///     [
///         .maxLength(10000),
///         .custom("pii_check") { output in
///             // Custom logic
///             .passed()
///         }
///     ]
/// }
/// ```
///
/// - SeeAlso: ``OutputGuardrail``, ``InputGuard``
public struct OutputGuard: OutputGuardrail, Sendable {
    /// The unique name identifying this guard.
    public let name: String

    /// Creates an output guard with a simple validation closure.
    ///
    /// Use this initializer when you only need to inspect the output text.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guard
    ///   - validate: Closure that receives output string and returns a ``GuardrailResult``
    ///
    /// Example:
    /// ```swift
    /// let guardrail = OutputGuard("profanity_check") { output in
    ///     output.contains("badword")
    ///         ? .tripwire(message: "Profanity detected")
    ///         : .passed()
    /// }
    /// ```
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { output, _, _ in
            try await validate(output)
        }
    }

    /// Creates an output guard with a context-aware validation closure.
    ///
    /// Use this initializer when you need access to shared state through
    /// the ``AgentContext``, but don't need access to the agent.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guard
    ///   - validate: Closure that receives output string and optional context
    ///
    /// Example:
    /// ```swift
    /// let guardrail = OutputGuard("rate_limited") { output, context in
    ///     let count = await context?.get("outputCount")?.intValue ?? 0
    ///     if count > 1000 {
    ///         return .tripwire(message: "Output limit exceeded")
    ///     }
    ///     await context?.set("outputCount", value: .int(count + 1))
    ///     return .passed()
    /// }
    /// ```
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { output, _, context in
            try await validate(output, context)
        }
    }

    /// Creates an output guard with full access to agent and context.
    ///
    /// Use this initializer when you need access to both the agent configuration
    /// and the shared context for validation decisions.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guard
    ///   - validate: Closure that receives output, agent, and optional context
    ///
    /// Example:
    /// ```swift
    /// let guardrail = OutputGuard("agent_specific") { output, agent, context in
    ///     let agentName = agent.configuration.name
    ///     // Validation based on agent
    ///     return .passed()
    /// }
    /// ```
    public init(
        _ name: String,
        _ validate: @escaping OutputValidationHandler
    ) {
        self.name = name
        handler = validate
    }

    /// Validates output using the configured handler.
    ///
    /// - Parameters:
    ///   - output: The output string to validate
    ///   - agent: The agent that produced the output
    ///   - context: Optional agent context
    /// - Returns: The ``GuardrailResult`` from the validation handler
    /// - Throws: Any error thrown by the validation handler
    public func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(output, agent, context)
    }

    private let handler: OutputValidationHandler
}

// MARK: - OutputGuard Static Factories

public extension OutputGuard {
    /// Creates a guardrail that enforces a maximum output length.
    ///
    /// This guardrail checks that the agent's output does not exceed the specified
    /// character count. Useful for preventing overly long responses that could
    /// overwhelm users or exceed display limits.
    ///
    /// - Parameters:
    ///   - maxLength: The maximum allowed character count
    ///   - name: Optional custom name (default: "MaxOutputLengthGuardrail")
    /// - Returns: An ``OutputGuard`` configured with length validation
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(
    ///     instructions: "Be concise",
    ///     outputGuardrails: [
    ///         OutputGuard.maxLength(2000),
    ///     ]
    /// )
    ///
    /// // For Twitter-style responses
    /// let twitterBot = Agent(
    ///     instructions: "Reply in 280 characters",
    ///     outputGuardrails: [
    ///         OutputGuard.maxLength(280, name: "TwitterLimit")
    ///     ]
    /// )
    /// ```
    ///
    /// The tripwire result includes metadata about the actual and allowed lengths.
    static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard {
        OutputGuard(name) { output in
            if output.count > maxLength {
                return .tripwire(
                    message: "Output exceeds maximum length of \(maxLength)",
                    metadata: ["length": .int(output.count), "limit": .int(maxLength)]
                )
            }
            return .passed()
        }
    }

    /// Creates a custom output guardrail from a validation closure.
    ///
    /// Use this factory method when you need a one-off custom validation
    /// without defining a new type.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guardrail
    ///   - validate: Closure that performs validation and returns a ``GuardrailResult``
    /// - Returns: An ``OutputGuard`` configured with the custom validation
    ///
    /// Example:
    /// ```swift
    /// // Block output containing phone numbers
    /// let noPhones = OutputGuard.custom("no_phone_numbers") { output in
    ///     let phonePattern = "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b"
    ///     let regex = try! NSRegularExpression(pattern: phonePattern)
    ///     let range = NSRange(output.startIndex..., in: output)
    ///
    ///     if regex.firstMatch(in: output, options: [], range: range) != nil {
    ///         return .tripwire(message: "Phone numbers detected in output")
    ///     }
    ///     return .passed()
    /// }
    ///
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     outputGuardrails: [noPhones]
    /// )
    /// ```
    static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> OutputGuard {
        OutputGuard(name, validate)
    }
}

// MARK: - Protocol Extension Factory Methods

extension OutputGuardrail where Self == OutputGuard {
    /// Creates a max-length output guardrail using protocol extension syntax.
    ///
    /// This allows convenient syntax when building arrays of `any OutputGuardrail`:
    ///
    /// ```swift
    /// let guardrails: [any OutputGuardrail] = [
    ///     .maxLength(10000),
    ///     .custom("pii_check") { output in
    ///         // Custom logic
    ///         .passed()
    ///     }
    /// ]
    /// ```
    ///
    /// - Parameters:
    ///   - maxLength: The maximum allowed character count
    ///   - name: Optional custom name
    /// - Returns: An ``OutputGuard`` configured with length validation
    public static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard {
        OutputGuard.maxLength(maxLength, name: name)
    }

    /// Creates a custom output guardrail using protocol extension syntax.
    ///
    /// This allows convenient syntax when building arrays of `any OutputGuardrail`:
    ///
    /// ```swift
    /// let guardrails: [any OutputGuardrail] = [
    ///     .maxLength(10000),
    ///     .custom("format_check") { output in
    ///         output.hasPrefix("{") ? .passed() : .tripwire(message: "Invalid format")
    ///     }
    /// ]
    /// ```
    ///
    /// - Parameters:
    ///   - name: The unique name for this guardrail
    ///   - validate: Closure that performs validation
    /// - Returns: An ``OutputGuard`` configured with the custom validation
    public static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> OutputGuard {
        OutputGuard.custom(name, validate)
    }
}
