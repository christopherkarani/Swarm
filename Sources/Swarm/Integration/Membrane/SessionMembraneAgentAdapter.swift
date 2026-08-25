#if SWARM_INTEGRATIONS && canImport(Membrane)
import Foundation
import Membrane
import MembraneCore

/// Swarm-side adapter over `Membrane.MembraneSession`.
///
/// Kept internal: callers use ``MembraneEnvironment/contextCoreSession(configuration:budget:recallStore:pointerStore:initialSnapshot:)``.
/// The session still receives budget, stores, and snapshot; those arguments are not decorative.
actor SessionMembraneAgentAdapter: MembraneAgentAdapter {
    private let session: Membrane.MembraneSession

    init(session: Membrane.MembraneSession) {
        self.session = session
    }

    func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile _: ContextProfile
    ) async throws -> MembranePlannedBoundary {
        let prepared = try await session.prepare(
            ContextRequest(
                basePrompt: prompt,
                userInput: prompt,
                tools: toolSchemas.map {
                    ToolManifest(name: $0.name, description: $0.description)
                }
            )
        )

        let selectedToolNames = Set(prepared.selectedToolNames)
        var selectedSchemas = toolSchemas.filter { selectedToolNames.contains($0.name) }
        if prepared.mode == "jit" {
            selectedSchemas.append(contentsOf: MembraneInternalTools.schemaSet())
        }

        return MembranePlannedBoundary(
            prompt: prepared.plan.prompt,
            toolSchemas: MembraneInternalTools.sortedSchemas(selectedSchemas),
            mode: prepared.mode
        )
    }

    func transformToolResult(
        toolName: String,
        output: String,
        profile _: ContextProfile = .balanced
    ) async throws -> MembraneToolResultBoundary {
        switch try await session.transformToolResult(toolName: toolName, output: output) {
        case let .inline(text):
            return MembraneToolResultBoundary(textForConversation: text)
        case let .pointer(pointer, replacementText):
            return MembraneToolResultBoundary(
                textForConversation: replacementText,
                pointerID: pointer.id
            )
        }
    }

    func handleInternalToolCall(
        name: String,
        arguments: [String: SendableValue]
    ) async throws -> String? {
        try await session.handleInternalToolCall(
            name: name,
            arguments: stringify(arguments: arguments)
        )
    }

    func restore(checkpointData: Data?) async throws {
        let snapshot = try checkpointData.map { try JSONDecoder().decode(ContextSnapshot.self, from: $0) }
        try await session.restore(snapshot: snapshot)
    }

    func snapshotCheckpointData() async throws -> Data? {
        guard let snapshot = try await session.snapshot() else {
            return nil
        }
        return try JSONEncoder().encode(snapshot)
    }

    private func stringify(arguments: [String: SendableValue]) -> [String: String] {
        arguments.mapValues { value in
            switch value {
            case let .string(string):
                return string
            case let .int(int):
                return String(int)
            case let .double(double):
                return String(double)
            case let .bool(bool):
                return String(bool)
            case let .array(array):
                return array.compactMap(\.stringValue).joined(separator: ",")
            case let .dictionary(dictionary):
                let pairs = dictionary.keys.sorted().compactMap { key -> String? in
                    guard let value = dictionary[key]?.stringValue else { return nil }
                    return "\(key)=\(value)"
                }
                return pairs.joined(separator: ",")
            case .null:
                return ""
            }
        }
    }
}

public extension MembraneEnvironment {
    /// Builds an enabled Membrane environment backed by `Membrane.MembraneSession`.
    ///
    /// `budget`, `recallStore`, `pointerStore`, and `initialSnapshot` are forwarded
    /// into that session. They change planning, pointerization, recall, and restore.
    static func contextCoreSession(
        configuration: MembraneFeatureConfiguration = .default,
        budget: MembraneCore.ContextBudget = MembraneCore.ContextBudget(
            totalTokens: 4096,
            profile: .foundationModels4K
        ),
        recallStore: (any MembraneCore.ContextRecallStore)? = nil,
        pointerStore: (any MembraneCore.PointerStore)? = nil,
        initialSnapshot: MembraneCore.ContextSnapshot? = nil
    ) -> MembraneEnvironment {
        let session = Membrane.MembraneSession(
            configuration: configuration.makeMembraneSessionConfiguration(),
            budget: budget,
            recallStore: recallStore,
            pointerStore: pointerStore,
            initialSnapshot: initialSnapshot
        )

        return MembraneEnvironment(
            isEnabled: true,
            configuration: configuration,
            adapter: SessionMembraneAgentAdapter(session: session)
        )
    }
}

extension MembraneFeatureConfiguration {
    /// Maps Swarm's public configuration onto Membrane's internal session type.
    func makeMembraneSessionConfiguration() -> Membrane.MembraneFeatureConfiguration {
        Membrane.MembraneFeatureConfiguration(
            jitMinToolCount: jitMinToolCount,
            defaultJITLoadCount: defaultJITLoadCount,
            pointerThresholdBytes: pointerThresholdBytes,
            pointerSummaryMaxChars: pointerSummaryMaxChars,
            runtimeFeatureFlags: runtimeFeatureFlags,
            runtimeModelAllowlist: runtimeModelAllowlist
        )
    }
}
#endif
