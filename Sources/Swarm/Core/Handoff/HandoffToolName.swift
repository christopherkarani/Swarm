// HandoffToolName.swift
// Swarm Framework
//
// Single derivation site for LLM-facing handoff tool names.

import Foundation

// MARK: - HandoffToolName

/// The effective tool name used to advertise and dispatch a handoff.
///
/// Derived once from `toolNameOverride`, or from `"handoff_to_"` plus the
/// snake_case of `String(describing: type(of: target))` when no override is set.
/// ``HandoffConfiguration/effectiveToolName`` and
/// ``AnyHandoffConfiguration/effectiveToolName`` project this value.
package struct HandoffToolName: Hashable, Sendable {
    /// The LLM-facing tool name.
    package let rawValue: String

    /// Derives the effective handoff tool name for `target`.
    ///
    /// - Parameters:
    ///   - target: The handoff destination runtime.
    ///   - override: A custom tool name. When non-`nil`, it is used as-is.
    package init(derivedFrom target: any AgentRuntime, override: String?) {
        if let override {
            rawValue = override
            return
        }
        let typeName = String(describing: type(of: target))
        rawValue = "handoff_to_\(typeName.camelCaseToSnakeCase())"
    }
}

// MARK: - HandoffIdentity

/// Init-time uniqueness checks for handoff tool names.
package enum HandoffIdentity {
    /// Validates that handoff tool names are unique and do not collide with tools.
    ///
    /// - Parameters:
    ///   - handoffs: Configured handoffs whose effective names are checked.
    ///   - toolNames: Registered tool names, including disabled tools.
    /// - Throws: ``AgentError/duplicateHandoffToolName(name:)`` when two handoffs
    ///   share an effective name, or ``AgentError/handoffToolNameCollidesWithTool(name:)``
    ///   when an effective name equals a registered tool name.
    package static func validate(
        handoffs: [AnyHandoffConfiguration],
        toolNames: Set<String>
    ) throws {
        var seen: Set<String> = []
        for handoff in handoffs {
            let name = HandoffToolName(
                derivedFrom: handoff.targetAgent,
                override: handoff.toolNameOverride
            ).rawValue
            if !seen.insert(name).inserted {
                throw AgentError.duplicateHandoffToolName(name: name)
            }
            if toolNames.contains(name) {
                throw AgentError.handoffToolNameCollidesWithTool(name: name)
            }
        }
    }
}
