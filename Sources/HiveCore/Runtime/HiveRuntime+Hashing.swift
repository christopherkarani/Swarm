import Foundation

extension HiveRuntime {
    func payloadHash(for channelID: HiveChannelID, in global: HiveGlobalStore<Schema>) throws -> String {
        let spec = try storeSupport.requireSpec(for: channelID)
        let value = try global.valueAny(for: channelID)
        let bytes = try canonicalBytes(for: value, spec: spec)
        let hash = HiveSHA256.hash(data: bytes)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func makeGlobalChannelPayloadHashes(
        from global: HiveGlobalStore<Schema>
    ) throws -> [HiveChannelID: String] {
        var hashes: [HiveChannelID: String] = [:]
        hashes.reserveCapacity(registry.sortedChannelSpecs.count)
        for spec in registry.sortedChannelSpecs where spec.scope == .global {
            hashes[spec.id] = try payloadHash(for: spec.id, in: global)
        }
        return hashes
    }

    func makeInterruptionSnapshot(
        from interruption: HiveInterrupt<Schema>?
    ) throws -> HiveRuntimeInterruptionSnapshot? {
        guard let interruption else { return nil }
        let payloadBytes: Data
        if let stableJSON = try stableJSONDataIfEncodable(interruption.payload) {
            payloadBytes = stableJSON
        } else {
            payloadBytes = Data(String(reflecting: type(of: interruption.payload)).utf8)
        }
        let digest = HiveSHA256.hash(data: payloadBytes)
        let payloadHash = digest.compactMap { String(format: "%02x", $0) }.joined()
        return HiveRuntimeInterruptionSnapshot(
            interruptID: interruption.id,
            payloadHash: payloadHash
        )
    }

    func makeFrontierSummary(
        from frontier: [HiveFrontierTask<Schema>]
    ) throws -> [HiveRuntimeFrontierSummary] {
        var summary: [HiveRuntimeFrontierSummary] = []
        summary.reserveCapacity(frontier.count)
        for entry in frontier {
            let fingerprint = try HiveTaskLocalFingerprint.digest(
                registry: registry,
                initialCache: initialCache,
                overlay: entry.seed.local,
                debugPayloads: false
            )
            let digest = HiveSHA256.hash(data: fingerprint)
            let fingerprintHash = digest.compactMap { String(format: "%02x", $0) }.joined()
            summary.append(
                HiveRuntimeFrontierSummary(
                    nodeID: entry.seed.nodeID,
                    provenance: entry.provenance,
                    taskLocalFingerprintHash: fingerprintHash
                )
            )
        }
        summary.sort { lhs, rhs in
            if lhs.nodeID != rhs.nodeID {
                return HiveOrdering.lexicographicallyPrecedes(lhs.nodeID.rawValue, rhs.nodeID.rawValue)
            }
            if lhs.provenance != rhs.provenance {
                return HiveOrdering.lexicographicallyPrecedes(lhs.provenance.rawValue, rhs.provenance.rawValue)
            }
            return HiveOrdering.lexicographicallyPrecedes(lhs.taskLocalFingerprintHash, rhs.taskLocalFingerprintHash)
        }
        return summary
    }

    func writeAppliedMetadata(
        for channelID: HiveChannelID,
        in global: HiveGlobalStore<Schema>,
        debugPayloads: Bool
    ) throws -> [String: String] {
        guard debugPayloads else { return [:] }
        let spec = try storeSupport.requireSpec(for: channelID)
        let value = try global.valueAny(for: channelID)

        var encoding: String = "unhashable"
        var payload: String = ""

        if let encode = spec._encodeBox {
            do {
                let data = try encode(value)
                encoding = "codec.base64"
                payload = data.base64EncodedString()
            } catch {
                if let json = try stableJSONDataIfEncodable(value) {
                    encoding = "json.utf8"
                    payload = String(decoding: json, as: UTF8.self)
                }
            }
        } else if let json = try stableJSONDataIfEncodable(value) {
            encoding = "json.utf8"
            payload = String(decoding: json, as: UTF8.self)
        }

        return [
            "valueTypeID": spec.valueTypeID,
            "codecID": spec.codecID ?? "",
            "payloadEncoding": encoding,
            "payload": payload
        ]
    }

    func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private func canonicalBytes(for value: any Sendable, spec: AnyHiveChannelSpec<Schema>) throws -> Data {
        if let encode = spec._encodeBox {
            do {
                return try encode(value)
            } catch {
                if let json = try stableJSONDataIfEncodable(value) {
                    return json
                }
                return Data(("unhashable:" + spec.valueTypeID).utf8)
            }
        }

        if let json = try stableJSONDataIfEncodable(value) {
            return json
        }

        return Data(("unhashable:" + spec.valueTypeID).utf8)
    }

    private func stableJSONDataIfEncodable(_ value: any Sendable) throws -> Data? {
        guard let encodable = value as? any Encodable else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(HiveAnyEncodable(encodable))
    }

    private struct HiveAnyEncodable: Encodable {
        let encodable: any Encodable

        init(_ encodable: any Encodable) {
            self.encodable = encodable
        }

        func encode(to encoder: Encoder) throws {
            try encodable.encode(to: encoder)
        }
    }
}
