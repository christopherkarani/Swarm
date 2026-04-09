import Foundation
import Membrane
import MembraneCore

public actor SessionMembraneAgentAdapter: StructuredMembranePlanningAdapter {
    private let session: Membrane.MembraneSession

    public init(session: Membrane.MembraneSession) {
        self.session = session
    }

    public func plan(
        prompt: String,
        toolSchemas: [ToolSchema],
        profile: ContextProfile
    ) async throws -> MembranePlannedBoundary {
        try await plan(
            request: MembranePlanningRequest(
                prompt: prompt,
                basePrompt: prompt,
                userInput: prompt
            ),
            toolSchemas: toolSchemas,
            profile: profile
        )
    }

    public func plan(
        request: MembranePlanningRequest,
        toolSchemas: [ToolSchema],
        profile: ContextProfile
    ) async throws -> MembranePlannedBoundary {
        let prepared = try await session.prepare(
            ContextRequest(
                systemPrompt: request.systemPrompt,
                basePrompt: request.basePrompt.isEmpty ? request.prompt : request.basePrompt,
                userInput: request.userInput,
                tools: toolSchemas.map {
                    ToolManifest(name: $0.name, description: $0.description)
                },
                history: request.history.map(makeContextSlice(from:)),
                memories: request.memories.map(makeContextSlice(from:)),
                retrieval: request.retrieval.map(makeContextSlice(from:)),
                metadata: ContextMetadata(
                    turnNumber: request.history.count,
                    sessionID: request.userInput,
                    modelProfile: budgetProfile(for: profile)
                ),
                recallQuery: request.recallQuery
            )
        )

        let selectedToolNames = Set(prepared.selectedToolNames)
        var selectedSchemas = toolSchemas.filter { selectedToolNames.contains($0.name) }
        if prepared.mode == "jit" {
            selectedSchemas.append(contentsOf: MembraneInternalTools.schemaSet())
        }

        let distilledPrompt = await distillPromptIfNeeded(
            prompt: prepared.plan.prompt,
            profile: profile,
            toolCount: toolSchemas.count
        )
        let boundedPrompt = await PromptEnvelope.enforce(
            prompt: distilledPrompt,
            profile: profile
        )

        return MembranePlannedBoundary(
            prompt: boundedPrompt,
            toolSchemas: MembraneInternalTools.sortedSchemas(selectedSchemas),
            mode: prepared.mode
        )
    }

    public func transformToolResult(
        toolName: String,
        output: String,
        profile: ContextProfile = .balanced
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

    public func handleInternalToolCall(
        name: String,
        arguments: [String: SendableValue]
    ) async throws -> String? {
        try await session.handleInternalToolCall(
            name: name,
            arguments: stringify(arguments: arguments)
        )
    }

    public func restore(checkpointData: Data?) async throws {
        let snapshot = try checkpointData.map { try JSONDecoder().decode(ContextSnapshot.self, from: $0) }
        try await session.restore(snapshot: snapshot)
    }

    public func snapshotCheckpointData() async throws -> Data? {
        guard let snapshot = try await session.snapshot() else {
            return nil
        }
        return try JSONEncoder().encode(snapshot)
    }

    public func contextSnapshot() async throws -> ContextSnapshot? {
        try await session.snapshot()
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

    private func makeContextSlice(from slice: MembranePlanningSlice) -> ContextSlice {
        let source: ContextSource = switch slice.source {
        case .history:
            .history
        case .memory:
            .memory
        case .retrieval:
            .retrieval
        }

        return ContextSlice(
            content: slice.content,
            tokenCount: max(1, slice.tokenCount),
            importance: slice.importance,
            source: source,
            tier: .full,
            timestamp: ContinuousClock.now
        )
    }

    private func budgetProfile(for profile: ContextProfile) -> BudgetProfile {
        let totalTokens = profile.maxTotalContextTokens
        if totalTokens <= 4096 {
            return .foundationModels4K
        }
        if totalTokens <= 8192 {
            return .openModel8K
        }
        return .cloud200K
    }

    private func distillPromptIfNeeded(
        prompt: String,
        profile: ContextProfile,
        toolCount: Int
    ) async -> String {
        guard profile.preset == .strict4k, toolCount >= 4 else {
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

        return compacted
    }
}

public extension MembraneEnvironment {
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
        let sharedStore = WaxMembraneStorage()
        let session = Membrane.MembraneSession(
            configuration: Membrane.MembraneFeatureConfiguration(
                jitMinToolCount: configuration.jitMinToolCount,
                defaultJITLoadCount: configuration.defaultJITLoadCount,
                pointerThresholdBytes: configuration.pointerThresholdBytes,
                pointerSummaryMaxChars: configuration.pointerSummaryMaxChars,
                runtimeFeatureFlags: configuration.runtimeFeatureFlags,
                runtimeModelAllowlist: configuration.runtimeModelAllowlist
            ),
            budget: budget,
            backend: SwarmMembraneContextCoreBackend(),
            recallStore: recallStore ?? sharedStore,
            pointerStore: pointerStore ?? sharedStore,
            initialSnapshot: initialSnapshot
        )

        return MembraneEnvironment(
            isEnabled: true,
            configuration: configuration,
            adapter: SessionMembraneAgentAdapter(session: session)
        )
    }
}
