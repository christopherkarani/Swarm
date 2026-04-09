#if canImport(ConduitAdvanced)
import ConduitAdvanced
#else
import Conduit
#endif
import Testing
@testable import Swarm

@Suite("Conduit Inference Provider Bridge")
struct ConduitInferenceProviderBridgeTests {
    @Test("Converts ToolSchema into Conduit GenerationSchema")
    func convertsToolSchema() throws {
        let schema = ToolSchema(
            name: "weather",
            description: "Gets current weather",
            parameters: [
                ToolParameter(name: "location", description: "City name", type: .string),
                ToolParameter(name: "units", description: "Units", type: .oneOf(["c", "f"]), isRequired: false)
            ]
        )

        let generationSchema = try ConduitToolSchemaConverter.generationSchema(for: schema)
        let jsonSchema = generationSchema.toJSONSchema()

        let defs = jsonSchema["$defs"] as? [String: Any]
        #expect(defs != nil)
        guard let defs else { return }

        let ref = jsonSchema["$ref"] as? String
        #expect(ref != nil)
        guard let ref else { return }

        let rootName = ref.replacingOccurrences(of: "#/$defs/", with: "")
        let root = defs[rootName] as? [String: Any]
        #expect(root != nil)
        guard let root else { return }

        let properties = root["properties"] as? [String: Any]
        #expect(properties != nil)
        guard let properties else { return }

        let location = properties["location"] as? [String: Any]
        #expect(location?["type"] as? String == "string")

        let units = properties["units"] as? [String: Any]
        if let enumValues = units?["enum"] as? [String] {
            #expect(enumValues == ["c", "f"])
        } else if let ref = units?["$ref"] as? String {
            // Conduit may lift enums into `$defs` and reference them from the property.
            let defName = ref.replacingOccurrences(of: "#/$defs/", with: "")
            let def = defs[defName] as? [String: Any]
            #expect(def?["enum"] as? [String] == ["c", "f"])
        } else {
            #expect(Bool(false), "Expected units schema to contain either `enum` or `$ref` to a definition with `enum`.")
        }

        let required = root["required"] as? [String]
        #expect(required?.contains("location") == true)
        #expect(required?.contains("units") == false)
    }

    @Test("Converts Conduit tool calls into Swarm parsed tool calls")
    func convertsToolCall() throws {
        let arguments = try GeneratedContent(json: #"{"query":"swift","limit":3}"#)
        let call = Transcript.ToolCall(id: "call_1", toolName: "search", arguments: arguments)

        let parsed = try ConduitToolCallConverter.toParsedToolCall(call)

        #expect(parsed.id == "call_1")
        #expect(parsed.name == "search")
        #expect(parsed.arguments["query"]?.stringValue == "swift")
        #expect(parsed.arguments["limit"]?.intValue == 3)
    }

    @Test("Fallback parser recovers wrapped conduit tool call from text output")
    func fallbackParserRecoversWrappedToolCall() {
        let tools = [
            ToolSchema(
                name: "websearch",
                description: "Search the web",
                parameters: [ToolParameter(name: "query", description: "Search query", type: .string)]
            )
        ]

        let content = """
        ```json
        {
          "conduit_tool_call": {
            "arguments": {
              "tool": "websearch",
              "query": "Apple Foundation Models context window"
            },
            "nonce": "B70FD653-B81C-4181-A5BC-5668A51F2BB1"
          }
        }
        ```
        """

        let parsed = ConduitPromptToolFallbackParser.parseToolCalls(
            from: content,
            availableTools: tools
        )

        #expect(parsed.count == 1)
        #expect(parsed.first?.name == "websearch")
        #expect(parsed.first?.arguments["query"] == .string("Apple Foundation Models context window"))
    }

    @Test("Fallback parser repairs truncated wrapped conduit tool call from text output")
    func fallbackParserRepairsTruncatedWrappedToolCall() {
        let tools = [
            ToolSchema(
                name: "websearch",
                description: "Search the web",
                parameters: [ToolParameter(name: "query", description: "Search query", type: .string)]
            )
        ]

        let content = """
        ```json
        {"conduit_tool_call":{"arguments":{"query":"Apple Foundation Models context window","mode":"search"},"tool":"websearch"}
        ```
        """

        let parsed = ConduitPromptToolFallbackParser.parseToolCalls(
            from: content,
            availableTools: tools
        )

        #expect(parsed.count == 1)
        #expect(parsed.first?.name == "websearch")
        #expect(parsed.first?.arguments["query"] == .string("Apple Foundation Models context window"))
        #expect(parsed.first?.arguments["mode"] == .string("search"))
    }
}
