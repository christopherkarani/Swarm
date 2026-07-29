import CryptoKit
import Foundation
import MembraneCore

public struct PointerResolverConfig: Sendable, Equatable {
    public var pointerThresholdBytes: Int
    public var summaryMaxChars: Int

    public init(pointerThresholdBytes: Int = 1024, summaryMaxChars: Int = 200) {
        self.pointerThresholdBytes = pointerThresholdBytes
        self.summaryMaxChars = summaryMaxChars
    }
}

public enum PointerizationDecision: Sendable, Equatable {
    case inline(String)
    case pointer(MemoryPointer, replacementText: String)
}

public actor PointerResolver: Sendable {
    private let store: any PointerStore
    private let config: PointerResolverConfig

    public init(store: any PointerStore, config: PointerResolverConfig = .init()) {
        self.store = store
        self.config = config
    }

    public func pointerizeIfNeeded(toolName: String, output: String) async throws -> PointerizationDecision {
        let payload = Data(output.utf8)
        if payload.count <= config.pointerThresholdBytes {
            return .inline(output)
        }

        let summary = Self.makeSummary(text: output, maxChars: config.summaryMaxChars)
        let pointer = try await store.store(payload: payload, dataType: .document, summary: summary)

        let replacement = """
        [POINTER id=\(pointer.id) tool=\(toolName) bytes=\(pointer.byteSize)] \(pointer.summary)
        Use resolve_pointer(pointer_id: "\(pointer.id)") to access the full payload.
        """

        return .pointer(pointer, replacementText: replacement)
    }

    static func makeSummary(text: String, maxChars: Int) -> String {
        let maxChars = max(0, maxChars)
        guard text.count > maxChars else {
            return text
        }

        let end = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<end]) + "..."
    }
}

public actor InMemoryPointerStore: PointerStore {
    private var payloadByID: [String: Data]

    public init() {
        self.payloadByID = [:]
    }

    public func store(payload: Data, dataType: MemoryPointer.DataType, summary: String) async throws -> MemoryPointer {
        let id = Self.pointerID(for: payload)
        payloadByID[id] = payload
        return MemoryPointer(id: id, dataType: dataType, byteSize: payload.count, summary: summary)
    }

    public func resolve(pointerID: String) async throws -> Data {
        guard let payload = payloadByID[pointerID] else {
            throw MembraneError.pointerResolutionFailed(pointerID: pointerID)
        }
        return payload
    }

    public func delete(pointerID: String) async {
        payloadByID.removeValue(forKey: pointerID)
    }

    private static func pointerID(for payload: Data) -> String {
        let digest = SHA256.hash(data: payload)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "ptr_\(hex.prefix(12))"
    }
}
