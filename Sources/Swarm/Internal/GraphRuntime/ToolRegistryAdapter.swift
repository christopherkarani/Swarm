#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

enum ToolRegistryAdapterError: Error, Equatable, Sendable {
    case invalidArgumentsJSON
    case argumentsMustBeJSONObject
    case resultEncodingFailed
    case schemaEncodingFailed
    case toolNotFound(name: String)
    case toolInvocationFailed(name: String, reason: String)
    case duplicateToolName(String)
}

/// Bridges Swarm tools into HiveCore's `HiveToolRegistry` interface.
///
/// This adapter snapshots tools at initialization time so `listTools()` can remain synchronous.
struct ToolRegistryAdapter: HiveToolRegistry, Sendable {
    private let registry: ToolRegistry
    private let toolDefinitions: [HiveToolDefinition]

    init(tools: [any AnyJSONTool]) throws {
        let registry: ToolRegistry
        do {
            registry = try ToolRegistry(tools: tools)
        } catch let error as ToolRegistryError {
            switch error {
            case .duplicateToolName(let name):
                throw ToolRegistryAdapterError.duplicateToolName(name)
            }
        }
        self.registry = registry
        self.toolDefinitions = try tools
            .map { try Self.makeToolDefinition(for: $0.schema) }
            .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
    }

    static func fromRegistry(_ registry: ToolRegistry) async throws -> Self {
        let schemas = await registry.schemas
        let definitions = try schemas
            .map { try Self.makeToolDefinition(for: $0) }
            .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        return ToolRegistryAdapter(registry: registry, toolDefinitions: definitions)
    }

    func listTools() -> [HiveToolDefinition] {
        toolDefinitions
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        let arguments = try Self.parseArgumentsJSON(call.argumentsJSON)

        guard await registry.contains(named: call.name) else {
            throw ToolRegistryAdapterError.toolNotFound(name: call.name)
        }

        do {
            let output = try await registry.execute(toolNamed: call.name, arguments: arguments)
            let content = try Self.encodeJSONFragment(output)
            return HiveToolResult(toolCallID: call.id, content: content)
        } catch let error as CancellationError {
            throw error
        } catch let error as AgentError {
            switch error {
            case let .toolNotFound(name):
                throw ToolRegistryAdapterError.toolNotFound(name: name)
            case let .toolExecutionFailed(toolName, underlyingError):
                throw ToolRegistryAdapterError.toolInvocationFailed(name: toolName, reason: underlyingError)
            case let .invalidToolArguments(toolName, reason):
                throw ToolRegistryAdapterError.toolInvocationFailed(name: toolName, reason: reason)
            default:
                throw ToolRegistryAdapterError.toolInvocationFailed(name: call.name, reason: error.localizedDescription)
            }
        } catch {
            if let guardrailError = error as? GuardrailError {
                throw guardrailError
            }
            throw ToolRegistryAdapterError.toolInvocationFailed(
                name: call.name,
                reason: error.localizedDescription
            )
        }
    }
}

extension ToolRegistryAdapter {
    private init(registry: ToolRegistry, toolDefinitions: [HiveToolDefinition]) {
        self.registry = registry
        self.toolDefinitions = toolDefinitions
    }

    private static func parseArgumentsJSON(_ json: String) throws -> [String: SendableValue] {
        guard let data = json.data(using: .utf8) else {
            throw ToolRegistryAdapterError.invalidArgumentsJSON
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ToolRegistryAdapterError.invalidArgumentsJSON
        }
        guard let dict = jsonObject as? [String: Any] else {
            throw ToolRegistryAdapterError.argumentsMustBeJSONObject
        }

        var result: [String: SendableValue] = [:]
        for (key, value) in dict {
            result[key] = SendableValue.fromJSONValue(value)
        }
        return result
    }

    private static func encodeJSONFragment(_ value: SendableValue) throws -> String {
        if case let .string(s) = value {
            return s
        }
        let object = value.toJSONObject()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ToolRegistryAdapterError.resultEncodingFailed
        }
        return json
    }

    private static func makeToolDefinition(for schema: ToolSchema) throws -> HiveToolDefinition {
        let schemaObject = makeParametersSchema(toolName: schema.name, parameters: schema.parameters)
        let data = try JSONSerialization.data(withJSONObject: schemaObject, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ToolRegistryAdapterError.schemaEncodingFailed
        }
        return HiveToolDefinition(
            name: schema.name,
            description: schema.description,
            parametersJSONSchema: json
        )
    }

    private static func makeParametersSchema(toolName: String, parameters: [ToolParameter]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for parameter in parameters {
            var schema = jsonSchema(for: parameter.type)
            schema["description"] = parameter.description
            if let defaultValue = parameter.defaultValue {
                schema["default"] = defaultValue.toJSONObject()
            }
            properties[parameter.name] = schema
            if parameter.isRequired, parameter.defaultValue == nil {
                required.append(parameter.name)
            }
        }

        required.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

        var root: [String: Any] = [
            "type": "object",
            "description": "Tool parameters for \(toolName)",
            "properties": properties,
            "additionalProperties": false
        ]

        if !required.isEmpty {
            root["required"] = required
        }

        return root
    }

    private static func jsonSchema(for type: ToolParameter.ParameterType) -> [String: Any] {
        switch type {
        case .string:
            return ["type": "string"]
        case .int:
            return ["type": "integer"]
        case .double:
            return ["type": "number"]
        case .bool:
            return ["type": "boolean"]
        case .array(let elementType):
            return [
                "type": "array",
                "items": jsonSchema(for: elementType)
            ]
        case .object(let properties):
            var props: [String: Any] = [:]
            var required: [String] = []
            for property in properties {
                var schema = jsonSchema(for: property.type)
                schema["description"] = property.description
                if let defaultValue = property.defaultValue {
                    schema["default"] = defaultValue.toJSONObject()
                }
                props[property.name] = schema
                if property.isRequired, property.defaultValue == nil {
                    required.append(property.name)
                }
            }

            required.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

            var object: [String: Any] = [
                "type": "object",
                "properties": props,
                "additionalProperties": false
            ]
            if !required.isEmpty {
                object["required"] = required
            }
            return object
        case .oneOf(let options):
            return [
                "type": "string",
                "enum": options
            ]
        case .any:
            return [
                "anyOf": [
                    ["type": "string"],
                    ["type": "number"],
                    ["type": "integer"],
                    ["type": "boolean"],
                    ["type": "object"],
                    ["type": "array"]
                ]
            ]
        }
    }
}
#endif
