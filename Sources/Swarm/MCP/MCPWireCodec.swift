// MCPWireCodec.swift
// Swarm Framework
//
// Shared JSON-RPC parsing and MCP result shaping for HTTP and stdio clients.

import Foundation

// MARK: - MCPWireCodec

/// Package helpers shared by ``HTTPMCPServer`` and ``StdioMCPServer``.
enum MCPWireCodec {
    // MARK: Internal

    static func requireToolName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPError.invalidParams("Tool name must be non-empty")
        }
    }

    static func parseCapabilities(from value: SendableValue) throws -> MCPCapabilities {
        guard let dict = value.dictionaryValue else {
            throw MCPError.parseError("Expected dictionary in initialize result")
        }

        let capabilitiesDict = dict["capabilities"]?.dictionaryValue ?? [:]
        return MCPCapabilities(
            tools: capabilitiesDict["tools"] != nil,
            resources: capabilitiesDict["resources"] != nil,
            prompts: false,
            sampling: false
        )
    }

    static func negotiatedVersion(from value: SendableValue) throws -> String {
        guard let dict = value.dictionaryValue else {
            throw MCPError.parseError("Expected dictionary in initialize result")
        }
        return try MCPProtocolVersion.negotiate(serverReported: extractString(dict["protocolVersion"]))
    }

    static func parseTools(from value: SendableValue) throws -> [ToolSchema] {
        guard let dict = value.dictionaryValue,
              let toolsArray = dict["tools"]?.arrayValue else {
            throw MCPError.parseError("Expected dictionary with 'tools' array in tools/list result")
        }

        var tools: [ToolSchema] = []

        for toolValue in toolsArray {
            guard let toolDict = toolValue.dictionaryValue,
                  let name = extractString(toolDict["name"]) else {
                continue
            }

            let description = extractString(toolDict["description"]) ?? ""
            let parameters = parseParameters(from: toolDict["inputSchema"])

            tools.append(ToolSchema(name: name, description: description, parameters: parameters))
        }

        return tools
    }

    static func parseResources(from value: SendableValue) throws -> [MCPResource] {
        guard let dict = value.dictionaryValue,
              let resourcesArray = dict["resources"]?.arrayValue else {
            throw MCPError.parseError("Expected dictionary with 'resources' array in resources/list result")
        }

        var resources: [MCPResource] = []

        for resourceValue in resourcesArray {
            guard let resourceDict = resourceValue.dictionaryValue,
                  let uri = extractString(resourceDict["uri"]),
                  let name = extractString(resourceDict["name"]) else {
                continue
            }

            resources.append(MCPResource(
                uri: uri,
                name: name,
                description: extractString(resourceDict["description"]),
                mimeType: extractString(resourceDict["mimeType"])
            ))
        }

        return resources
    }

    static func parseResourceContent(from value: SendableValue) throws -> MCPResourceContent {
        guard let dict = value.dictionaryValue,
              let contentsArray = dict["contents"]?.arrayValue,
              let firstContent = contentsArray.first,
              let contentDict = firstContent.dictionaryValue else {
            throw MCPError.parseError("Expected dictionary with 'contents' array in resources/read result")
        }

        return try MCPResourceContent(
            uri: extractString(contentDict["uri"]) ?? "",
            mimeType: extractString(contentDict["mimeType"]),
            text: extractString(contentDict["text"]),
            blob: extractString(contentDict["blob"])
        )
    }

    static func toolCallResult(
        _ result: SendableValue,
        toolName: String,
        style: MCPToolResultStyle
    ) throws -> SendableValue {
        guard let resultDict = result.dictionaryValue,
              resultDict["content"] != nil || resultDict["isError"] != nil else {
            return result
        }

        if resultDict["isError"]?.boolValue == true {
            let detail = toolCallErrorMessage(from: resultDict)
            throw MCPError(
                code: MCPError.internalErrorCode,
                message: "Remote MCP tool '\(toolName)' failed: \(detail)",
                data: result
            )
        }

        switch style {
        case .rawEnvelope:
            return result
        case .unwrappedContent:
            return unwrapContent(resultDict["content"])
        }
    }

    static func jsonRPCPayload(fromSSE data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPError.parseError("SSE payload was not valid UTF-8")
        }

        var payloadLines: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("data:") {
                payloadLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }

        let joined = payloadLines.filter { !$0.isEmpty }.joined(separator: "\n")
        guard !joined.isEmpty, let payload = joined.data(using: .utf8) else {
            throw MCPError.parseError("SSE stream did not contain a JSON-RPC data event")
        }
        return payload
    }

    static func initializeParameters() -> [String: SendableValue] {
        [
            "protocolVersion": .string(MCPProtocolVersion.current),
            "capabilities": .dictionary([:]),
            "clientInfo": .dictionary([
                "name": .string("Swarm"),
                "version": .string(Swarm.version)
            ])
        ]
    }

    // MARK: Private

    private static func parseParameters(from schema: SendableValue?) -> [ToolParameter] {
        guard let schemaDict = schema?.dictionaryValue else {
            return []
        }
        return parseObjectProperties(from: schemaDict)
    }

    private static func parseObjectProperties(from schemaDict: [String: SendableValue]) -> [ToolParameter] {
        guard let properties = schemaDict["properties"]?.dictionaryValue else {
            return []
        }

        let requiredSet = Set(schemaDict["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        var parameters: [ToolParameter] = []

        for (name, propValue) in properties {
            guard let propDict = propValue.dictionaryValue else { continue }

            parameters.append(ToolParameter(
                name: name,
                description: extractString(propDict["description"]) ?? "",
                type: parseParameterType(from: propDict),
                isRequired: requiredSet.contains(name),
                defaultValue: propDict["default"]
            ))
        }

        return parameters
    }

    private static func parseParameterType(from schemaDict: [String: SendableValue]) -> ToolParameter.ParameterType {
        if let options = parseStringOptions(from: schemaDict), !options.isEmpty {
            return .oneOf(options)
        }

        let typeString = extractString(schemaDict["type"]) ?? inferredTypeString(from: schemaDict)

        switch typeString.lowercased() {
        case "string":
            return .string
        case "integer":
            return .int
        case "number":
            return .double
        case "boolean":
            return .bool
        case "array":
            if let itemsDict = schemaDict["items"]?.dictionaryValue {
                return .array(elementType: parseParameterType(from: itemsDict))
            }
            return .array(elementType: .any)
        case "object":
            return .object(properties: parseObjectProperties(from: schemaDict))
        default:
            return .any
        }
    }

    private static func inferredTypeString(from schemaDict: [String: SendableValue]) -> String {
        if schemaDict["properties"]?.dictionaryValue != nil {
            return "object"
        }
        if schemaDict["items"]?.dictionaryValue != nil {
            return "array"
        }
        return "any"
    }

    private static func parseStringOptions(from schemaDict: [String: SendableValue]) -> [String]? {
        if let values = schemaDict["enum"]?.arrayValue?.compactMap(\.stringValue), !values.isEmpty {
            return values
        }

        guard let oneOf = schemaDict["oneOf"]?.arrayValue else {
            return nil
        }

        let values = oneOf.flatMap { option -> [String] in
            guard let optionDict = option.dictionaryValue else {
                return []
            }
            if let constValue = optionDict["const"]?.stringValue {
                return [constValue]
            }
            return optionDict["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        }
        return values.isEmpty ? nil : values
    }

    private static func unwrapContent(_ content: SendableValue?) -> SendableValue {
        guard let items = content?.arrayValue else {
            return content ?? .null
        }

        if items.count == 1, let only = items.first {
            if let text = only.dictionaryValue?["text"]?.stringValue {
                let type = only.dictionaryValue?["type"]?.stringValue
                if type == nil || type == "text" {
                    return .string(text)
                }
            }
            return only
        }

        return .array(items)
    }

    private static func toolCallErrorMessage(from resultDict: [String: SendableValue]) -> String {
        guard let content = resultDict["content"]?.arrayValue else {
            return "tool returned isError"
        }

        let textParts = content.compactMap { item -> String? in
            item.dictionaryValue?["text"]?.stringValue
        }

        return textParts.isEmpty ? "tool returned isError" : textParts.joined(separator: "\n")
    }

    private static func extractString(_ value: SendableValue?) -> String? {
        value?.stringValue
    }
}
