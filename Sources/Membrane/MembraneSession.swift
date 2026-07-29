import Foundation
import MembraneContextCore
import MembraneCore

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

public struct MembranePreparedContext: Sendable {
    public let plan: ContextPlan
    public let selectedToolNames: [String]
    public let mode: String
    public let snapshot: ContextSnapshot?
    public let recalledMemories: [ContextRecallCandidate]

    public init(
        plan: ContextPlan,
        selectedToolNames: [String],
        mode: String,
        snapshot: ContextSnapshot?,
        recalledMemories: [ContextRecallCandidate] = []
    ) {
        self.plan = plan
        self.selectedToolNames = selectedToolNames
        self.mode = mode
        self.snapshot = snapshot
        self.recalledMemories = recalledMemories
    }
}

public actor MembraneSession {
    private let configuration: MembraneFeatureConfiguration
    private let baseBudget: ContextBudget
    private let backend: any MembraneContextBackend
    private let recallStore: (any ContextRecallStore)?
    private let pointerStore: any PointerStore
    private let pointerResolver: PointerResolver
    private let jitLoader: JITToolLoader

    private var loadedToolNames: [String]
    private var allowListToolNames: [String]
    private var pointerIDs: [String]
    private var usageCounts: [String: Int]
    private var snapshotState: ContextSnapshot?

    public init(
        configuration: MembraneFeatureConfiguration = .default,
        budget: ContextBudget = ContextBudget(totalTokens: 4096, profile: .foundationModels4K),
        backend: (any MembraneContextBackend)? = nil,
        recallStore: (any ContextRecallStore)? = nil,
        pointerStore: (any PointerStore)? = nil,
        initialSnapshot: ContextSnapshot? = nil
    ) {
        self.configuration = configuration
        self.baseBudget = budget
        self.backend = backend ?? MembraneContextCoreBackend()
        self.recallStore = recallStore

        let resolvedPointerStore = pointerStore ?? InMemoryPointerStore()
        self.pointerStore = resolvedPointerStore
        self.pointerResolver = PointerResolver(
            store: resolvedPointerStore,
            config: PointerResolverConfig(
                pointerThresholdBytes: configuration.pointerThresholdBytes,
                summaryMaxChars: configuration.pointerSummaryMaxChars
            )
        )
        self.jitLoader = JITToolLoader(jitMinToolCount: configuration.jitMinToolCount)

        let normalized = initialSnapshot?.normalized()
        self.loadedToolNames = normalized?.toolState.loadedToolNames ?? []
        self.allowListToolNames = normalized?.toolState.allowListToolNames ?? []
        self.pointerIDs = normalized?.pointerIDs ?? []
        self.usageCounts = Dictionary(
            uniqueKeysWithValues: (normalized?.toolState.usageCounts ?? []).map { ($0.toolName, $0.count) }
        )
        self.snapshotState = normalized
    }

    public func prepare(_ request: ContextRequest) async throws -> MembranePreparedContext {
        let recalledMemories = try await recalledMemories(for: request)
        let requestWithRecall = merge(recalledMemories: recalledMemories, into: request)

        let sortedTools = requestWithRecall.tools.sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.description < rhs.description
        }

        var selectedToolNames = sortedTools.map(\.name)
        var toolMode = ContextSnapshot.ToolState.Mode.allowAll
        let nextPlan = jitLoader.plan(
            tools: sortedTools,
            existingPlan: currentToolPlan(fallback: requestWithRecall.toolPlan)
        )

        switch nextPlan {
        case .allowAll:
            allowListToolNames = []
            toolMode = .allowAll

        case let .allowList(toolNames):
            let allowSet = Set(toolNames)
            allowListToolNames = Array(allowSet).sorted()
            selectedToolNames = sortedTools.compactMap { allowSet.contains($0.name) ? $0.name : nil }
            toolMode = .allowList

        case let .jit(index, _):
            var loadedSet = Set(loadedToolNames)
            if loadedSet.isEmpty {
                loadedSet.formUnion(index.map(\.name).sorted().prefix(configuration.defaultJITLoadCount))
            }
            loadedToolNames = Array(loadedSet).sorted()
            selectedToolNames = sortedTools.compactMap { loadedSet.contains($0.name) ? $0.name : nil }
            toolMode = .jit
        }

        let budget = snapshotBudget(from: snapshotState) ?? baseBudget
        let preparation = try await backend.prepare(
            request: ContextRequest(
                systemPrompt: requestWithRecall.systemPrompt,
                basePrompt: requestWithRecall.basePrompt,
                userInput: requestWithRecall.userInput,
                tools: sortedTools,
                toolPlan: nextPlan,
                history: requestWithRecall.history,
                memories: requestWithRecall.memories,
                retrieval: requestWithRecall.retrieval,
                pointers: requestWithRecall.pointers,
                metadata: requestWithRecall.metadata,
                recallQuery: requestWithRecall.recallQuery,
                recallLimit: requestWithRecall.recallLimit
            ),
            budget: budget,
            snapshot: snapshotState
        )

        let mergedSnapshot = makeSnapshot(
            from: preparation.snapshot,
            budget: preparation.plan.budget,
            toolMode: toolMode
        )
        snapshotState = mergedSnapshot

        return MembranePreparedContext(
            plan: preparation.plan,
            selectedToolNames: selectedToolNames.sorted(),
            mode: modeString(toolMode),
            snapshot: mergedSnapshot,
            recalledMemories: recalledMemories
        )
    }

    public func transformToolResult(toolName: String, output: String) async throws -> PointerizationDecision {
        usageCounts[toolName, default: 0] += 1
        let decision = try await pointerResolver.pointerizeIfNeeded(toolName: toolName, output: output)
        if case let .pointer(pointer, _) = decision {
            pointerIDs = Array(Set(pointerIDs + [pointer.id])).sorted()
        }
        snapshotState = makeSnapshot(from: try await backend.snapshot(), budget: snapshotBudget(from: snapshotState) ?? baseBudget, toolMode: currentToolMode())
        return decision
    }

    public func handleInternalToolCall(
        name: String,
        arguments: [String: String]
    ) async throws -> String? {
        switch name {
        case "membrane_load_tool_schema":
            guard let toolName = arguments["tool_name"], toolName.isEmpty == false else {
                return nil
            }
            loadedToolNames = Array(Set(loadedToolNames + [toolName])).sorted()
            snapshotState = makeSnapshot(from: try await backend.snapshot(), budget: snapshotBudget(from: snapshotState) ?? baseBudget, toolMode: .jit)
            return "Loaded tool schema: \(toolName)"

        case "Add_Tools":
            let names = parseToolNames(arguments["tool_names"])
            guard names.isEmpty == false else { return nil }
            loadedToolNames = Array(Set(loadedToolNames + names)).sorted()
            snapshotState = makeSnapshot(from: try await backend.snapshot(), budget: snapshotBudget(from: snapshotState) ?? baseBudget, toolMode: .jit)
            return "Added tools: \(names.sorted().joined(separator: ", "))"

        case "Remove_Tools":
            let names = Set(parseToolNames(arguments["tool_names"]))
            guard names.isEmpty == false else { return nil }
            loadedToolNames.removeAll { names.contains($0) }
            loadedToolNames.sort()
            snapshotState = makeSnapshot(from: try await backend.snapshot(), budget: snapshotBudget(from: snapshotState) ?? baseBudget, toolMode: currentToolMode())
            return "Removed tools: \(names.sorted().joined(separator: ", "))"

        case "resolve_pointer":
            guard let pointerID = arguments["pointer_id"], pointerID.isEmpty == false else {
                return nil
            }
            let payload = try await pointerStore.resolve(pointerID: pointerID)
            if let text = String(data: payload, encoding: .utf8) {
                return text
            }
            return payload.base64EncodedString()

        default:
            return nil
        }
    }

    public func restore(snapshot: ContextSnapshot?) async throws {
        let normalized = snapshot?.normalized()
        snapshotState = normalized
        loadedToolNames = normalized?.toolState.loadedToolNames ?? []
        allowListToolNames = normalized?.toolState.allowListToolNames ?? []
        pointerIDs = normalized?.pointerIDs ?? []
        usageCounts = Dictionary(
            uniqueKeysWithValues: (normalized?.toolState.usageCounts ?? []).map { ($0.toolName, $0.count) }
        )
        try await backend.restore(snapshot: normalized)
    }

    public func snapshot() async throws -> ContextSnapshot? {
        if let backendSnapshot = try await backend.snapshot() {
            snapshotState = makeSnapshot(
                from: backendSnapshot,
                budget: snapshotBudget(from: snapshotState) ?? baseBudget,
                toolMode: currentToolMode()
            )
        }
        return snapshotState?.normalized()
    }

    private func recalledMemories(for request: ContextRequest) async throws -> [ContextRecallCandidate] {
        guard let recallStore else { return [] }
        let query = (request.recallQuery ?? request.userInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return [] }
        return try await recallStore.recall(query: query, limit: request.recallLimit)
    }

    private func merge(
        recalledMemories: [ContextRecallCandidate],
        into request: ContextRequest
    ) -> ContextRequest {
        guard recalledMemories.isEmpty == false else { return request }

        let recalledSlices = recalledMemories.map { candidate in
            ContextSlice(
                content: candidate.content,
                tokenCount: candidate.content.count,
                importance: candidate.score ?? 1.0,
                source: .retrieval,
                tier: .full,
                timestamp: .now
            )
        }

        return ContextRequest(
            systemPrompt: request.systemPrompt,
            basePrompt: request.basePrompt,
            userInput: request.userInput,
            tools: request.tools,
            toolPlan: request.toolPlan,
            history: request.history,
            memories: request.memories,
            retrieval: request.retrieval + recalledSlices,
            pointers: request.pointers,
            metadata: request.metadata,
            recallQuery: request.recallQuery,
            recallLimit: request.recallLimit
        )
    }

    private func currentToolPlan(fallback: ToolPlan) -> ToolPlan {
        switch currentToolMode() {
        case .allowAll:
            return fallback
        case .allowList:
            return .allowList(normalized: allowListToolNames)
        case .jit:
            let index = loadedToolNames.map { ToolIndexEntry(name: $0, description: "") }
            return .jit(normalized: index, loaded: loadedToolNames)
        }
    }

    private func currentToolMode() -> ContextSnapshot.ToolState.Mode {
        if loadedToolNames.isEmpty == false {
            return .jit
        }
        if allowListToolNames.isEmpty == false {
            return .allowList
        }
        return .allowAll
    }

    private func makeSnapshot(
        from backendSnapshot: ContextSnapshot?,
        budget: ContextBudget,
        toolMode: ContextSnapshot.ToolState.Mode
    ) -> ContextSnapshot {
        let usageEntries = usageCounts
            .map { ContextSnapshot.ToolState.UsageCount(toolName: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.toolName != rhs.toolName {
                    return lhs.toolName < rhs.toolName
                }
                return lhs.count < rhs.count
            }

        return ContextSnapshot(
            budget: ContextSnapshot.BudgetSnapshot(
                totalTokens: budget.totalTokens,
                allocations: budget.bucketAllocations.map {
                    .init(bucketID: $0.key.rawValue, allocatedTokens: $0.value)
                }.sorted { $0.bucketID < $1.bucketID },
                kvBytesPerToken: budget.kvBytesPerToken,
                kvMemoryBudgetBytes: budget.kvMemoryBudgetBytes,
                maxSequenceLength: budget.maxSequenceLength
            ),
            csoSummaries: backendSnapshot?.csoSummaries ?? snapshotState?.csoSummaries ?? [],
            pagingCursor: backendSnapshot?.pagingCursor ?? snapshotState?.pagingCursor,
            toolState: .init(
                mode: toolMode,
                loadedToolNames: loadedToolNames,
                allowListToolNames: allowListToolNames,
                usageCounts: usageEntries
            ),
            pointerIDs: pointerIDs,
            backendID: backendSnapshot?.backendID,
            backendState: backendSnapshot?.backendState
        ).normalized()
    }

    private func snapshotBudget(from snapshot: ContextSnapshot?) -> ContextBudget? {
        guard let snapshot else { return nil }
        var budget = ContextBudget(
            totalTokens: snapshot.budget.totalTokens,
            profile: .foundationModels4K,
            kvBytesPerToken: snapshot.budget.kvBytesPerToken,
            kvMemoryBudgetBytes: snapshot.budget.kvMemoryBudgetBytes
        )
        for allocation in snapshot.budget.allocations {
            guard let bucketID = BucketID(rawValue: allocation.bucketID) else { continue }
            try? budget.allocate(allocation.allocatedTokens, to: bucketID)
        }
        return budget
    }

    private func parseToolNames(_ rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func modeString(_ mode: ContextSnapshot.ToolState.Mode) -> String {
        switch mode {
        case .allowAll:
            "allowAll"
        case .allowList:
            "allowList"
        case .jit:
            "jit"
        }
    }
}
