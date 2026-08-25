// OwnedLoopSupport.swift
// Swarm Framework
//
// Handoff-interception support for provider-owned tool loops. Moved here
// from Agent.swift (W3-T2); behavior is unchanged.

import Foundation

/// A handoff tool invoked inside a provider-owned tool loop.
struct OwnedLoopHandoffRequest: Error, Sendable {
    let name: String
    let arguments: [String: SendableValue]
}

/// Backup if Apple's session remaps the typed handoff to cancellation.
final class OwnedLoopPendingHandoff: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (name: String, arguments: [String: SendableValue])?

    func store(name: String, arguments: [String: SendableValue]) {
        lock.lock()
        pending = (name, arguments)
        lock.unlock()
    }

    func take() -> (name: String, arguments: [String: SendableValue])? {
        lock.lock()
        defer { lock.unlock() }
        let value = pending
        pending = nil
        return value
    }
}
