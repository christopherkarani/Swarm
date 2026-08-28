#if SWARM_MCP
import Foundation
import MCP
import Swarm

enum SwarmMCPToolMapper {
    static func mapSchemas(_ schemas: [ToolSchema]) -> [MCP.Tool] {
        schemas
            .sorted { lhs, rhs in
                lhs.name < rhs.name
            }
            .map(mapSchema(_:))
    }

    static func mapSchema(_ schema: ToolSchema) -> MCP.Tool {
        MCP.Tool(
            name: schema.name,
            description: schema.description,
            inputSchema: buildInputSchema(from: schema.parameters)
        )
    }

    static func buildInputSchema(from parameters: [ToolParameter]) -> Value {
        let sorted = parameters.sorted { $0.name < $1.name }
        let properties = propertiesMap(from: sorted)
        let required = requiredFields(from: sorted)

        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required),
            "additionalProperties": .bool(false),
        ])
    }

    private static func parameterSchema(for parameter: ToolParameter) -> Value {
        var schema = jsonSchema(for: parameter.type)
        guard case var .object(map) = schema else {
            return schema
        }

        map["description"] = .string(parameter.description)
        if let defaultValue = parameter.defaultValue {
            map["default"] = SwarmMCPValueMapper.mcpValue(from: defaultValue)
        }

        schema = .object(map)
        return schema
    }

    private static func jsonSchema(for type: ToolParameter.ParameterType) -> Value {
        switch type {
        case .string:
            return .object(["type": .string("string")])
        case .int:
            return .object(["type": .string("integer")])
        case .double:
            return .object(["type": .string("number")])
        case .bool:
            return .object(["type": .string("boolean")])
        case let .array(elementType):
            return .object([
                "type": .string("array"),
                "items": jsonSchema(for: elementType),
            ])
        case let .object(properties):
            let sorted = properties.sorted { $0.name < $1.name }
            return .object([
                "type": .string("object"),
                "properties": .object(propertiesMap(from: sorted)),
                "required": .array(requiredFields(from: sorted)),
                "additionalProperties": .bool(false),
            ])
        case let .oneOf(options):
            return .object([
                "type": .string("string"),
                "enum": .array(options.sorted().map(Value.string)),
            ])
        case .any:
            return .object([:])
        }
    }

    private static func propertiesMap(from parameters: [ToolParameter]) -> [String: Value] {
        // Duplicate parameter names should not crash mapping; the last deterministic
        // entry for a key wins after sorting.
        var output: [String: Value] = [:]
        for parameter in parameters {
            output[parameter.name] = parameterSchema(for: parameter)
        }
        return output
    }

    private static func requiredFields(from parameters: [ToolParameter]) -> [Value] {
        Array(Set(parameters.filter(\.isRequired).map(\.name)))
            .sorted()
            .map(Value.string)
    }
}
#endif
