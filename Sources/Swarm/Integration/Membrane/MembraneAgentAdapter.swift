import Foundation
#if SWARM_INTEGRATIONS
import Membrane
#endif

public struct MembraneFeatureConfiguration: Sendable, Equatable {
    public static let `default` = MembraneFeatureConfiguration()

    public var jitMinToolCount: Int
    public var defaultJITLoadCount: Int
    public var pointerThresholdBytes: Int
    public var pointerSummaryMaxChars: Int
    /// Optional provider-runtime feature policy flags keyed by namespaced identifier.
    ///
    /// Example keys:
    /// - `conduit.runtime.kv_quantization`
    /// - `conduit.runtime.attention_sinks`
    public var runtimeFeatureFlags: [String: Bool]
    /// Optional provider model allowlist used by runtime feature policy.
    public var runtimeModelAllowlist: [String]

    public init(
        jitMinToolCount: Int = 12,
        defaultJITLoadCount: Int = 6,
        pointerThresholdBytes: Int = 400,
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

public struct MembraneEnvironment: Sendable {
    public var isEnabled: Bool
    public var configuration: MembraneFeatureConfiguration
    public var adapter: (any MembraneAgentAdapter)?

    public init(
        isEnabled: Bool = true,
        configuration: MembraneFeatureConfiguration = .default,
        adapter: (any MembraneAgentAdapter)? = nil
    ) {
        self.isEnabled = isEnabled
        self.configuration = configuration
        self.adapter = adapter
    }

    public static let disabled = MembraneEnvironment(isEnabled: false)
    public static let enabled = MembraneEnvironment(isEnabled: true)
}

public struct MembranePlannedBoundary: Sendable {
    public let prompt: String
    public let toolSchemas: [ToolSchema]
    public let mode: String

    public init(prompt: String, toolSchemas: [ToolSchema], mode: String) {
        self.prompt = prompt
        self.toolSchemas = toolSchemas
        self.mode = mode
    }
}

public struct MembraneToolResultBoundary: Sendable {
    public let textForConversation: String
    public let pointerID: String?

    public init(textForConversation: String, pointerID: String? = nil) {
        self.textForConversation = textForConversation
        self.pointerID = pointerID
    }
}

public enum MembraneAgentAdapterError: Error, Sendable, Equatable {
    case unsupportedInternalTool(name: String)
    case invalidInternalToolArguments(name: String, reason: String)
}

public protocol MembraneAgentAdapter: Sendable {
    func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile: ContextProfile
    ) async throws -> MembranePlannedBoundary

    func transformToolResult(
        toolName: String,
        output: String,
        profile: ContextProfile
    ) async throws -> MembraneToolResultBoundary

    func handleInternalToolCall(
        name: String,
        arguments: [String: SendableValue]
    ) async throws -> String?

    func restore(checkpointData: Data?) async throws
    func snapshotCheckpointData() async throws -> Data?
}

#if SWARM_INTEGRATIONS
public actor DefaultMembraneAgentAdapter: MembraneAgentAdapter {
    public init(configuration: MembraneFeatureConfiguration = .default) {
        self.configuration = configuration

        let store = InMemoryPointerStore()
        pointerStore = store
        pointerResolver = PointerResolver(
            store: store,
            config: PointerResolverConfig(
                pointerThresholdBytes: configuration.pointerThresholdBytes,
                summaryMaxChars: configuration.pointerSummaryMaxChars
            )
        )
        toolPlan = .allowAll

        // TODO: Restore when MembraneHive ships MembraneCheckpointAdapter
        // #if canImport(MembraneHive)
        // checkpointAdapter = MembraneCheckpointAdapter()
        // #endif
    }

    public func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile: ContextProfile
    ) async throws -> MembranePlannedBoundary {
        let sortedSchemas = MembraneInternalTools.sortedSchemas(toolSchemas)
        var selectedSchemas = sortedSchemas
        var mode = "allowAll"

        let manifests = sortedSchemas.map { ToolManifest(name: $0.name, description: $0.description) }

        // For small-context providers (strict4k), enter JIT with fewer tools to save prompt tokens.
        let effectiveMinTools = profile.preset == .strict4k ? min(4, configuration.jitMinToolCount) : configuration.jitMinToolCount
        let jitLoader = JITToolLoader(jitMinToolCount: effectiveMinTools)
        var nextPlan: ToolPlan
        nextPlan = jitLoader.plan(tools: manifests, existingPlan: toolPlan)

        switch nextPlan {
        case .allowAll:
            mode = "allowAll"
            allowListToolNames = []

        case let .allowList(toolNames):
            mode = "allowList"
            let allowSet = Set(toolNames)
            allowListToolNames = Array(allowSet).sorted()
            selectedSchemas = sortedSchemas.filter { (schema: ToolSchema) in allowSet.contains(schema.name) }

        case let .jit(index, _):
            mode = "jit"

            var loadedSet = Set(loadedToolNames)
            if loadedSet.isEmpty {
                let loadCount = profile.preset == .strict4k ? min(2, configuration.defaultJITLoadCount) : configuration.defaultJITLoadCount
                let defaults = index.map(\.name).sorted().prefix(loadCount)
                loadedSet.formUnion(defaults)
            }
            loadedToolNames = Array(loadedSet).sorted()

            nextPlan = ToolPlan.jit(normalized: index, loaded: loadedToolNames)
            let loadedNames = Set(loadedToolNames)
            selectedSchemas = sortedSchemas.filter { loadedNames.contains($0.name) }
            selectedSchemas.append(contentsOf: MembraneInternalTools.schemaSet())
            selectedSchemas = MembraneInternalTools.sortedSchemas(selectedSchemas)
        }

        toolPlan = nextPlan

        let distilledPrompt = await distillPromptIfNeeded(
            prompt: prompt,
            profile: profile,
            toolCount: toolSchemas.count
        )

        try await syncCheckpointState(totalTokens: profile.budget.maxInputTokens)
        return MembranePlannedBoundary(
            prompt: distilledPrompt,
            toolSchemas: MembraneInternalTools.sortedSchemas(selectedSchemas),
            mode: mode
        )
    }

    public func transformToolResult(
        toolName: String,
        output: String,
        profile: ContextProfile = .balanced
    ) async throws -> MembraneToolResultBoundary {
        usageCounts[toolName, default: 0] += 1

        // For strict4k, force pointerization at 100 bytes instead of the default threshold.
        let effectiveThreshold = profile.preset == .strict4k ? 100 : configuration.pointerThresholdBytes
        let effectiveConfig = PointerResolverConfig(
            pointerThresholdBytes: effectiveThreshold,
            summaryMaxChars: profile.preset == .strict4k ? 120 : configuration.pointerSummaryMaxChars
        )
        let resolver = PointerResolver(store: pointerStore, config: effectiveConfig)
        let decision = try await resolver.pointerizeIfNeeded(toolName: toolName, output: output)
        switch decision {
        case let .inline(text):
            try await syncCheckpointState()
            return MembraneToolResultBoundary(textForConversation: text)

        case let .pointer(pointer, replacementText):
            pointerIDs.append(pointer.id)
            pointerIDs = Array(Set(pointerIDs)).sorted()
            try await syncCheckpointState()
            return MembraneToolResultBoundary(
                textForConversation: replacementText,
                pointerID: pointer.id
            )
        }
    }

    public func handleInternalToolCall(
        name: String,
        arguments: [String: SendableValue]
    ) async throws -> String? {
        guard MembraneInternalTools.isInternalTool(name) else {
            return nil
        }

        switch name {
        case MembraneInternalToolName.loadToolSchema:
            guard let toolName = arguments["tool_name"]?.stringValue, !toolName.isEmpty else {
                throw MembraneAgentAdapterError.invalidInternalToolArguments(
                    name: name,
                    reason: "Missing required string argument: tool_name"
                )
            }

            loadedToolNames.append(toolName)
            loadedToolNames = Array(Set(loadedToolNames)).sorted()
            try await syncCheckpointState()
            return "Loaded tool schema: \(toolName)"

        case MembraneInternalToolName.addTools:
            let names = parseToolNames(arguments["tool_names"])
            guard !names.isEmpty else {
                throw MembraneAgentAdapterError.invalidInternalToolArguments(
                    name: name,
                    reason: "Missing required array argument: tool_names"
                )
            }
            loadedToolNames = Array(Set(loadedToolNames + names)).sorted()
            try await syncCheckpointState()
            return "Added tools: \(names.sorted().joined(separator: ", "))"

        case MembraneInternalToolName.removeTools:
            let names = parseToolNames(arguments["tool_names"])
            guard !names.isEmpty else {
                throw MembraneAgentAdapterError.invalidInternalToolArguments(
                    name: name,
                    reason: "Missing required array argument: tool_names"
                )
            }
            let removals = Set(names)
            loadedToolNames.removeAll { removals.contains($0) }
            loadedToolNames.sort()
            try await syncCheckpointState()
            return "Removed tools: \(names.sorted().joined(separator: ", "))"

        case MembraneInternalToolName.resolvePointer:
            guard let pointerID = arguments["pointer_id"]?.stringValue, !pointerID.isEmpty else {
                throw MembraneAgentAdapterError.invalidInternalToolArguments(
                    name: name,
                    reason: "Missing required string argument: pointer_id"
                )
            }

            let payload = try await pointerStore.resolve(pointerID: pointerID)
            if let text = String(data: payload, encoding: .utf8) {
                return text
            }
            return payload.base64EncodedString()

        default:
            throw MembraneAgentAdapterError.unsupportedInternalTool(name: name)
        }
    }

    public func restore(checkpointData: Data?) async throws {
        guard let checkpointData else {
            loadedToolNames = []
            allowListToolNames = []
            pointerIDs = []
            usageCounts = [:]
            return
        }

        let state = try JSONDecoder().decode(CheckpointState.self, from: checkpointData)
        loadedToolNames = state.loadedToolNames
        allowListToolNames = state.allowListToolNames
        pointerIDs = state.pointerIDs
        usageCounts = state.usageCounts
    }

    public func snapshotCheckpointData() async throws -> Data? {
        let state = CheckpointState(
            loadedToolNames: loadedToolNames,
            allowListToolNames: allowListToolNames,
            pointerIDs: pointerIDs,
            usageCounts: usageCounts
        )
        return try JSONEncoder().encode(state)
    }

    private let configuration: MembraneFeatureConfiguration
    private var loadedToolNames: [String] = []
    private var allowListToolNames: [String] = []
    private var pointerIDs: [String] = []
    private var usageCounts: [String: Int] = [:]

    private let pointerStore: InMemoryPointerStore
    private let pointerResolver: PointerResolver
    private var toolPlan: ToolPlan

    // TODO: Restore when MembraneHive ships MembraneCheckpointAdapter
    // #if canImport(MembraneHive)
    // private let checkpointAdapter: MembraneCheckpointAdapter
    // #endif

    private func parseToolNames(_ value: SendableValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case let .array(elements):
            return elements.compactMap(\.stringValue).filter { !$0.isEmpty }
        case let .string(raw):
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private func distillPromptIfNeeded(
        prompt: String,
        profile: ContextProfile,
        toolCount: Int
    ) async -> String {
        guard profile.preset == .strict4k, toolCount >= configuration.jitMinToolCount else {
            return prompt
        }

        let counter = PromptTokenBudgeting.counter()
        let maxTokens = profile.budget.maxInputTokens
        guard await PromptTokenBudgeting.countTokens(in: prompt, using: counter) > maxTokens else {
            return prompt
        }

        let marker = "\n\n[Membrane distilled context]\n\n"
        let markerTokens = await PromptTokenBudgeting.countTokens(in: marker, using: counter)
        if maxTokens <= markerTokens + 16 {
            return await PromptTokenBudgeting.prefix(prompt, maxTokens: maxTokens, using: counter)
        }

        let tailTokens = max(16, maxTokens / 3)
        let headTokens = max(16, maxTokens - markerTokens - tailTokens)
        let head = await PromptTokenBudgeting.prefix(prompt, maxTokens: headTokens, using: counter)
        let tail = await PromptTokenBudgeting.suffix(prompt, maxTokens: tailTokens, using: counter)

        var compacted = head + marker + tail
        if await PromptTokenBudgeting.countTokens(in: compacted, using: counter) > maxTokens {
            let overflow = await PromptTokenBudgeting.countTokens(in: compacted, using: counter) - maxTokens
            let adjustedTail = max(0, tailTokens - overflow)
            let adjustedSuffix = await PromptTokenBudgeting.suffix(
                prompt,
                maxTokens: adjustedTail,
                using: counter
            )
            compacted = head + marker + adjustedSuffix
        }

        if await PromptTokenBudgeting.countTokens(in: compacted, using: counter) <= maxTokens {
            return compacted
        }

        let adjustedHead = max(0, maxTokens - markerTokens)
        return await PromptTokenBudgeting.prefix(prompt, maxTokens: adjustedHead, using: counter) + marker
    }

    private func syncCheckpointState(totalTokens _: Int = 4_096) async throws {
        _ = try await snapshotCheckpointData()
    }

    private struct CheckpointState: Codable, Sendable {
        let loadedToolNames: [String]
        let allowListToolNames: [String]
        let pointerIDs: [String]
        let usageCounts: [String: Int]
    }
}
#else
public actor DefaultMembraneAgentAdapter: MembraneAgentAdapter {
    public init(configuration _: MembraneFeatureConfiguration = .default) {}

    public func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile _: ContextProfile
    ) async throws -> MembranePlannedBoundary {
        MembranePlannedBoundary(prompt: prompt, toolSchemas: toolSchemas, mode: "disabled")
    }

    public func transformToolResult(
        toolName _: String,
        output: String,
        profile _: ContextProfile = .balanced
    ) async throws -> MembraneToolResultBoundary {
        MembraneToolResultBoundary(textForConversation: output)
    }

    public func handleInternalToolCall(
        name _: String,
        arguments _: [String: SendableValue]
    ) async throws -> String? {
        nil
    }

    public func restore(checkpointData _: Data?) async throws {}

    public func snapshotCheckpointData() async throws -> Data? {
        nil
    }
}
#endif
