// FoundationModelsSchemaConversion.swift
// Swarm Framework
//
// Converts Swarm tool schemas into Foundation Models GenerationSchema values.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
enum FoundationModelsSchemaConversion {
    /// Builds a guided-generation schema from a mapped structured-output request.
    ///
    /// Call ``FoundationModelsStructuredSchemaMapping/evaluate(_:)`` first; this
    /// lowering is mechanical and throws only if Apple rejects the tree.
    static func generationSchema(
        from mapped: FoundationModelsMappedGenerationSchema
    ) throws -> GenerationSchema {
        let dependencies = try mapped.definitions.map { definition in
            try namedDynamicSchema(definition, typeName: definition.name)
        }
        let root = try namedDynamicSchema(mapped, typeName: mapped.name)
        return try GenerationSchema(root: root, dependencies: dependencies)
    }

    /// Builds a guided-generation schema for a structured-output request, or throws
    /// if the request is outside the supported GenerationSchema subset.
    static func generationSchema(for request: StructuredOutputRequest) throws -> GenerationSchema {
        switch FoundationModelsStructuredSchemaMapping.evaluate(request) {
        case let .mapped(mapped):
            return try generationSchema(from: mapped)
        case let .unsupported(reason):
            throw reason
        }
    }

    /// Builds a guided-generation schema for a Swarm tool's argument object.
    static func argumentSchema(for tool: ToolSchema) throws -> GenerationSchema {
        let properties = tool.parameters.map { parameter in
            DynamicGenerationSchema.Property(
                name: parameter.name,
                description: parameter.description,
                schema: dynamicSchema(for: parameter.type, name: "\(tool.name)_\(parameter.name)"),
                isOptional: !parameter.isRequired
            )
        }

        let root = DynamicGenerationSchema(
            name: sanitizeTypeName("\(tool.name)_Arguments"),
            description: "Arguments for \(tool.name)",
            properties: properties
        )

        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Converts a Foundation Models `GeneratedContent` tree into Swarm `SendableValue`s.
    static func sendableValue(from content: GeneratedContent) -> SendableValue {
        switch content.kind {
        case .null:
            return .null
        case let .bool(value):
            return .bool(value)
        case let .number(value):
            if value.rounded() == value,
               value >= Double(Int.min),
               value <= Double(Int.max)
            {
                return .int(Int(value))
            }
            return .double(value)
        case let .string(value):
            return .string(value)
        case let .array(values):
            return .array(values.map(sendableValue(from:)))
        case let .structure(properties, orderedKeys):
            var dictionary: [String: SendableValue] = [:]
            dictionary.reserveCapacity(orderedKeys.count)
            for key in orderedKeys {
                if let value = properties[key] {
                    dictionary[key] = sendableValue(from: value)
                }
            }
            // Include any keys omitted from orderedKeys for resilience.
            for (key, value) in properties where dictionary[key] == nil {
                dictionary[key] = sendableValue(from: value)
            }
            return .dictionary(dictionary)
        @unknown default:
            return .string(String(describing: content))
        }
    }

    /// Extracts a dictionary of tool arguments from generated content.
    static func argumentDictionary(from content: GeneratedContent) -> [String: SendableValue] {
        let value = sendableValue(from: content)
        if case let .dictionary(dictionary) = value {
            return dictionary
        }
        // Some models may surface a bare scalar when the tool has a single required field.
        return ["value": value]
    }

    /// Converts Swarm `SendableValue`s into a Foundation Models `GeneratedContent` tree.
    static func generatedContent(from dictionary: [String: SendableValue]) -> GeneratedContent {
        generatedContent(from: .dictionary(dictionary))
    }

    /// Converts a Swarm `SendableValue` into Foundation Models `GeneratedContent`.
    static func generatedContent(from value: SendableValue) -> GeneratedContent {
        switch value {
        case .null:
            return GeneratedContent(kind: .null)
        case let .bool(bool):
            return GeneratedContent(kind: .bool(bool))
        case let .int(int):
            return GeneratedContent(kind: .number(Double(int)))
        case let .double(double):
            return GeneratedContent(kind: .number(double))
        case let .string(string):
            return GeneratedContent(kind: .string(string))
        case let .array(values):
            return GeneratedContent(kind: .array(values.map(generatedContent(from:))))
        case let .dictionary(dictionary):
            let keys = dictionary.keys.sorted()
            var properties: [String: GeneratedContent] = [:]
            properties.reserveCapacity(keys.count)
            for key in keys {
                if let nested = dictionary[key] {
                    properties[key] = generatedContent(from: nested)
                }
            }
            return GeneratedContent(kind: .structure(properties: properties, orderedKeys: keys))
        }
    }

    // MARK: - Private

    private static func dynamicSchema(
        for type: ToolParameter.ParameterType,
        name: String
    ) -> DynamicGenerationSchema {
        switch type {
        case .string, .any:
            return DynamicGenerationSchema(type: String.self)
        case .int:
            return DynamicGenerationSchema(type: Int.self)
        case .double:
            return DynamicGenerationSchema(type: Double.self)
        case .bool:
            return DynamicGenerationSchema(type: Bool.self)
        case let .array(elementType):
            return DynamicGenerationSchema(
                arrayOf: dynamicSchema(for: elementType, name: "\(name)_Element")
            )
        case let .object(properties):
            let nested = properties.map { parameter in
                DynamicGenerationSchema.Property(
                    name: parameter.name,
                    description: parameter.description,
                    schema: dynamicSchema(for: parameter.type, name: "\(name)_\(parameter.name)"),
                    isOptional: !parameter.isRequired
                )
            }
            return DynamicGenerationSchema(
                name: sanitizeTypeName(name),
                description: nil,
                properties: nested
            )
        case let .oneOf(options):
            return DynamicGenerationSchema(
                name: sanitizeTypeName(name),
                description: nil,
                anyOf: options
            )
        }
    }

    private static func namedDynamicSchema(
        _ mapped: FoundationModelsMappedGenerationSchema,
        typeName: String
    ) throws -> DynamicGenerationSchema {
        if let values = mapped.stringEnum {
            return DynamicGenerationSchema(
                name: sanitizeTypeName(typeName),
                description: mapped.description,
                anyOf: values
            )
        }
        let properties = try mapped.properties.map { property in
            DynamicGenerationSchema.Property(
                name: property.name,
                description: property.description,
                schema: try dynamicSchema(for: property.type, name: "\(typeName)_\(property.name)"),
                isOptional: property.isOptional
            )
        }
        return DynamicGenerationSchema(
            name: sanitizeTypeName(typeName),
            description: mapped.description,
            properties: properties
        )
    }

    private static func dynamicSchema(
        for type: FoundationModelsMappedType,
        name: String
    ) throws -> DynamicGenerationSchema {
        switch type {
        case .string:
            return DynamicGenerationSchema(type: String.self)
        case .integer:
            return DynamicGenerationSchema(type: Int.self)
        case .number:
            return DynamicGenerationSchema(type: Double.self)
        case .boolean:
            return DynamicGenerationSchema(type: Bool.self)
        case let .stringEnum(values):
            return DynamicGenerationSchema(
                name: sanitizeTypeName(name),
                description: nil,
                anyOf: values
            )
        case let .array(element, minItems, maxItems):
            return DynamicGenerationSchema(
                arrayOf: try dynamicSchema(for: element, name: "\(name)_Element"),
                minimumElements: minItems,
                maximumElements: maxItems
            )
        case let .object(schema):
            return try namedDynamicSchema(schema, typeName: schema.name)
        case let .reference(refName):
            return DynamicGenerationSchema(referenceTo: sanitizeTypeName(refName))
        }
    }

    static func sanitizeTypeName(_ raw: String) -> String {
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
#endif
