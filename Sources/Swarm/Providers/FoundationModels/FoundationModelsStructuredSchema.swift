// FoundationModelsStructuredSchema.swift
// Swarm Framework
//
// Pure JSON Schema → GenerationSchema subset mapping. No FoundationModels
// import: Linux CI can assert supported vs unsupported constructs.

import Foundation

/// Intermediate representation of a JSON Schema that Foundation Models
/// `GenerationSchema` can express.
///
/// Built by ``FoundationModelsStructuredSchemaMapping`` so the Apple-only
/// conversion in ``FoundationModelsSchemaConversion`` stays a mechanical
/// lowering of this tree.
struct FoundationModelsMappedGenerationSchema: Sendable, Equatable {
    var name: String
    var description: String?
    var properties: [FoundationModelsMappedProperty]
    /// When non-nil, this named schema is a string enum (`anyOf` choices) rather than an object.
    var stringEnum: [String]?
    var definitions: [FoundationModelsMappedGenerationSchema]
}

struct FoundationModelsMappedProperty: Sendable, Equatable {
    var name: String
    var description: String?
    var isOptional: Bool
    var type: FoundationModelsMappedType
}

indirect enum FoundationModelsMappedType: Sendable, Equatable {
    case string
    case integer
    case number
    case boolean
    case stringEnum([String])
    case array(element: FoundationModelsMappedType, minItems: Int?, maxItems: Int?)
    case object(FoundationModelsMappedGenerationSchema)
    case reference(String)
}

/// Evaluates whether a Swarm structured-output request maps onto Apple
/// Foundation Models guided generation.
///
/// ## Supported subset
///
/// Native `GenerationSchema` is used only when the request is
/// ``StructuredOutputFormat/jsonSchema(name:schemaJSON:)`` and the schema is a
/// **closed object** whose constraints GenerationSchema can enforce:
///
/// - Root `type: object` with `properties` (and optional `required`)
/// - Property types: `string`, `integer`, `number`, `boolean`
/// - Nested objects and arrays (`items` as a single schema)
/// - `enum` of strings (maps to `anyOf` choices)
/// - `minItems` / `maxItems` on arrays
/// - Local `$ref` to root `$defs` / `definitions` (object or string-enum targets)
/// - `additionalProperties: false` (or omitted — guided generation already
///   forbids extra keys, which still validates against an open JSON Schema)
/// - Metadata ignored: `$schema`, `$id`, `$comment`, `title`, `description`,
///   `default`, `examples`, `deprecated`
///
/// ## Explicitly unsupported
///
/// ``StructuredOutputFormat/jsonObject`` has no schema, so it cannot be guided
/// and stays prompt-instruction + parse. Also rejected (honest
/// ``StructuredOutputResult/Source/promptFallback``):
///
/// - `additionalProperties: true` or a nested schema (free-form keys)
/// - `pattern`, `format`, `minLength`, `maxLength`
/// - numeric `minimum` / `maximum` / `exclusive*` / `multipleOf`
/// - `oneOf` / `anyOf` / `allOf` / `not` / `if` / `then` / `else`
/// - `const`, `uniqueItems`, tuple `items` / `prefixItems`
/// - type unions (`type` as an array), remote `$ref`, unknown keywords
enum FoundationModelsStructuredSchemaMapping: Sendable, Equatable {
    case mapped(FoundationModelsMappedGenerationSchema)
    case unsupported(Reason)

    enum Reason: Error, Sendable, Equatable, CustomStringConvertible {
        case jsonObjectHasNoSchema
        case invalidSchemaJSON(String)
        case rootMustBeObject
        case unsupportedKeyword(String, path: String)
        case unsupportedType(String, path: String)
        case invalidEnum(path: String)
        case unresolvedReference(String)
        case invalidReference(String)
        case additionalProperties(path: String)
        case emptyProperties(path: String)

        var description: String {
            switch self {
            case .jsonObjectHasNoSchema:
                "jsonObject has no schema; Foundation Models GenerationSchema cannot constrain a free-form object"
            case let .invalidSchemaJSON(detail):
                "schemaJSON is not valid JSON: \(detail)"
            case .rootMustBeObject:
                "root schema must be type: object with properties"
            case let .unsupportedKeyword(keyword, path):
                "unsupported JSON Schema keyword '\(keyword)' at \(path)"
            case let .unsupportedType(type, path):
                "unsupported JSON Schema type '\(type)' at \(path)"
            case let .invalidEnum(path):
                "enum at \(path) must be an array of strings"
            case let .unresolvedReference(ref):
                "unresolved $ref '\(ref)'"
            case let .invalidReference(ref):
                "$ref '\(ref)' is not a local #/$defs or #/definitions pointer"
            case let .additionalProperties(path):
                "additionalProperties at \(path) enables free-form keys that GenerationSchema cannot express"
            case let .emptyProperties(path):
                "object at \(path) has no properties; GenerationSchema cannot express a free-form object"
            }
        }
    }

    static func evaluate(_ request: StructuredOutputRequest) -> Self {
        switch request.format {
        case .jsonObject:
            return .unsupported(.jsonObjectHasNoSchema)
        case let .jsonSchema(name, schemaJSON):
            return evaluate(name: name, schemaJSON: schemaJSON)
        }
    }

    static func evaluate(name: String, schemaJSON: String) -> Self {
        let trimmed = schemaJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return .unsupported(.invalidSchemaJSON("not valid UTF-8"))
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .unsupported(.invalidSchemaJSON(error.localizedDescription))
        }

        guard let root = raw as? [String: Any] else {
            return .unsupported(.rootMustBeObject)
        }

        do {
            let mapped = try Parser(rootName: name).parseRoot(root)
            return .mapped(mapped)
        } catch let reason as Reason {
            return .unsupported(reason)
        } catch {
            return .unsupported(.invalidSchemaJSON(String(describing: error)))
        }
    }
}

// MARK: - Parser

private struct Parser {
    let rootName: String
    private var definitionNames: Set<String> = []

    init(rootName: String) {
        self.rootName = rootName
    }

    func parseRoot(_ node: [String: Any]) throws -> FoundationModelsMappedGenerationSchema {
        try rejectUnknownKeys(in: node, path: "$")
        try rejectOpenAdditionalProperties(in: node, path: "$")

        var parser = self
        let definitions = try parser.parseDefinitions(from: node)
        parser.definitionNames = Set(definitions.map(\.name))

        let object = try parser.parseObjectSchema(
            node,
            name: rootName,
            path: "$"
        )
        return FoundationModelsMappedGenerationSchema(
            name: object.name,
            description: object.description,
            properties: object.properties,
            stringEnum: object.stringEnum,
            definitions: definitions
        )
    }

    private mutating func parseDefinitions(
        from node: [String: Any]
    ) throws -> [FoundationModelsMappedGenerationSchema] {
        let defsNode: [String: Any]
        if let defs = node["$defs"] as? [String: Any] {
            if node["definitions"] != nil {
                throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedKeyword(
                    "definitions",
                    path: "$"
                )
            }
            defsNode = defs
        } else if let defs = node["definitions"] as? [String: Any] {
            defsNode = defs
        } else {
            return []
        }

        definitionNames = Set(defsNode.keys.map(FoundationModelsGenerationTypeName.sanitize))
        var result: [FoundationModelsMappedGenerationSchema] = []
        result.reserveCapacity(defsNode.count)
        for key in defsNode.keys.sorted() {
            guard let defNode = defsNode[key] as? [String: Any] else {
                throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType(
                    "non-object definition",
                    path: "$/$defs/\(key)"
                )
            }
            try rejectUnknownKeys(in: defNode, path: "$/$defs/\(key)")
            let mapped: FoundationModelsMappedGenerationSchema
            if defNode["enum"] != nil, defNode["properties"] == nil {
                guard case let .stringEnum(values) = try parseStringEnum(
                    defNode["enum"] as Any,
                    path: "$/$defs/\(key)"
                ) else {
                    throw FoundationModelsStructuredSchemaMapping.Reason.invalidEnum(
                        path: "$/$defs/\(key)"
                    )
                }
                mapped = FoundationModelsMappedGenerationSchema(
                    name: FoundationModelsGenerationTypeName.sanitize(key),
                    description: defNode["description"] as? String,
                    properties: [],
                    stringEnum: values,
                    definitions: []
                )
            } else {
                mapped = try parseObjectSchema(
                    defNode,
                    name: FoundationModelsGenerationTypeName.sanitize(key),
                    path: "$/$defs/\(key)"
                )
            }
            result.append(mapped)
        }
        return result
    }

    private func parseObjectSchema(
        _ node: [String: Any],
        name: String,
        path: String
    ) throws -> FoundationModelsMappedGenerationSchema {
        if path != "$", node["$defs"] != nil || node["definitions"] != nil {
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedKeyword(
                "$defs",
                path: path
            )
        }

        try rejectOpenAdditionalProperties(in: node, path: path)

        if node["$ref"] != nil {
            try rejectRefComposition(in: node, path: path)
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType(
                "$ref as whole object schema",
                path: path
            )
        }

        let type = jsonType(of: node)
        if let type, type != "object" {
            throw FoundationModelsStructuredSchemaMapping.Reason.rootMustBeObject
        }

        guard let propertiesNode = node["properties"] as? [String: Any], !propertiesNode.isEmpty else {
            throw FoundationModelsStructuredSchemaMapping.Reason.emptyProperties(path: path)
        }

        let required = Set((node["required"] as? [Any] ?? []).compactMap { $0 as? String })
        var properties: [FoundationModelsMappedProperty] = []
        properties.reserveCapacity(propertiesNode.count)
        for key in propertiesNode.keys.sorted() {
            guard let propertyNode = propertiesNode[key] as? [String: Any] else {
                throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType(
                    "non-object property schema",
                    path: "\(path).properties.\(key)"
                )
            }
            let propertyPath = "\(path).properties.\(key)"
            try rejectUnknownKeys(in: propertyNode, path: propertyPath)
            properties.append(
                FoundationModelsMappedProperty(
                    name: key,
                    description: propertyNode["description"] as? String,
                    isOptional: !required.contains(key),
                    type: try parseType(
                        propertyNode,
                        path: propertyPath,
                        anonymousName: "\(name)_\(key)"
                    )
                )
            )
        }

        return FoundationModelsMappedGenerationSchema(
            name: FoundationModelsGenerationTypeName.sanitize(name),
            description: node["description"] as? String ?? node["title"] as? String,
            properties: properties,
            stringEnum: nil,
            definitions: []
        )
    }

    private func parseType(
        _ node: [String: Any],
        path: String,
        anonymousName: String
    ) throws -> FoundationModelsMappedType {
        try rejectUnknownKeys(in: node, path: path)

        if let ref = node["$ref"] as? String {
            try rejectRefComposition(in: node, path: path)
            return try .reference(resolveReference(ref))
        }

        if let enumValues = node["enum"] {
            return try parseStringEnum(enumValues, path: path)
        }

        try rejectOpenAdditionalProperties(in: node, path: path)

        switch jsonType(of: node) {
        case "string":
            return .string
        case "integer":
            return .integer
        case "number":
            return .number
        case "boolean":
            return .boolean
        case "array":
            return try parseArray(node, path: path, anonymousName: anonymousName)
        case "object", .none:
            if node["properties"] != nil {
                let nested = try parseObjectSchema(
                    node,
                    name: anonymousName,
                    path: path
                )
                return .object(nested)
            }
            if jsonType(of: node) == "object" {
                throw FoundationModelsStructuredSchemaMapping.Reason.emptyProperties(path: path)
            }
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType(
                jsonType(of: node) ?? "missing",
                path: path
            )
        case let .some(other):
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType(other, path: path)
        }
    }

    private func parseArray(
        _ node: [String: Any],
        path: String,
        anonymousName: String
    ) throws -> FoundationModelsMappedType {
        guard let items = node["items"] as? [String: Any] else {
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType(
                "array without object items schema",
                path: path
            )
        }
        let element = try parseType(
            items,
            path: "\(path).items",
            anonymousName: "\(anonymousName)_Element"
        )
        return .array(
            element: element,
            minItems: intValue(node["minItems"]),
            maxItems: intValue(node["maxItems"])
        )
    }

    private func parseStringEnum(_ raw: Any, path: String) throws -> FoundationModelsMappedType {
        guard let values = raw as? [Any], !values.isEmpty else {
            throw FoundationModelsStructuredSchemaMapping.Reason.invalidEnum(path: path)
        }
        var strings: [String] = []
        strings.reserveCapacity(values.count)
        for value in values {
            guard let string = value as? String else {
                throw FoundationModelsStructuredSchemaMapping.Reason.invalidEnum(path: path)
            }
            strings.append(string)
        }
        return .stringEnum(strings)
    }

    private func resolveReference(_ ref: String) throws -> String {
        let prefix: String
        if ref.hasPrefix("#/$defs/") {
            prefix = "#/$defs/"
        } else if ref.hasPrefix("#/definitions/") {
            prefix = "#/definitions/"
        } else {
            throw FoundationModelsStructuredSchemaMapping.Reason.invalidReference(ref)
        }
        let name = FoundationModelsGenerationTypeName.sanitize(String(ref.dropFirst(prefix.count)))
        guard !name.isEmpty, definitionNames.contains(name) else {
            throw FoundationModelsStructuredSchemaMapping.Reason.unresolvedReference(ref)
        }
        return name
    }

    private func rejectRefComposition(in node: [String: Any], path: String) throws {
        for keyword in ["type", "properties", "items", "enum", "required"] where node[keyword] != nil {
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedKeyword(keyword, path: path)
        }
    }

    private func rejectOpenAdditionalProperties(in node: [String: Any], path: String) throws {
        guard let additional = node["additionalProperties"] else { return }
        if let flag = additional as? Bool {
            if flag {
                throw FoundationModelsStructuredSchemaMapping.Reason.additionalProperties(path: path)
            }
            return
        }
        if additional is [String: Any] {
            throw FoundationModelsStructuredSchemaMapping.Reason.additionalProperties(path: path)
        }
        throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedKeyword(
            "additionalProperties",
            path: path
        )
    }

    private func rejectUnknownKeys(in node: [String: Any], path: String) throws {
        for key in node.keys where !Self.allowedKeys.contains(key) {
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedKeyword(key, path: path)
        }
        if node["type"] is [Any] {
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedType("union", path: path)
        }
        if node["items"] is [Any] {
            throw FoundationModelsStructuredSchemaMapping.Reason.unsupportedKeyword("prefixItems", path: path)
        }
    }

    private func jsonType(of node: [String: Any]) -> String? {
        node["type"] as? String
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let int = raw as? Int { return int }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }

    static let allowedKeys: Set<String> = [
        "$schema", "$id", "$comment", "title", "description", "default", "examples", "deprecated",
        "type", "properties", "required", "additionalProperties", "items", "enum",
        "$defs", "definitions", "$ref",
        "minItems", "maxItems",
    ]
}

/// Sanitizes JSON Schema type names for Foundation Models `GenerationSchema`.
enum FoundationModelsGenerationTypeName {
    static func sanitize(_ raw: String) -> String {
        let filtered = raw.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        var name = String(filtered)
        if name.isEmpty || name.first?.isNumber == true {
            name = "T_\(name)"
        }
        return name
    }
}
