// ToolArgumentProcessor.swift
// Swarm Framework
//
// Shared argument validation and normalization for AnyJSONTool.

import Foundation

// MARK: - ToolArgumentProcessor

/// Shared argument validation + normalization logic for `AnyJSONTool`.
enum ToolArgumentProcessor {
    // MARK: Internal

    /// Maximum recursion depth for nested object/array parameters to prevent stack overflow.
    static let maxDepth = 50

    static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws {
        try validate(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil, depth: 0)
    }

    static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue]
    ) throws -> [String: SendableValue] {
        try normalize(toolName: toolName, parameters: parameters, arguments: arguments, pathPrefix: nil, depth: 0)
    }

    // MARK: Private

    private static func validate(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?,
        depth: Int
    ) throws {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(pathPrefix ?? "root")"
            )
        }

        for param in parameters where param.isRequired {
            guard arguments[param.name] != nil else {
                let fullPath = join(pathPrefix, param.name)
                throw AgentError.invalidToolArguments(
                    toolName: toolName,
                    reason: "Missing required parameter: \(fullPath)"
                )
            }
        }

        for param in parameters {
            guard let value = arguments[param.name] else { continue }
            let fullPath = join(pathPrefix, param.name)
            try validateValue(toolName: toolName, value: value, expected: param.type, path: fullPath, depth: depth)
        }
    }

    private static func normalize(
        toolName: String,
        parameters: [ToolParameter],
        arguments: [String: SendableValue],
        pathPrefix: String?,
        depth: Int
    ) throws -> [String: SendableValue] {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(pathPrefix ?? "root")"
            )
        }

        var normalized = arguments

        // Apply default values (also when model explicitly sends null)
        for param in parameters {
            let currentValue = normalized[param.name]
            if currentValue == nil || currentValue == .null, let defaultValue = param.defaultValue {
                normalized[param.name] = defaultValue
            }
        }

        // Coerce known parameters to expected types
        for param in parameters {
            guard let value = normalized[param.name] else { continue }
            let fullPath = join(pathPrefix, param.name)
            normalized[param.name] = try coerceValue(toolName: toolName, value: value, expected: param.type, path: fullPath, depth: depth)
        }

        // Validate after applying defaults + coercion
        try validate(toolName: toolName, parameters: parameters, arguments: normalized, pathPrefix: pathPrefix, depth: depth)
        return normalized
    }

    private static func validateValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String,
        depth: Int = 0
    ) throws {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(path)"
            )
        }

        switch expected {
        case .any:
            return

        case .string:
            guard case .string = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .int:
            switch value {
            case .int:
                return
            case let .double(d) where d.truncatingRemainder(dividingBy: 1) == 0
                && d >= Double(Int.min)
                && d <= Double(Int.max):
                return
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .double:
            switch value {
            case .double,
                 .int:
                return
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .bool:
            guard case .bool = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case let .array(elementType):
            guard case let .array(elements) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            for (index, element) in elements.enumerated() {
                try validateValue(
                    toolName: toolName,
                    value: element,
                    expected: elementType,
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            try validate(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path, depth: depth + 1)

        case let .oneOf(options):
            guard case let .string(s) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            guard options.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) else {
                throw AgentError.invalidToolArguments(
                    toolName: toolName,
                    reason: "Invalid value for parameter: \(path). Expected oneOf(\(options.joined(separator: ", ")))"
                )
            }
        }
    }

    private static func coerceValue(
        toolName: String,
        value: SendableValue,
        expected: ToolParameter.ParameterType,
        path: String,
        depth: Int = 0
    ) throws -> SendableValue {
        guard depth < maxDepth else {
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Maximum nesting depth (\(maxDepth)) exceeded at path: \(path)"
            )
        }

        switch expected {
        case .any:
            return value

        case .string:
            guard case .string = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            return value

        case .int:
            switch value {
            case .int:
                return value
            case let .double(d) where d.truncatingRemainder(dividingBy: 1) == 0
                && d >= Double(Int.min)
                && d <= Double(Int.max):
                return .int(Int(d))
            case let .string(s):
                if let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .int(i)
                }
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .double:
            switch value {
            case let .double(d):
                return .double(d)
            case let .int(i):
                return .double(Double(i))
            case let .string(s):
                if let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .double(d)
                }
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case .bool:
            switch value {
            case .bool:
                return value
            case let .string(s):
                switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true":
                    return .bool(true)
                case "false":
                    return .bool(false)
                default:
                    throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
                }
            default:
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }

        case let .array(elementType):
            guard case let .array(elements) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try elements.enumerated().map { index, element in
                try coerceValue(
                    toolName: toolName,
                    value: element,
                    expected: elementType,
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }
            return .array(coerced)

        case let .object(properties):
            guard case let .dictionary(dict) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            let coerced = try normalize(toolName: toolName, parameters: properties, arguments: dict, pathPrefix: path, depth: depth + 1)
            return .dictionary(coerced)

        case let .oneOf(options):
            guard case let .string(s) = value else {
                throw invalidType(toolName: toolName, path: path, expected: expected, actual: value)
            }
            if let matched = options.first(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
                return .string(matched)
            }
            throw AgentError.invalidToolArguments(
                toolName: toolName,
                reason: "Invalid value for parameter: \(path). Expected oneOf(\(options.joined(separator: ", ")))"
            )
        }
    }

    private static func invalidType(
        toolName: String,
        path: String,
        expected: ToolParameter.ParameterType,
        actual: SendableValue
    ) -> AgentError {
        AgentError.invalidToolArguments(
            toolName: toolName,
            reason: "Invalid type for parameter: \(path). Expected \(expected.description), got \(jsonTypeDescription(actual))"
        )
    }

    private static func join(_ prefix: String?, _ key: String) -> String {
        guard let prefix, !prefix.isEmpty else { return key }
        return "\(prefix).\(key)"
    }

    private static func jsonTypeDescription(_ value: SendableValue) -> String {
        switch value {
        case .null:
            "null"
        case .bool:
            "boolean"
        case .int:
            "integer"
        case .double:
            "number"
        case .string:
            "string"
        case .array:
            "array"
        case .dictionary:
            "object"
        }
    }
}
