// HandoffConfiguration.swift
// Swarm Framework
//
// Configuration types for enhanced agent handoffs with callbacks.

import Foundation

// MARK: - HandoffInputData

/// Data provided to handoff callbacks containing information about the handoff.
///
/// `HandoffInputData` encapsulates all the information available during a handoff,
/// including source and target agent names, the input being passed, any context
/// being transferred, and mutable metadata that can be modified by filters.
///
/// This type is passed to callbacks like `OnTransferCallback` and `TransformCallback`
/// to enable logging, validation, and transformation of handoff data.
///
/// Example:
/// ```swift
/// let inputData = HandoffInputData(
///     sourceAgentName: "planner",
///     targetAgentName: "executor",
///     input: "Execute step 1",
///     context: ["plan_id": .string("123")],
///     metadata: ["priority": .string("high")]
/// )
/// ```
public struct HandoffInputData: Sendable, Equatable {
    /// The name of the agent initiating the handoff.
    public let sourceAgentName: String

    /// The name of the agent receiving the handoff.
    public let targetAgentName: String

    /// The input being passed to the target agent.
    public let input: String

    /// Context being transferred with the handoff.
    ///
    /// This dictionary contains any contextual information that should be
    /// propagated from the source agent to the target agent.
    public let context: [String: SendableValue]

    /// Mutable metadata that can be modified by input filters.
    ///
    /// Unlike `context`, metadata can be modified by `TransformCallback`
    /// to add, remove, or update values during handoff processing.
    public var metadata: [String: SendableValue]

    // MARK: - Initialization

    /// Creates a new handoff input data instance.
    ///
    /// - Parameters:
    ///   - sourceAgentName: The agent initiating the handoff.
    ///   - targetAgentName: The agent receiving the handoff.
    ///   - input: The input for the target agent.
    ///   - context: Context to transfer. Default: [:]
    ///   - metadata: Mutable metadata. Default: [:]
    public init(
        sourceAgentName: String,
        targetAgentName: String,
        input: String,
        context: [String: SendableValue] = [:],
        metadata: [String: SendableValue] = [:]
    ) {
        self.sourceAgentName = sourceAgentName
        self.targetAgentName = targetAgentName
        self.input = input
        self.context = context
        self.metadata = metadata
    }
}

// MARK: CustomStringConvertible

extension HandoffInputData: CustomStringConvertible {
    public var description: String {
        """
        HandoffInputData(
            from: "\(sourceAgentName)",
            to: "\(targetAgentName)",
            input: "\(input.prefix(50))\(input.count > 50 ? "..." : "")"
        )
        """
    }
}

// MARK: - Callback Type Aliases

/// Callback invoked before a handoff is executed.
///
/// Use this callback to log, perform side effects, or update context before
/// a handoff occurs. The callback receives the shared `AgentContext`
/// and the `HandoffInputData` describing the handoff.
///
/// > Note: Errors thrown from this callback are logged but do **not** abort
/// > the handoff. For pre-handoff validation that should prevent execution,
/// > use `WhenCallback` instead, which returns `false` to skip handoffs.
///
/// Example:
/// ```swift
/// let onTransfer: OnTransferCallback = { context, inputData in
///     Log.agents.info("Handoff: \(inputData.sourceAgentName) -> \(inputData.targetAgentName)")
///
///     // Update context before handoff
///     await context.set("last_handoff", value: .string(inputData.targetAgentName))
/// }
/// ```
public typealias OnTransferCallback = @Sendable (AgentContext, HandoffInputData) async throws -> Void

/// Filter that transforms handoff input data before execution.
///
/// Use this filter to modify, augment, or transform the handoff data
/// before it is passed to the target agent. The filter receives the
/// original input data and returns the potentially modified version.
///
/// This callback is synchronous and cannot throw errors. For validation
/// that may fail, use `OnTransferCallback` instead.
///
/// Example:
/// ```swift
/// let transform: TransformCallback = { inputData in
///     var modified = inputData
///     modified.metadata["filtered_at"] = .double(Date().timeIntervalSince1970)
///     modified.metadata["original_source"] = .string(inputData.sourceAgentName)
///     return modified
/// }
/// ```
public typealias TransformCallback = @Sendable (HandoffInputData) -> HandoffInputData

/// Callback that determines if a handoff should be enabled.
///
/// Use this callback to dynamically enable or disable handoffs based on
/// the current context and target agent state. Return `false` to skip
/// this handoff option when presenting available handoffs to the user
    /// or when building tool schemas.
///
/// Example:
/// ```swift
/// let when: WhenCallback = { context, agent in
///     // Only enable handoff to executor when planning is complete
///     guard await context.get("planning_complete")?.boolValue == true else {
///         return false
///     }
///     return true
/// }
/// ```
public typealias WhenCallback = @Sendable (AgentContext, any AgentRuntime) async -> Bool

// MARK: - HandoffConfiguration

/// Configuration for an agent handoff with callbacks and filters.
///
/// `HandoffConfiguration` provides a rich configuration model for handoffs,
/// supporting:
/// - Custom tool naming and descriptions for the handoff
/// - Pre-handoff callbacks for logging and validation
/// - Input filters for data transformation
/// - Dynamic enablement based on context
/// - History nesting options
///
/// Use `AgentRuntime.asHandoff()` or `HandoffOptions` to construct
/// configurations, and `AnyHandoffConfiguration` to store them type-erased.
///
/// Example:
/// ```swift
/// let config = HandoffConfiguration(
///     targetAgent: executorAgent,
///     toolNameOverride: "execute_task",
///     toolDescription: "Execute the planned task",
///     onTransfer: { context, data in
///         Log.agents.info("Executing handoff to \(data.targetAgentName)")
///     },
///     transform: { data in
///         var modified = data
///         modified.metadata["timestamp"] = .double(Date().timeIntervalSince1970)
///         return modified
///     },
///     when: { context, _ in
///         await context.get("ready")?.boolValue ?? false
///     },
///     nestHandoffHistory: true
/// )
/// ```
public struct HandoffConfiguration<Target: AgentRuntime>: Sendable {
    /// The target agent to hand off to.
    public let targetAgent: Target

    /// Optional custom tool name for this handoff.
    ///
    /// When set, this overrides the default tool name generated from
    /// the target agent's type name. Use this to provide more descriptive
    /// or context-specific names for handoff tools.
    public let toolNameOverride: String?

    /// Optional description for the handoff tool.
    ///
    /// This description is used when generating tool schemas for
    /// the handoff, helping the model understand when to use this handoff.
    public let toolDescription: String?

    /// Callback invoked before handoff execution.
    ///
    /// This callback is called after the handoff is validated but before
    /// the target agent begins execution. Use it for logging, metrics,
    /// or final validation.
    public let onTransfer: OnTransferCallback?

    /// Filter to transform input data before handoff.
    ///
    /// This filter is applied after `onTransfer` but before the handoff
    /// is executed. Use it to modify metadata, transform inputs, or
    /// add computed values to the handoff data.
    public let transform: TransformCallback?

    /// Callback to determine if handoff is enabled.
    ///
    /// When set, this callback is invoked to check whether the handoff
    /// should be available. If it returns `false`, the handoff is skipped.
    public let when: WhenCallback?

    /// Whether to nest the handoff history in the target agent's context.
    ///
    /// When `true`, the source agent's conversation history is nested
    /// within the target agent's context, preserving the full chain
    /// of interactions. When `false`, only the direct input is passed.
    public let nestHandoffHistory: Bool

    // MARK: - Initialization

    /// Creates a new handoff configuration.
    ///
    /// - Parameters:
    ///   - targetAgent: The agent to hand off to.
    ///   - toolNameOverride: Custom tool name. Default: nil
    ///   - toolDescription: Tool description. Default: nil
    ///   - onTransfer: Pre-handoff callback. Default: nil
    ///   - transform: Input data filter. Default: nil
    ///   - when: Enablement check. Default: nil
    ///   - nestHandoffHistory: Whether to nest history. Default: false
    public init(
        targetAgent: Target,
        toolNameOverride: String? = nil,
        toolDescription: String? = nil,
        onTransfer: OnTransferCallback? = nil,
        transform: TransformCallback? = nil,
        when: WhenCallback? = nil,
        nestHandoffHistory: Bool = false
    ) {
        self.targetAgent = targetAgent
        self.toolNameOverride = toolNameOverride
        self.toolDescription = toolDescription
        self.onTransfer = onTransfer
        self.transform = transform
        self.when = when
        self.nestHandoffHistory = nestHandoffHistory
    }
}

// MARK: - HandoffConfiguration + Computed Properties

public extension HandoffConfiguration {
    /// The effective tool name for this handoff.
    ///
    /// Returns `toolNameOverride` if set, otherwise generates a name
    /// from the target agent's type using snake_case convention.
    var effectiveToolName: String {
        if let override = toolNameOverride {
            return override
        }
        // Generate from type name: "ExecutorAgent" -> "handoff_to_executor_agent"
        let typeName = String(describing: type(of: targetAgent))
        return "handoff_to_\(typeName.camelCaseToSnakeCase())"
    }

    /// The effective description for this handoff tool.
    ///
    /// Returns `toolDescription` if set, otherwise generates a default
    /// description based on the target agent's type.
    var effectiveToolDescription: String {
        if let description = toolDescription {
            return description
        }
        let typeName = String(describing: type(of: targetAgent))
        return "Hand off execution to \(typeName)"
    }
}

// MARK: - String Extension for Snake Case

extension String {
    /// Converts a camelCase or PascalCase string to snake_case.
    ///
    /// Example: "ExecutorAgent" -> "executor_agent"
    func camelCaseToSnakeCase() -> String {
        var result = ""
        for (index, character) in enumerated() {
            if character.isUppercase {
                if index > 0 {
                    result += "_"
                }
                result += character.lowercased()
            } else {
                result += String(character)
            }
        }
        return result
    }
}
