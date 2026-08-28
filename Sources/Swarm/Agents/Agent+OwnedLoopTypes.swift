// Agent+OwnedLoopTypes.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

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

    /// First-winner: a later concurrent provider callback cannot overwrite
    /// an already-captured handoff.
    func store(name: String, arguments: [String: SendableValue]) {
        lock.lock()
        if pending == nil {
            pending = (name, arguments)
        }
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
