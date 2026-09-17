// HandoffContextFilter.swift
// Swarm Framework
//
// Reserved-prefix filter for handoff context injection.

import Foundation

// MARK: - HandoffContextFilter

/// Filters handoff request context so reserved identity keys cannot be injected.
///
/// Coordinator and in-loop dispatch share this filter. Matching is
/// case-insensitive prefix comparison against `auth`, `user_id`,
/// `authorization`, `session`, and `internal.`.
package enum HandoffContextFilter: Sendable {
    /// Keys that must not be copied from a handoff request into `AgentContext`.
    package static let reservedPrefixes = ["auth", "user_id", "authorization", "session", "internal."]

    /// Returns the subset of `context` whose keys do not match a reserved prefix.
    ///
    /// - Parameter context: Candidate handoff context values.
    /// - Returns: Values that are safe to merge into orchestration context.
    package static func allowedValues(_ context: [String: SendableValue]) -> [String: SendableValue] {
        var allowed: [String: SendableValue] = [:]
        allowed.reserveCapacity(context.count)
        for (key, value) in context {
            let lowerKey = key.lowercased()
            if reservedPrefixes.contains(where: { lowerKey.hasPrefix($0) }) {
                Log.agents.warning("Handoff context key '\(key)' blocked: matches reserved prefix")
                continue
            }
            allowed[key] = value
        }
        return allowed
    }
}
