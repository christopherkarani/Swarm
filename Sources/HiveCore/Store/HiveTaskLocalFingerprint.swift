import Foundation

/// Task-local fingerprint computation and hashing.
enum HiveTaskLocalFingerprint {
    static func digest<Schema: HiveSchema>(
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        overlay: HiveTaskLocalStore<Schema>,
        debugPayloads: Bool = false
    ) throws -> Data {
        let canonical = try canonicalBytes(
            registry: registry,
            initialCache: initialCache,
            overlay: overlay,
            debugPayloads: debugPayloads
        )
        let hash = HiveSHA256.hash(data: canonical)
        return Data(hash)
    }

    static func canonicalBytes<Schema: HiveSchema>(
        registry: HiveSchemaRegistry<Schema>,
        initialCache: HiveInitialCache<Schema>,
        overlay: HiveTaskLocalStore<Schema>,
        debugPayloads: Bool
    ) throws -> Data {
        let taskLocalSpecs = registry.sortedChannelSpecs.filter { $0.scope == .taskLocal }

        var entries: [(idData: Data, valueData: Data)] = []
        entries.reserveCapacity(taskLocalSpecs.count)

        for spec in taskLocalSpecs {
            guard let encode = spec._encodeBox else {
                throw HiveRuntimeError.missingCodec(channelID: spec.id)
            }

            let effectiveValue = try (overlay.valueAny(for: spec.id) ?? initialCache.valueAny(for: spec.id))

            do {
                let valueData = try encode(effectiveValue)
                let idData = Data(spec.id.rawValue.utf8)
                entries.append((idData: idData, valueData: valueData))
            } catch {
                throw HiveRuntimeError.taskLocalFingerprintEncodeFailed(
                    channelID: spec.id,
                    errorDescription: HiveErrorDescription.describe(
                        error,
                        debugPayloads: debugPayloads
                    )
                )
            }
        }

        var bytes = Data()
        bytes.append(contentsOf: [0x48, 0x4C, 0x46, 0x31])
        appendUInt32BE(try lengthAsUInt32(entries.count), to: &bytes)
        for entry in entries {
            appendUInt32BE(try lengthAsUInt32(entry.idData.count), to: &bytes)
            bytes.append(entry.idData)
            appendUInt32BE(try lengthAsUInt32(entry.valueData.count), to: &bytes)
            bytes.append(entry.valueData)
        }
        return bytes
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func lengthAsUInt32(_ length: Int) throws -> UInt32 {
        guard let value = UInt32(exactly: length) else {
            throw HiveRuntimeError.internalInvariantViolation(
                "Task-local fingerprint value length is out of UInt32 range: \(length)"
            )
        }
        return value
    }

    // error description formatting is centralized in HiveErrorDescription
}
