import Foundation

/// Typed failures for ``InMemoryMembraneBackend`` state round-trips.
public enum InMemoryMembraneBackendError: Error, Sendable, Equatable {
    /// Persisted state used an unknown version.
    case snapshotVersionMismatch(expected: Int, found: Int)
    /// Persisted state could not be decoded.
    case snapshotCorrupt(reason: String)
    /// Live state could not be encoded.
    case encodingFailed(reason: String)
}

/// Portable bounded in-memory `MembraneContextBackend`.
///
/// Lives in MembraneCore with no ContextCore imports, so it builds and
/// behaves identically on Linux. It retains recent history/memory/retrieval
/// slices across `prepare` calls (deduplicated, capacity-bounded) and folds
/// the highest-importance slices that fit the token budget into the prompt,
/// using the same `Relevant Context:` shape as the ContextCore backend.
/// Backend state round-trips through `ContextSnapshot.backendState`.
public actor InMemoryMembraneBackend: MembraneContextBackend {
    /// Always ``MembraneBackendID/inMemory``.
    public nonisolated let backendID = MembraneBackendID.inMemory.rawValue

    private struct StoredSlice: Sendable, Codable, Equatable {
        var content: String
        var tokenCount: Int
        var importance: Double
        var source: ContextSource
    }

    private struct PersistedState: Sendable, Codable, Equatable {
        var version: Int
        var slices: [StoredSlice]
        var prepareCount: Int
    }

    private static let stateVersion = 1

    private let capacity: Int
    private var slices: [StoredSlice] = []
    private var prepareCount = 0
    private var lastSnapshot: ContextSnapshot?

    /// Creates an in-memory backend.
    ///
    /// - Parameter capacity: Maximum retained slices. Oldest slices evict
    ///   first; repeats of the same content collapse to the latest copy.
    public init(capacity: Int = 128) {
        self.capacity = max(1, capacity)
    }

    /// Number of slices currently retained.
    public var storedSliceCount: Int {
        slices.count
    }

    /// Number of `prepare` calls served (restored across snapshots).
    public var totalPrepares: Int {
        prepareCount
    }

    public func prepare(
        request: ContextRequest,
        budget: ContextBudget,
        snapshot: ContextSnapshot?
    ) async throws -> MembraneBackendPreparation {
        if let snapshot, snapshot.backendID == backendID, let data = snapshot.backendState {
            try restoreState(from: data)
        }

        append(request.history + request.memories + request.retrieval)
        prepareCount += 1

        let basePrompt = request.basePrompt.isEmpty ? request.userInput : request.basePrompt
        let prompt = assemblePrompt(base: basePrompt, budgetTotal: budget.totalTokens)
        let backendState = try encodeState()
        let backendSnapshot = ContextSnapshot(
            budget: snapshot?.budget ?? .init(totalTokens: budget.totalTokens),
            toolState: snapshot?.toolState ?? .init(
                mode: .allowAll,
                loadedToolNames: [],
                allowListToolNames: [],
                usageCounts: []
            ),
            pointerIDs: snapshot?.pointerIDs ?? [],
            backendID: backendID,
            backendState: backendState
        ).normalized()
        lastSnapshot = backendSnapshot

        return MembraneBackendPreparation(
            plan: ContextPlan(
                prompt: prompt,
                systemPrompt: request.systemPrompt,
                toolPlan: request.toolPlan,
                budget: budget,
                metadata: request.metadata
            ),
            snapshot: backendSnapshot
        )
    }

    public func restore(snapshot: ContextSnapshot?) async throws {
        guard let snapshot else {
            slices = []
            prepareCount = 0
            lastSnapshot = nil
            return
        }
        let normalized = snapshot.normalized()
        if normalized.backendID == backendID, let data = normalized.backendState {
            try restoreState(from: data)
        } else {
            slices = []
            prepareCount = 0
        }
        lastSnapshot = normalized
    }

    public func snapshot() async throws -> ContextSnapshot? {
        lastSnapshot
    }

    private func append(_ slices: [ContextSlice]) {
        for slice in slices {
            self.slices.append(
                StoredSlice(
                    content: slice.content,
                    tokenCount: slice.tokenCount,
                    importance: slice.importance.isFinite ? slice.importance : 0,
                    source: slice.source
                )
            )
        }
        deduplicate()
        if self.slices.count > capacity {
            self.slices.removeFirst(self.slices.count - capacity)
        }
    }

    private func deduplicate() {
        var seen: Set<String> = []
        var collapsed: [StoredSlice] = []
        collapsed.reserveCapacity(slices.count)
        for slice in slices.reversed() {
            let key = "\(slice.source.rawValue)\n\(slice.content)"
            if seen.insert(key).inserted {
                collapsed.append(slice)
            }
        }
        slices = collapsed.reversed()
    }

    private func assemblePrompt(base: String, budgetTotal: Int) -> String {
        var remaining = max(0, budgetTotal - Self.estimatedTokens(base))
        let ranked = slices.sorted { lhs, rhs in
            if lhs.importance == rhs.importance {
                return lhs.content < rhs.content
            }
            return lhs.importance > rhs.importance
        }
        var included: [String] = []
        for slice in ranked {
            let cost = max(1, slice.tokenCount)
            guard cost <= remaining else {
                continue
            }
            remaining -= cost
            included.append(slice.content)
        }
        guard !included.isEmpty else {
            return base
        }
        return """
        \(base)

        Relevant Context:
        \(included.joined(separator: "\n\n"))
        """
    }

    private func encodeState() throws -> Data {
        do {
            return try JSONEncoder().encode(
                PersistedState(version: Self.stateVersion, slices: slices, prepareCount: prepareCount)
            )
        } catch {
            throw InMemoryMembraneBackendError.encodingFailed(reason: String(describing: error))
        }
    }

    private func restoreState(from data: Data) throws {
        let state: PersistedState
        do {
            state = try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            throw InMemoryMembraneBackendError.snapshotCorrupt(reason: String(describing: error))
        }
        guard state.version == Self.stateVersion else {
            throw InMemoryMembraneBackendError.snapshotVersionMismatch(
                expected: Self.stateVersion,
                found: state.version
            )
        }
        slices = Array(state.slices.suffix(capacity))
        prepareCount = state.prepareCount
    }

    private static func estimatedTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}
