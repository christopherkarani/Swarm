// Agent+Memory.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

import Foundation

extension Agent {
    func persistNoSessionTurn(
        userMessage: MemoryMessage,
        transcriptMessages: [MemoryMessage],
        to memory: any Memory
    ) async {
        let messages = ([userMessage] + transcriptMessages).filter { message in
            message.role == .user || message.role == .assistant
        }

        for message in messages {
            await memory.add(message)
        }
    }

    /// Creates the package default memory for agents that do not pass one explicitly.
    ///
    /// With the Integrations trait: ContextCore+Wax ``DefaultAgentMemory``.
    /// Without Integrations (lean default): ``SlidingWindowMemory``.
    /// Prefer this over constructing integration types from macros or client code so
    /// trait gating stays inside the Swarm module.
    /// - Parameter waxStoreURL: Explicit location of the durable Wax store.
    ///   When `nil`, the store lands under the installed ephemeral root
    ///   (``SwarmDefaultStoreLocation/installEphemeralRoot(_:)``) when one is
    ///   present, and in the durable Application-Support location otherwise.
    public static func makeDefaultMemory(waxStoreURL: URL? = nil) throws -> any Memory {
        #if SWARM_INTEGRATIONS && canImport(ContextCore)
        let resolvedWaxStoreURL = waxStoreURL ?? SwarmDefaultStoreLocation.installedEphemeralRoot.map {
            WaxMemory.makeEphemeralStoreURL(under: $0)
        }
        guard let resolvedWaxStoreURL else {
            return try DefaultAgentMemory()
        }
        return try DefaultAgentMemory(configuration: DefaultAgentMemory.Configuration(
            waxStoreURL: resolvedWaxStoreURL
        ))
        #else
        // Lean builds, or Integrations on non-Apple (no ContextCore link).
        return SlidingWindowMemory()
        #endif
    }
}
