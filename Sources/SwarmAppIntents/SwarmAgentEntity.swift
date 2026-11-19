// SwarmAgentEntity.swift
// SwarmAppIntents
//
// App Intents surface for agents registered in SwarmAgentDirectory.

#if canImport(AppIntents)
@_exported import AppIntents
// Generated intents spell `LocalizedStringResource` unqualified.
@_exported import Foundation

// MARK: - SwarmAgentEntity

/// An agent registered in ``SwarmAgentDirectory``, exposed to the system as an
/// `AppEntity`.
///
/// Siri, Shortcuts, and Spotlight can list, search, and pick these entities,
/// and ``AskSwarmAgentIntent`` takes one as its target.
public struct SwarmAgentEntity: AppEntity, Sendable {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Assistant")
    }

    public static var defaultQuery: SwarmAgentEntityQuery {
        SwarmAgentEntityQuery()
    }

    /// The directory identifier of the agent.
    public let id: String
    /// The agent's display name.
    public let name: String
    /// Optional one-line description.
    public let summary: String?

    public var displayRepresentation: DisplayRepresentation {
        if let summary {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    public init(id: String, name: String, summary: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
    }

    init(_ entry: SwarmAgentDirectory.Entry) {
        self.init(id: entry.id, name: entry.name, summary: entry.summary)
    }
}

// MARK: - SwarmAgentEntityQuery

/// Resolves ``SwarmAgentEntity`` values from ``SwarmAgentDirectory/shared``.
public struct SwarmAgentEntityQuery: EntityStringQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [SwarmAgentEntity] {
        SwarmAgentDirectory.shared.entries(ids: identifiers).map(SwarmAgentEntity.init)
    }

    public func entities(matching string: String) async throws -> [SwarmAgentEntity] {
        SwarmAgentDirectory.shared.entries(matching: string).map(SwarmAgentEntity.init)
    }

    public func suggestedEntities() async throws -> [SwarmAgentEntity] {
        SwarmAgentDirectory.shared.entries.map(SwarmAgentEntity.init)
    }
}

// MARK: - AskSwarmAgentIntent

/// Sends a request to any agent in ``SwarmAgentDirectory/shared``.
///
/// One intent covers every registered agent; Siri and Shortcuts let the user
/// pick which one. To make the system index it, include
/// ``SwarmAppIntentsPackage`` in your app's `AppIntentsPackage`.
public struct AskSwarmAgentIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask Assistant"
    public static let description = IntentDescription("Sends a request to one of the app's assistants.")

    @IntentParameter(title: "Assistant")
    public var agent: SwarmAgentEntity

    @IntentParameter(title: "Request")
    public var prompt: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let runtime = try await SwarmAgentDirectory.shared.makeAgent(id: agent.id)
        let output = try await SwarmIntentBridge.run(agent: runtime, prompt: prompt)
        return .result(value: output, dialog: "\(output)")
    }
}

// MARK: - SwarmAppIntentsPackage

/// Lets the system discover the intents and entities defined in this module.
///
/// Add it to your app's package list:
///
/// ```swift
/// struct MyAppIntents: AppIntentsPackage {
///     static var includedPackages: [any AppIntentsPackage.Type] {
///         [SwarmAppIntentsPackage.self]
///     }
/// }
/// ```
public struct SwarmAppIntentsPackage: AppIntentsPackage {}

// MARK: - Error presentation

extension SwarmIntentError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        "\(errorDescription ?? String(describing: self))"
    }
}
#endif
