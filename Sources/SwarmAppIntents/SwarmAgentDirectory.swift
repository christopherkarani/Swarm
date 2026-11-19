// SwarmAgentDirectory.swift
// SwarmAppIntents
//
// Registry of agents exposed to Siri / Shortcuts as `SwarmAgentEntity` values.

import Foundation
import Synchronization

// MARK: - SwarmAgentDirectory

/// The agents your app exposes to Siri, Shortcuts, and Spotlight.
///
/// Register agents once at launch. Each registration becomes a
/// `SwarmAgentEntity` that the built-in `AskSwarmAgentIntent` can target, so
/// people can say things like "Ask Travel Planner in MyApp to find a hotel".
///
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         SwarmAgentDirectory.shared.register(
///             id: "travel",
///             name: "Travel Planner",
///             summary: "Plans trips with live weather"
///         ) {
///             try Agent("You plan weekend trips.") { WeatherTool() }
///         }
///     }
///     // ...
/// }
/// ```
///
/// Agents are created lazily from their factory each time an intent runs, so
/// registration is cheap and per-run state is never shared between requests.
public final class SwarmAgentDirectory: Sendable {
    /// A registered agent.
    public struct Entry: Sendable, Identifiable {
        /// Stable identifier persisted by Shortcuts. Don't change it between releases.
        public let id: String
        /// Name shown in Siri and Shortcuts.
        public let name: String
        /// Optional one-line description shown as a subtitle.
        public let summary: String?

        let makeAgent: @Sendable () async throws -> any AgentRuntime
    }

    /// The directory used by `SwarmAgentEntity` and `AskSwarmAgentIntent`.
    public static let shared = SwarmAgentDirectory()

    /// Creates an empty directory. Most apps use ``shared``.
    public init() {}

    /// Registers (or replaces) an agent built on demand by `makeAgent`.
    ///
    /// - Parameters:
    ///   - id: Stable identifier. Re-registering an existing `id` replaces it
    ///     in place, keeping its position.
    ///   - name: Display name shown to the user.
    ///   - summary: Optional subtitle.
    ///   - makeAgent: Builds a fresh agent for each request.
    public func register(
        id: String,
        name: String,
        summary: String? = nil,
        makeAgent: @escaping @Sendable () async throws -> any AgentRuntime
    ) {
        let entry = Entry(id: id, name: name, summary: summary, makeAgent: makeAgent)
        state.withLock { entries in
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
        }
    }

    /// Registers (or replaces) a ready-made agent value.
    ///
    /// Use this for value-type agents such as ``Agent``, which are cheap to
    /// copy and hold no per-run state.
    public func register(
        _ agent: some AgentRuntime,
        id: String,
        name: String,
        summary: String? = nil
    ) {
        register(id: id, name: name, summary: summary) { agent }
    }

    /// Removes the agent registered under `id`, if any.
    public func unregister(id: String) {
        state.withLock { entries in
            entries.removeAll { $0.id == id }
        }
    }

    /// All registered agents in registration order.
    public var entries: [Entry] {
        state.withLock { $0 }
    }

    /// The registered agents whose identifiers appear in `ids`, in `ids` order.
    public func entries(ids: [String]) -> [Entry] {
        let all = entries
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    /// Registered agents whose name or summary contains `text` (case- and
    /// diacritic-insensitive). An empty query matches everything.
    public func entries(matching text: String) -> [Entry] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.filter { entry in
            entry.name.range(of: query, options: options) != nil
                || entry.summary?.range(of: query, options: options) != nil
        }
    }

    /// Builds the agent registered under `id`.
    ///
    /// - Throws: ``SwarmIntentError/agentNotFound(id:)`` when nothing is
    ///   registered under `id`, or any error thrown by the factory.
    public func makeAgent(id: String) async throws -> any AgentRuntime {
        guard let entry = entries(ids: [id]).first else {
            throw SwarmIntentError.agentNotFound(id: id)
        }
        return try await entry.makeAgent()
    }

    private let state = Mutex<[Entry]>([])
}
