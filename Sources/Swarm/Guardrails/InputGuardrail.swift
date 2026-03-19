// InputGuardrail.swift
// Swarm Framework
//
// Input validation guardrails for agent systems.
// Provides validation and safety checks for agent inputs before processing.

import Foundation

/// Type alias for input validation handler closures.
///
/// Use this type alias when creating custom closure-based input validation.
/// The handler receives the input string and optional context, returning a ``GuardrailResult``.
///
/// - Parameters:
///   - String: The input string to validate
///   - AgentContext?: Optional context for validation decisions
/// - Returns: A ``GuardrailResult`` indicating pass or failure
/// - Throws: Validation errors if the check cannot be completed
///
/// Example:
/// ```swift
/// let handler: InputValidationHandler = { input, context in
///     let maxLength = await context?.get("maxLength")?.intValue ?? 1000
///     if input.count > maxLength {
///         return .tripwire(message: "Input too long")
///     }
///     return .passed()
/// }
/// ```
public typealias InputValidationHandler = @Sendable (String, AgentContext?) async throws -> GuardrailResult

// MARK: - InputGuardrail

/// Protocol for validating user input before agent processing.
///
/// `InputGuardrail` defines the contract for validating agent inputs before they are processed.
/// Input guardrails act as a security and quality layer, checking for:
///
/// - **Sensitive data**: PII, passwords, API keys
/// - **Malicious content**: Prompt injection, jailbreak attempts
/// - **Policy violations**: Profanity, inappropriate content
/// - **Format constraints**: Length limits, required patterns
/// - **Rate limiting**: Request throttling
///
/// ## Usage
///
/// Create a custom input guardrail by implementing the protocol:
///
/// ```swift
/// struct ProfanityGuardrail: InputGuardrail {
///     let name = "ProfanityGuardrail"
///
///     func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
///         let hasProfanity = checkForProfanity(input)
///         if hasProfanity {
///             return .tripwire(
///                 message: "Input contains inappropriate language",
///                 outputInfo: .dictionary(["violation": .string("PROFANITY_DETECTED")])
///             )
///         }
///         return .passed(message: "Content is clean")
///     }
///
///     private func checkForProfanity(_ text: String) -> Bool {
///         // Implementation
///         false
///     }
/// }
/// ```
///
/// Attach guardrails to an agent:
///
/// ```swift
/// let agent = Agent(
///     instructions: "You are a helpful assistant",
///     inputGuardrails: [
///         ProfanityGuardrail(),
///         InputGuard.maxLength(5000),
///         InputGuard.notEmpty()
///     ]
/// )
/// ```
///
/// ## Execution Flow
///
/// Input guardrails execute before the agent processes user input:
///
/// ```
/// User Input → Input Guardrails → (tripwire?) → Agent Processing
///                   ↓ yes
///         GuardrailError.inputTripwireTriggered
/// ```
///
/// ## Composing Guardrails
///
/// Multiple guardrails can be composed to create comprehensive validation:
///
/// ```swift
/// extension InputGuardrail where Self == InputGuard {
///     /// Combined validation pipeline
///     static func standardValidation(maxLength: Int = 5000) -> some InputGuardrail {
///         [
///             InputGuard.notEmpty(),
///             InputGuard.maxLength(maxLength),
///             InputGuard.custom("no_scripts") { input in
///                 input.contains("<script")
///                     ? .tripwire(message: "Scripts not allowed")
///                     : .passed()
///             }
///         ]
///     }
/// }
/// ```
///
/// ## Error Handling
///
/// When a guardrail detects a violation, it returns ``GuardrailResult/tripwire(message:outputInfo:metadata:)``.
/// The runner converts this to ``GuardrailError/inputTripwireTriggered(guardrailName:message:outputInfo:)``.
///
/// ```swift
/// do {
///     let result = try await swarm.run(agent, input: "user input")
/// } catch let error as GuardrailError {
///     switch error {
///     case .inputTripwireTriggered(let name, let message, let info):
///         print("Guardrail '\(name)' blocked input: \(message ?? "")")
///     default:
///         break
///     }
/// }
/// ```
///
/// - SeeAlso: ``InputGuard``, ``OutputGuardrail``, ``GuardrailResult``, ``GuardrailError``
public protocol InputGuardrail: Guardrail {
    /// Validates the input before agent processing.
    ///
    /// Implement this method to perform custom validation logic on user input.
    /// Return ``GuardrailResult/passed(message:outputInfo:metadata:)`` if validation succeeds,
    /// or ``GuardrailResult/tripwire(message:outputInfo:metadata:)`` if a violation is detected.
    ///
    /// - Parameters:
    ///   - input: The user's input string to validate
    ///   - context: Optional ``AgentContext`` for accessing shared state, configuration,
    ///              or making context-aware validation decisions
    /// - Returns: A ``GuardrailResult`` indicating whether validation passed or failed
    /// - Throws: Only throw errors for unexpected failures (network errors, database failures).
    ///           Do not throw for validation failures - use ``GuardrailResult/tripwire(message:outputInfo:metadata:)`` instead.
    func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - InputGuard

/// A lightweight, closure-based implementation of ``InputGuardrail``.
///
/// `InputGuard` provides a convenient way to create input guardrails without defining
/// a new struct. Use the static factory methods or initializers to create guards:
///
/// ## Creating Input Guards
///
/// ### Using Static Factories
///
/// ```swift
/// let agent = Agent(
///     instructions: "Assistant",
///     inputGuardrails: [
///         InputGuard.maxLength(5000),
///         InputGuard.notEmpty()
///     ]
/// )
/// ```
///
/// ### Using Closures
///
/// ```swift
/// // Simple closure (input only)
/// let simpleGuard = InputGuard("no_numbers") { input in
///     input.rangeOfCharacter(from: .decimalDigits) == nil
///         ? .passed()
///         : .tripwire(message: "Numbers not allowed")
/// }
///
/// // Context-aware closure
/// let contextGuard = InputGuard("rate_limited") { input, context in
///     let count = await context?.get("requestCount")?.intValue ?? 0
///     guard count < 100 else {
///         return .tripwire(message: "Rate limit exceeded")
///     }
///     await context?.set("requestCount", value: .int(count + 1))
///     return .passed()
/// }
/// ```
///
/// ## Protocol Extension Factory Methods
///
/// Use these methods when you need type inference for the protocol:
///
/// ```swift
/// func createGuardrails() -> [any InputGuardrail] {
///     [
///         .maxLength(1000),
///         .notEmpty(),
///         .custom("custom_validator") { input in
///             // Custom logic
///             .passed()
///         }
///     ]
/// }
/// ```
///
/// - SeeAlso: ``InputGuardrail``, ``OutputGuard``
public struct InputGuard: InputGuardrail, Sendable {
    /// The unique name identifying this guard.
    public let name: String

    /// Creates an input guard with a simple validation closure.
    ///
    /// Use this initializer when you don't need access to the agent context.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guard
    ///   - validate: Closure that receives input string and returns a ``GuardrailResult``
    ///
    /// Example:
    /// ```swift
    /// let guardrail = InputGuard("length_check") { input in
    ///     input.count <= 1000 ? .passed() : .tripwire(message: "Too long")
    /// }
    /// ```
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { input, _ in
            try await validate(input)
        }
    }

    /// Creates an input guard with a context-aware validation closure.
    ///
    /// Use this initializer when you need access to shared state or configuration
    /// through the ``AgentContext``.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guard
    ///   - validate: Closure that receives input string and optional context
    ///
    /// Example:
    /// ```swift
    /// let guardrail = InputGuard("rate_limit") { input, context in
    ///     let count = await context?.get("count")?.intValue ?? 0
    ///     if count > 100 {
    ///         return .tripwire(message: "Rate limit exceeded")
    ///     }
    ///     await context?.set("count", value: .int(count + 1))
    ///     return .passed()
    /// }
    /// ```
    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = validate
    }

    /// Validates input using the configured handler.
    ///
    /// - Parameters:
    ///   - input: The input string to validate
    ///   - context: Optional agent context
    /// - Returns: The ``GuardrailResult`` from the validation handler
    /// - Throws: Any error thrown by the validation handler
    public func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(input, context)
    }

    private let handler: InputValidationHandler
}

// MARK: - InputGuard Static Factories

public extension InputGuard {
    /// Creates a guardrail that enforces a maximum input length.
    ///
    /// This guardrail checks that the input string does not exceed the specified
    /// character count. Useful for preventing overly long inputs that could
    /// cause performance issues or exceed model token limits.
    ///
    /// - Parameters:
    ///   - maxLength: The maximum allowed character count
    ///   - name: Optional custom name (default: "MaxLengthGuardrail")
    /// - Returns: An ``InputGuard`` configured with length validation
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     inputGuardrails: [InputGuard.maxLength(500)]
    /// )
    ///
    /// // With custom name for logging
    /// let custom = InputGuard.maxLength(1000, name: "CustomMaxLength")
    /// ```
    ///
    /// The tripwire result includes metadata about the actual and allowed lengths:
    /// ```swift
    /// GuardrailResult.tripwire(
    ///     message: "Input exceeds maximum length of 500",
    ///     metadata: ["length": .int(750), "limit": .int(500)]
    /// )
    /// ```
    static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard {
        InputGuard(name) { input in
            if input.count > maxLength {
                return .tripwire(
                    message: "Input exceeds maximum length of \(maxLength)",
                    metadata: ["length": .int(input.count), "limit": .int(maxLength)]
                )
            }
            return .passed()
        }
    }

    /// Creates a guardrail that rejects empty or whitespace-only inputs.
    ///
    /// This guardrail trims whitespace and newlines before checking if the
    /// input is empty. Useful for ensuring users provide meaningful content.
    ///
    /// - Parameter name: Optional custom name (default: "NotEmptyGuardrail")
    /// - Returns: An ``InputGuard`` configured with non-empty validation
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     inputGuardrails: [
    ///         InputGuard.notEmpty(),
    ///         InputGuard.maxLength(5000)
    ///     ]
    /// )
    /// ```
    ///
    /// The following inputs would trigger the tripwire:
    /// - `""` (empty string)
    /// - `"   "` (whitespace only)
    /// - `"\n\t "` (newlines and tabs only)
    static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard {
        InputGuard(name) { input in
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .tripwire(message: "Input cannot be empty")
            }
            return .passed()
        }
    }

    /// Creates a custom input guardrail from a validation closure.
    ///
    /// Use this factory method when you need a one-off custom validation
    /// without defining a new type.
    ///
    /// - Parameters:
    ///   - name: The unique name for this guardrail
    ///   - validate: Closure that performs validation and returns a ``GuardrailResult``
    /// - Returns: An ``InputGuard`` configured with the custom validation
    ///
    /// Example:
    /// ```swift
    /// // Block input containing email addresses
    /// let noEmails = InputGuard.custom("no_emails") { input in
    ///     let emailPattern = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
    ///     let regex = try! NSRegularExpression(pattern: emailPattern, options: .caseInsensitive)
    ///     let range = NSRange(input.startIndex..., in: input)
    ///
    ///     if regex.firstMatch(in: input, options: [], range: range) != nil {
    ///         return .tripwire(message: "Email addresses not allowed in input")
    ///     }
    ///     return .passed()
    /// }
    ///
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     inputGuardrails: [noEmails]
    /// )
    /// ```
    static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> InputGuard {
        InputGuard(name, validate)
    }
}

// MARK: - Protocol Extension Factory Methods

extension InputGuardrail where Self == InputGuard {
    /// Creates a max-length input guardrail using protocol extension syntax.
    ///
    /// This allows convenient syntax when building arrays of `any InputGuardrail`:
    ///
    /// ```swift
    /// let guardrails: [any InputGuardrail] = [
    ///     .maxLength(5000),
    ///     .notEmpty()
    /// ]
    /// ```
    ///
    /// - Parameters:
    ///   - maxLength: The maximum allowed character count
    ///   - name: Optional custom name
    /// - Returns: An ``InputGuard`` configured with length validation
    public static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard {
        InputGuard.maxLength(maxLength, name: name)
    }

    /// Creates a not-empty input guardrail using protocol extension syntax.
    ///
    /// This allows convenient syntax when building arrays of `any InputGuardrail`:
    ///
    /// ```swift
    /// let guardrails: [any InputGuardrail] = [
    ///     .maxLength(5000),
    ///     .notEmpty()
    /// ]
    /// ```
    ///
    /// - Parameter name: Optional custom name
    /// - Returns: An ``InputGuard`` configured with non-empty validation
    public static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard {
        InputGuard.notEmpty(name: name)
    }

    /// Creates a custom input guardrail using protocol extension syntax.
    ///
    /// This allows convenient syntax when building arrays of `any InputGuardrail`:
    ///
    /// ```swift
    /// let guardrails: [any InputGuardrail] = [
    ///     .maxLength(5000),
    ///     .custom("no_scripts") { input in
    ///         input.contains("<script")
    ///             ? .tripwire(message: "Scripts not allowed")
    ///             : .passed()
    ///     }
    /// ]
    /// ```
    ///
    /// - Parameters:
    ///   - name: The unique name for this guardrail
    ///   - validate: Closure that performs validation
    /// - Returns: An ``InputGuard`` configured with the custom validation
    public static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> InputGuard {
        InputGuard.custom(name, validate)
    }
}
