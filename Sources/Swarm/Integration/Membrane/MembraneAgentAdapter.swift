import Foundation

#if SWARM_MEMBRANE
@_exported import Membrane
@_exported import MembraneCore
@_exported import MembraneHive

public typealias MembraneContextSnapshot = ContextSnapshot
#else
public struct MembraneFeatureConfiguration: Sendable, Equatable {
    public static let `default` = MembraneFeatureConfiguration()

    public var jitMinToolCount: Int
    public var defaultJITLoadCount: Int
    public var pointerThresholdBytes: Int
    public var pointerSummaryMaxChars: Int
    public var runtimeFeatureFlags: [String: Bool]
    public var runtimeModelAllowlist: [String]

    public init(
        jitMinToolCount: Int = 12,
        defaultJITLoadCount: Int = 6,
        pointerThresholdBytes: Int = 1024,
        pointerSummaryMaxChars: Int = 240,
        runtimeFeatureFlags: [String: Bool] = [:],
        runtimeModelAllowlist: [String] = []
    ) {
        self.jitMinToolCount = max(1, jitMinToolCount)
        self.defaultJITLoadCount = max(1, defaultJITLoadCount)
        self.pointerThresholdBytes = max(1, pointerThresholdBytes)
        self.pointerSummaryMaxChars = max(0, pointerSummaryMaxChars)
        self.runtimeFeatureFlags = runtimeFeatureFlags
        self.runtimeModelAllowlist = runtimeModelAllowlist.sorted()
    }
}

public struct MembraneContextSnapshot: Sendable, Equatable, Codable {
    public init() {}
}
#endif

public struct MembraneEnvironment: Sendable {
    public var isEnabled: Bool
    public var configuration: MembraneFeatureConfiguration

    #if SWARM_MEMBRANE
    public var session: MembraneSession?
    public var budget: ContextBudget?
    #endif

    #if SWARM_MEMBRANE
    public init(
        isEnabled: Bool = true,
        configuration: MembraneFeatureConfiguration = .default,
        session: MembraneSession? = nil,
        budget: ContextBudget? = nil
    ) {
        self.isEnabled = isEnabled
        self.configuration = configuration
        self.session = session
        self.budget = budget
    }
    #else
    public init(
        isEnabled: Bool = true,
        configuration: MembraneFeatureConfiguration = .default
    ) {
        self.isEnabled = isEnabled
        self.configuration = configuration
    }
    #endif

    public static let disabled = MembraneEnvironment(isEnabled: false)
    public static let enabled = MembraneEnvironment(isEnabled: true)
}

struct SwarmMembranePlannedBoundary: Sendable {
    let prompt: String
    let systemPrompt: String
    let toolSchemas: [ToolSchema]
    let mode: String
}

struct SwarmMembraneToolResultBoundary: Sendable {
    let textForConversation: String
    let pointerID: String?
}

protocol SwarmMembraneBridge: Sendable {
    func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile: ContextProfile,
        turnInput: String,
        conversationHistory: [String]
    ) async throws -> SwarmMembranePlannedBoundary

    func transformToolResult(
        toolName: String,
        output: String
    ) async throws -> SwarmMembraneToolResultBoundary

    func handleInternalToolCall(
        name: String,
        arguments: [String: SendableValue]
    ) async throws -> String?
}

#if SWARM_MEMBRANE
actor DefaultSwarmMembraneBridge: SwarmMembraneBridge {
    private let session: MembraneSession
    private let profile: ContextProfile

    init(session: MembraneSession, profile: ContextProfile) {
        self.session = session
        self.profile = profile
    }

    func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile _: ContextProfile,
        turnInput: String,
        conversationHistory: [String]
    ) async throws -> SwarmMembranePlannedBoundary {
        let prepared = try await session.prepare(
            ContextRequest(
                systemPrompt: conversationHistory.first ?? "",
                basePrompt: prompt,
                userInput: turnInput,
                tools: toolSchemas.map { ToolManifest(name: $0.name, description: $0.description) },
                history: conversationHistory.map { line in
                    ContextSlice(
                        content: line,
                        tokenCount: max(1, line.count / 4),
                        importance: 1.0,
                        source: .history,
                        tier: .full,
                        timestamp: .now
                    )
                },
                metadata: ContextMetadata(
                    turnNumber: conversationHistory.filter { $0.hasPrefix("[User]:") }.count,
                    sessionID: UUID().uuidString,
                    modelProfile: profile.preset == .strict4k ? .foundationModels4K : .mlxLocal8K
                ),
                recallQuery: turnInput,
                recallLimit: profile.maxRetrievedItems
            )
        )

        let selectedNames = Set(prepared.selectedToolNames)
        let selectedSchemas = toolSchemas.filter { selectedNames.contains($0.name) }

        return SwarmMembranePlannedBoundary(
            prompt: prepared.plan.prompt,
            systemPrompt: prepared.plan.systemPrompt,
            toolSchemas: MembraneInternalTools.sortedSchemas(selectedSchemas + MembraneInternalTools.schemaSet()),
            mode: prepared.mode
        )
    }

    func transformToolResult(
        toolName: String,
        output: String
    ) async throws -> SwarmMembraneToolResultBoundary {
        switch try await session.transformToolResult(toolName: toolName, output: output) {
        case let .inline(text):
            return SwarmMembraneToolResultBoundary(textForConversation: text, pointerID: nil)
        case let .pointer(pointer, replacementText):
            return SwarmMembraneToolResultBoundary(textForConversation: replacementText, pointerID: pointer.id)
        }
    }

    func handleInternalToolCall(
        name: String,
        arguments: [String: SendableValue]
    ) async throws -> String? {
        try await session.handleInternalToolCall(
            name: name,
            arguments: arguments.reduce(into: [String: String]()) { partial, entry in
                if let stringValue = Self.stringValue(from: entry.value) {
                    partial[entry.key] = stringValue
                }
            }
        )
    }

    private static func stringValue(from value: SendableValue) -> String? {
        switch value {
        case let .string(string):
            return string
        case let .array(items):
            let flattened = items.compactMap { stringValue(from: $0) }
            return flattened.isEmpty ? nil : flattened.joined(separator: ",")
        default:
            return value.stringValue
        }
    }
}
#endif
