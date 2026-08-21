// SendableValue.swift
// Swarm Framework
//
// A type-safe, Sendable container for dynamic values used in tool arguments and results.

import Foundation

// MARK: - SendableValue

/// A type-safe, Sendable container for dynamic values used in tool arguments and results.
/// Replaces `[String: Any]` which cannot conform to `Sendable`.
public enum SendableValue: Sendable, Equatable, Hashable, Codable {
    // MARK: Public

    // MARK: - Type-Safe Accessors

    /// Returns the Bool value if this is a `.bool`, otherwise nil.
    public var boolValue: Bool? {
        guard case let .bool(v) = self else { return nil }
        return v
    }

    /// Returns the Int value if this is an `.int`, otherwise nil.
    public var intValue: Int? {
        guard case let .int(v) = self else { return nil }
        return v
    }

    /// Returns the Double value if this is a `.double` or `.int`, otherwise nil.
    public var doubleValue: Double? {
        switch self {
        case let .double(v): v
        case let .int(v): Double(v)
        default: nil
        }
    }

    /// Returns the String value if this is a `.string`, otherwise nil.
    public var stringValue: String? {
        guard case let .string(v) = self else { return nil }
        return v
    }

    /// Returns the array if this is an `.array`, otherwise nil.
    public var arrayValue: [SendableValue]? {
        guard case let .array(v) = self else { return nil }
        return v
    }

    /// Returns the dictionary if this is a `.dictionary`, otherwise nil.
    public var dictionaryValue: [String: SendableValue]? {
        guard case let .dictionary(v) = self else { return nil }
        return v
    }

    /// Returns true if this is `.null`.
    public var isNull: Bool {
        guard case .null = self else { return false }
        return true
    }

    // MARK: - Convenience Initializers

    public init(_ value: Bool) { self = .bool(value) }
    public init(_ value: Int) { self = .int(value) }
    public init(_ value: Double) { self = .double(value) }
    public init(_ value: String) { self = .string(value) }
    public init(_ value: [SendableValue]) { self = .array(value) }
    public init(_ value: [String: SendableValue]) { self = .dictionary(value) }

    // MARK: - Subscript Access

    /// Access dictionary values by key.
    public subscript(key: String) -> SendableValue? {
        guard case let .dictionary(dict) = self else { return nil }
        return dict[key]
    }

    /// Access array values by index.
    public subscript(index: Int) -> SendableValue? {
        guard case let .array(arr) = self, index >= 0, index < arr.count else { return nil }
        return arr[index]
    }

    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SendableValue])
    case dictionary([String: SendableValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SendableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: SendableValue].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value for SendableValue"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

// MARK: ExpressibleByNilLiteral

extension SendableValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) { self = .null }
}

// MARK: ExpressibleByBooleanLiteral

extension SendableValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

// MARK: ExpressibleByIntegerLiteral

extension SendableValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

// MARK: ExpressibleByFloatLiteral

extension SendableValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

// MARK: ExpressibleByStringLiteral

extension SendableValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

// MARK: ExpressibleByArrayLiteral

extension SendableValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: SendableValue...) { self = .array(elements) }
}

// MARK: ExpressibleByDictionaryLiteral

extension SendableValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, SendableValue)...) {
        self = .dictionary(elements.reduce(into: [String: SendableValue]()) { $0[$1.0] = $1.1 })
    }
}

// MARK: CustomStringConvertible

extension SendableValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: return "null"
        case let .bool(v): return String(v)
        case let .int(v): return String(v)
        case let .double(v): return String(v)
        case let .string(v): return "\"\(v)\""
        case let .array(v): return "[\(v.map(\.description).joined(separator: ", "))]"
        case let .dictionary(v):
            let pairs = v
                .keys
                .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                .compactMap { key in
                    guard let value = v[key] else { return nil }
                    return "\"\(key)\": \(value.description)"
                }
                .joined(separator: ", ")
            return "{\(pairs)}"
        }
    }
}

// MARK: CustomDebugStringConvertible

extension SendableValue: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .null: "SendableValue.null"
        case let .bool(v): "SendableValue.bool(\(v))"
        case let .int(v): "SendableValue.int(\(v))"
        case let .double(v): "SendableValue.double(\(v))"
        case let .string(v): "SendableValue.string(\"\(v)\")"
        case let .array(v): "SendableValue.array(\(v.map(\.debugDescription)))"
        case let .dictionary(v): "SendableValue.dictionary(\(v))"
        }
    }
}

// MARK: - Encodable Type Conversion

public extension SendableValue {
    // MARK: Internal

    /// Error thrown when encoding/decoding fails.
    enum ConversionError: Error, LocalizedError {
        // MARK: Public

        public var errorDescription: String? {
            switch self {
            case let .encodingFailed(message):
                "Failed to encode value: \(message)"
            case let .decodingFailed(message):
                "Failed to decode value: \(message)"
            case let .unsupportedType(type):
                "Unsupported type for conversion: \(type)"
            }
        }

        case encodingFailed(String)
        case decodingFailed(String)
        case unsupportedType(String)
    }

    /// Creates a SendableValue by encoding an Encodable value.
    ///
    /// This initializer converts any `Encodable` type to a `SendableValue`,
    /// enabling type-safe tools to return their results through the standard
    /// `Tool` interface.
    ///
    /// - Parameter value: The value to encode.
    /// - Throws: `ConversionError.encodingFailed` if encoding fails.
    ///
    /// Example:
    /// ```swift
    /// struct UserInfo: Codable {
    ///     let name: String
    ///     let age: Int
    /// }
    ///
    /// let user = UserInfo(name: "Alice", age: 30)
    /// let sendable = try SendableValue(encoding: user)
    /// // Result: .dictionary(["name": .string("Alice"), "age": .int(30)])
    /// ```
    init(encoding value: some Encodable) throws {
        // Handle primitive types directly for efficiency
        if let boolValue = value as? Bool {
            self = .bool(boolValue)
            return
        }
        if let intValue = value as? Int {
            self = .int(intValue)
            return
        }
        if let doubleValue = value as? Double {
            self = .double(doubleValue)
            return
        }
        if let stringValue = value as? String {
            self = .string(stringValue)
            return
        }

        // Handle arrays of SendableValue
        if let arrayValue = value as? [SendableValue] {
            self = .array(arrayValue)
            return
        }

        // Handle dictionaries of SendableValue
        if let dictValue = value as? [String: SendableValue] {
            self = .dictionary(dictValue)
            return
        }

        // For complex types, use JSON encoding as an intermediate format
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        do {
            let data = try encoder.encode(value)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            self = try Self.fromJSONObject(jsonObject)
        } catch {
            throw ConversionError.encodingFailed(String(describing: error))
        }
    }

    /// Decodes this SendableValue to a Decodable type.
    ///
    /// - Returns: The decoded value.
    /// - Throws: `ConversionError.decodingFailed` if decoding fails.
    ///
    /// Example:
    /// ```swift
    /// let sendable: SendableValue = .dictionary([
    ///     "name": .string("Alice"),
    ///     "age": .int(30)
    /// ])
    ///
    /// let user: UserInfo = try sendable.decode()
    /// // Result: UserInfo(name: "Alice", age: 30)
    /// ```
    func decode<T: Decodable>() throws -> T {
        // Handle primitive types directly
        if T.self == Bool.self, let value = boolValue {
            guard let result = value as? T else {
                throw ConversionError.decodingFailed("Failed to cast Bool to \(T.self)")
            }
            return result
        }
        if T.self == Int.self, let value = intValue {
            guard let result = value as? T else {
                throw ConversionError.decodingFailed("Failed to cast Int to \(T.self)")
            }
            return result
        }
        if T.self == Double.self, let value = doubleValue {
            guard let result = value as? T else {
                throw ConversionError.decodingFailed("Failed to cast Double to \(T.self)")
            }
            return result
        }
        if T.self == String.self, let value = stringValue {
            guard let result = value as? T else {
                throw ConversionError.decodingFailed("Failed to cast String to \(T.self)")
            }
            return result
        }

        // For complex types, round-trip through Codable JSON. JSONSerialization
        // cannot encode a top-level String/number, so do not use it here.
        do {
            let data = try JSONEncoder().encode(self)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ConversionError.decodingFailed(String(describing: error))
        }
    }

    // MARK: Internal

    /// Converts a raw JSON value (from JSONSerialization) to SendableValue.
    /// Returns `.null` for unsupported types.
    package static func fromJSONValue(_ value: Any) -> SendableValue {
        (try? fromJSONObject(value)) ?? .null
    }

    package func toJSONObject() -> Any {
        _convertToJSONObject()
    }

    // MARK: Private

    /// Converts a JSON object to SendableValue.
    private static func fromJSONObject(_ object: Any) throws -> SendableValue {
        switch object {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            // Check if it's actually an integer stored as double.
            // Use the JavaScript safe integer range (2^53) to avoid precision loss
            // when converting Double to Int near Int.min/Int.max boundaries.
            if double.truncatingRemainder(dividingBy: 1) == 0,
               double >= -9_007_199_254_740_992, double <= 9_007_199_254_740_992 {
                return .int(Int(double))
            }
            return .double(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return try .array(array.map { try fromJSONObject($0) })
        case let dict as [String: Any]:
            var result: [String: SendableValue] = [:]
            for (key, value) in dict {
                result[key] = try fromJSONObject(value)
            }
            return .dictionary(result)
        default:
            throw ConversionError.unsupportedType(String(describing: type(of: object)))
        }
    }

    /// Converts this SendableValue to a JSON-compatible object.
    fileprivate func _convertToJSONObject() -> Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(v):
            return v
        case let .int(v):
            return v
        case let .double(v):
            return v
        case let .string(v):
            return v
        case let .array(v):
            return v.map { $0._convertToJSONObject() }
        case let .dictionary(v):
            var result: [String: Any] = [:]
            for (key, value) in v {
                result[key] = value._convertToJSONObject()
            }
            return result
        }
    }
}

// Ensure no duplicate definitions
