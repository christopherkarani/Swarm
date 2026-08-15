#if SWARM_INTEGRATIONS
import Foundation
import MembraneCore
import Wax

protocol WaxPointerIndex: Sendable {
    func save(_ text: String, metadata: [String: String]) async throws
    func flush() async throws
    func search(_ query: String, options: Wax.Memory.SearchOptions) async throws -> Wax.Memory.Results
    func close() async throws
}

extension Wax.Memory: WaxPointerIndex {}

actor WaxMembraneStorage: PointerStore, ContextRecallStore {
    private enum MetadataKey {
        static let kind = "membrane.kind"
        static let pointerID = "membrane.pointer.id"
        static let pointerSHA256 = "membrane.pointer.sha256"
        static let pointerDataType = "membrane.pointer.dataType"
        static let payloadEncoding = "membrane.pointer.payloadEncoding"
        static let payloadFrameID = "membrane.pointer.payloadFrameID"
        static let summary = "membrane.pointer.summary"
        static let pointerPayloadKind = "pointerPayload"
        static let pointerPayloadFrameKind = "membrane.pointer.payloadFrame"
    }

    private enum StorageFormat {
        static let payloadMarker = "\n\n__payload_base64__\n"
    }

    static var defaultStoreURL: URL {
        let fileManager = FileManager.default
        let baseURL = SwarmRuntimeEnvironment.isRunningTests
            ? fileManager.temporaryDirectory
            : (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory)
        let root = baseURL
            .appendingPathComponent("Swarm", isDirectory: true)
            .appendingPathComponent(SwarmRuntimeEnvironment.isRunningTests ? "MembraneTests" : "Membrane", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let fileName = SwarmRuntimeEnvironment.isRunningTests
            ? "membrane-store-\(UUID().uuidString).mv2s"
            : "membrane-store.mv2s"
        return root.appendingPathComponent(fileName)
    }

    private let url: URL
    private let memoryFactory: @Sendable (URL) async throws -> any WaxPointerIndex
    private var memory: (any WaxPointerIndex)?
    private var cachedPayloads: [String: Data] = [:]

    init(
        url: URL = defaultStoreURL,
        memoryFactory: @escaping @Sendable (URL) async throws -> any WaxPointerIndex = { try await Wax.Memory(at: $0) }
    ) {
        self.url = url
        self.memoryFactory = memoryFactory
    }

    func store(payload: Data, dataType: MemoryPointer.DataType, summary: String) async throws -> MemoryPointer {
        let pointerID = Self.pointerID(for: payload)
        let sha256 = Self.sha256Hex(payload)
        let payloadFrameID = try await persistPayloadFrame(
            payload,
            pointerID: pointerID,
            sha256: sha256,
            dataType: dataType
        )
        let storedDocument = Self.storedPointerDocument(
            pointerID: pointerID,
            summary: summary
        )

        let memory = try await ensureMemory()
        do {
            try await memory.save(
                storedDocument,
                metadata: [
                    MetadataKey.kind: MetadataKey.pointerPayloadKind,
                    MetadataKey.pointerID: pointerID,
                    MetadataKey.pointerSHA256: sha256,
                    MetadataKey.pointerDataType: dataType.rawValue,
                    MetadataKey.payloadEncoding: "frame",
                    MetadataKey.payloadFrameID: String(payloadFrameID),
                    MetadataKey.summary: summary,
                ]
            )
            try await memory.flush()
        } catch {
            try? await deletePersistedFrame(frameID: payloadFrameID)
            throw error
        }

        cachedPayloads[pointerID] = payload
        return MemoryPointer(
            id: pointerID,
            dataType: dataType,
            byteSize: payload.count,
            summary: summary
        )
    }

    func resolve(pointerID: String) async throws -> Data {
        if let cached = cachedPayloads[pointerID] {
            return cached
        }

        if let payload = try await persistedPayloadFrame(pointerID: pointerID) {
            cachedPayloads[pointerID] = payload
            return payload
        }

        let memory = try await ensureMemory()
        let results = try await memory.search(
            pointerID,
            options: .init(topK: 20, includeSurrogates: false, mode: .textOnly)
        )
        guard let item = results.items.first(where: {
            $0.metadata[MetadataKey.pointerID] == pointerID &&
                $0.metadata[MetadataKey.kind] == MetadataKey.pointerPayloadKind
        }) else {
            throw MembraneError.pointerResolutionFailed(pointerID: pointerID)
        }

        let payload = Self.decodedPayload(from: item.text) ?? Data(item.text.utf8)
        cachedPayloads[pointerID] = payload
        return payload
    }

    func delete(pointerID: String) async {
        cachedPayloads[pointerID] = nil
        try? await deletePersistedFrames(pointerID: pointerID)
    }

    func recall(query: String, limit: Int) async throws -> [ContextRecallCandidate] {
        let memory = try await ensureMemory()
        let results = try await memory.search(
            query,
            options: .init(topK: max(1, limit), includeSurrogates: false, mode: .textOnly)
        )
        return results.items.map { item in
            ContextRecallCandidate(
                content: item.text,
                score: Double(item.score),
                provenance: ContextProvenance(
                    backendID: "swarm.wax",
                    recordID: String(item.frameId),
                    kind: item.metadata[MetadataKey.kind] ?? "unknown",
                    metadata: item.metadata
                )
            )
        }
    }

    private func ensureMemory() async throws -> any WaxPointerIndex {
        if let memory {
            return memory
        }
        let resolved = try await memoryFactory(url)
        memory = resolved
        return resolved
    }

    private func closeMemoryIfOpen() async throws {
        guard let existing = memory else { return }
        try await existing.close()
        memory = nil
    }

    private func openFrameStore() async throws -> Wax.FrameStore {
        if FileManager.default.fileExists(atPath: url.path) {
            return try await Wax.FrameStore.open(at: url)
        }
        return try await Wax.FrameStore.create(at: url)
    }

    private func withFrameStore<Result>(
        _ body: (Wax.FrameStore) async throws -> Result
    ) async throws -> Result {
        let frameStore = try await openFrameStore()
        do {
            let result = try await body(frameStore)
            await frameStore.close()
            return result
        } catch {
            await frameStore.close()
            throw error
        }
    }

    private func persistPayloadFrame(
        _ payload: Data,
        pointerID: String,
        sha256: String,
        dataType: MemoryPointer.DataType
    ) async throws -> UInt64 {
        try await closeMemoryIfOpen()
        return try await withFrameStore { frameStore in
            try await frameStore.put(
                payload,
                kind: MetadataKey.pointerPayloadFrameKind,
                metadata: [
                    MetadataKey.kind: MetadataKey.pointerPayloadFrameKind,
                    MetadataKey.pointerID: pointerID,
                    MetadataKey.pointerSHA256: sha256,
                    MetadataKey.pointerDataType: dataType.rawValue,
                    MetadataKey.payloadEncoding: "raw",
                ]
            )
        }
    }

    private func persistedPayloadFrame(pointerID: String) async throws -> Data? {
        try await closeMemoryIfOpen()
        return try await withFrameStore { frameStore in
            let frames = await frameStore.frames()
            guard let frame = frames.reversed().first(where: {
                $0.status == .active &&
                    $0.metadata[MetadataKey.pointerID] == pointerID &&
                    $0.metadata[MetadataKey.kind] == MetadataKey.pointerPayloadFrameKind
            }) else {
                return nil
            }
            return try await frameStore.content(frameID: frame.id)
        }
    }

    private func deletePersistedFrame(frameID: UInt64) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try await closeMemoryIfOpen()
        try await withFrameStore { frameStore in
            try await frameStore.delete(frameID: frameID)
        }
    }

    private func deletePersistedFrames(pointerID: String) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try await closeMemoryIfOpen()
        try await withFrameStore { frameStore in
            let frames = await frameStore.frames()
            for frame in frames where frame.status == .active && frame.metadata[MetadataKey.pointerID] == pointerID {
                try await frameStore.delete(frameID: frame.id)
            }
        }
    }

    private static func pointerID(for payload: Data) -> String {
        let hash = sha256Hex(payload)
        return "ptr_\(hash.prefix(16))"
    }

    private static func sha256Hex(_ payload: Data) -> String {
        SwarmSHA256.hex(payload)
    }

    private static func storedPointerDocument(
        pointerID: String,
        summary: String
    ) -> String {
        """
        pointer_id: \(pointerID)
        summary: \(summary)
        """
    }

    private static func decodedPayload(from storedText: String) -> Data? {
        if let range = storedText.range(of: StorageFormat.payloadMarker) {
            let encodedPayload = storedText[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Data(base64Encoded: String(encodedPayload))
        }
        return Data(base64Encoded: storedText)
    }
}
#endif
