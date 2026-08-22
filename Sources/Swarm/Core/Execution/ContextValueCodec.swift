// ContextValueCodec.swift
// Swarm Framework
//
// Internal encoding/decoding between typed context values and SendableValue.

import Foundation

// MARK: - ContextValueCodec

/// Converts typed context values to and from their stored
/// `SendableValue` payloads.
///
/// Both directions travel through JSON so the conversion is performed by the
/// `Codable` machinery alone; no runtime casting decides value identity. The
/// encoder/decoder pair pins `Date` to seconds-since-1970, which keeps typed
/// reads of timestamp payloads exact.
enum ContextValueCodec {
    // MARK: - Encoding

    /// Encodes `value` into its stored payload form.
    ///
    /// - Parameter value: The value written through `setTyped(_:value:)`.
    /// - Returns: The encoded payload. When encoding fails, the historical
    ///   fallback — a string description of the value — is returned so a
    ///   write never throws.
    static func encode<T: Encodable>(_ value: T) -> SendableValue {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(value)
            return try JSONDecoder().decode(SendableValue.self, from: data)
        } catch {
            return .string(String(describing: value))
        }
    }

    // MARK: - Decoding

    /// Decodes `payload` into `T`.
    ///
    /// - Parameters:
    ///   - payload: The stored payload for this slot's value type.
    ///   - type: The static value type of the reading key.
    /// - Returns: The decoded value, or nil when the payload cannot be
    ///   decoded as `T`. A nil result is only reachable when the stored
    ///   payload does not fit `T`; slot identity already guarantees the
    ///   request itself addresses the right slot.
    static func decode<T: Decodable>(_ payload: SendableValue, as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }
}
