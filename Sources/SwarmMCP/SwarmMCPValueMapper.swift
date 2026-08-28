#if SWARM_MCP
import Foundation
import MCP
import Swarm

enum SwarmMCPValueMapper {
    static func mcpValue(from value: SendableValue) -> Value {
        switch value {
        case .null:
            .null
        case let .bool(boolValue):
            .bool(boolValue)
        case let .int(intValue):
            .int(intValue)
        case let .double(doubleValue):
            .double(doubleValue)
        case let .string(stringValue):
            .string(stringValue)
        case let .array(arrayValue):
            .array(arrayValue.map { mcpValue(from: $0) })
        case let .dictionary(dictionaryValue):
            .object(dictionaryValue.mapValues { mcpValue(from: $0) })
        }
    }

    static func sendableValue(from value: Value) -> SendableValue {
        switch value {
        case .null:
            return .null
        case let .bool(boolValue):
            return .bool(boolValue)
        case let .int(intValue):
            return .int(intValue)
        case let .double(doubleValue):
            return .double(doubleValue)
        case let .string(stringValue):
            return .string(stringValue)
        case let .data(mimeType: mimeType, data):
            let encoded = data.dataURLEncoded(mimeType: mimeType)
            return .string(encoded)
        case let .array(arrayValue):
            return .array(arrayValue.map { sendableValue(from: $0) })
        case let .object(objectValue):
            return .dictionary(objectValue.mapValues { sendableValue(from: $0) })
        }
    }

    static func sendableObject(from object: [String: Value]) -> [String: SendableValue] {
        object.mapValues { sendableValue(from: $0) }
    }
}
#endif
