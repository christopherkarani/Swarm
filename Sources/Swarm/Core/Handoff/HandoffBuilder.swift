// HandoffBuilder.swift
// Swarm Framework
//
// Type-erased handoff configuration storage.

import Foundation

// MARK: - AnyHandoffConfiguration

/// A type-erased wrapper for handoff configurations.
///
/// Use `AnyHandoffConfiguration` when you need to store heterogeneous
/// handoff configurations in a collection or pass them through APIs
/// that cannot work with generic types.
///
/// Example:
/// ```swift
/// let configurations: [AnyHandoffConfiguration] = [
///     AnyHandoffConfiguration(targetAgent: plannerAgent),
///     AnyHandoffConfiguration(targetAgent: executorAgent)
/// ]
/// ```
public struct AnyHandoffConfiguration: Sendable {
    /// The target agent (type-erased).
    public let targetAgent: any AgentRuntime

    /// Custom tool name for this handoff.
    public let toolNameOverride: String?

    /// Description for the handoff tool.
    public let toolDescription: String?

    /// Callback invoked before handoff execution.
    public let onTransfer: OnTransferCallback?

    /// Filter to transform input data before handoff.
    public let transform: TransformCallback?

    /// Callback to determine if handoff is enabled.
    public let when: WhenCallback?

    /// How source-agent conversation history is carried into the handoff.
    public let history: HandoffHistory

    /// Whether to nest handoff history.
    ///
    /// Derived from ``history``. Prefer ``history`` when configuring handoffs.
    public var nestHandoffHistory: Bool { history.nestsHistory }

    // MARK: - Initialization

    /// Creates a type-erased handoff configuration from a typed configuration.
    ///
    /// - Parameter configuration: The typed configuration to wrap.
    public init(_ configuration: HandoffConfiguration<some AgentRuntime>) {
        targetAgent = configuration.targetAgent
        toolNameOverride = configuration.toolNameOverride
        toolDescription = configuration.toolDescription
        onTransfer = configuration.onTransfer
        transform = configuration.transform
        when = configuration.when
        history = configuration.history
    }

    /// Creates a type-erased handoff configuration directly.
    ///
    /// - Parameters:
    ///   - targetAgent: The agent to hand off to.
    ///   - toolNameOverride: Custom tool name. Default: nil
    ///   - toolDescription: Tool description. Default: nil
    ///   - onTransfer: Pre-handoff callback. Default: nil
    ///   - transform: Input data filter. Default: nil
    ///   - when: Enablement check. Default: nil
    ///   - history: History strategy for the handoff. Default: `.none`
    public init(
        targetAgent: any AgentRuntime,
        toolNameOverride: String? = nil,
        toolDescription: String? = nil,
        onTransfer: OnTransferCallback? = nil,
        transform: TransformCallback? = nil,
        when: WhenCallback? = nil,
        history: HandoffHistory = .none
    ) {
        self.targetAgent = targetAgent
        self.toolNameOverride = toolNameOverride
        self.toolDescription = toolDescription
        self.onTransfer = onTransfer
        self.transform = transform
        self.when = when
        self.history = history
    }

    /// Creates a type-erased handoff configuration using a boolean history flag.
    ///
    /// - Parameter nestHandoffHistory: When `true`, maps to ``HandoffHistory/nested``; otherwise ``HandoffHistory/none``.
    @available(*, deprecated, message: "Use history: HandoffHistory instead")
    public init(
        targetAgent: any AgentRuntime,
        toolNameOverride: String? = nil,
        toolDescription: String? = nil,
        onTransfer: OnTransferCallback? = nil,
        transform: TransformCallback? = nil,
        when: WhenCallback? = nil,
        nestHandoffHistory: Bool
    ) {
        self.init(
            targetAgent: targetAgent,
            toolNameOverride: toolNameOverride,
            toolDescription: toolDescription,
            onTransfer: onTransfer,
            transform: transform,
            when: when,
            history: nestHandoffHistory ? .nested : .none
        )
    }
}

// MARK: - AnyHandoffConfiguration + Computed Properties

public extension AnyHandoffConfiguration {
    /// The effective tool name for this handoff.
    var effectiveToolName: String {
        if let override = toolNameOverride {
            return override
        }
        let typeName = String(describing: type(of: targetAgent))
        return "handoff_to_\(typeName.camelCaseToSnakeCase())"
    }

    /// The effective description for this handoff tool.
    var effectiveToolDescription: String {
        if let description = toolDescription {
            return description
        }
        let typeName = String(describing: type(of: targetAgent))
        return "Hand off execution to \(typeName)"
    }
}
