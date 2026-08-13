import Foundation
@testable import Swarm
import Testing

@Suite("FoundationModels Structured Schema Mapping")
struct FoundationModelsStructuredSchemaMappingTests {
    @Test("jsonObject has no schema and cannot be guided")
    func jsonObjectIsUnsupported() {
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonObject)
        )
        #expect(result == .unsupported(.jsonObjectHasNoSchema))
    }

    @Test("Closed object with string, integer, number, boolean maps")
    func closedObjectScalarsMap() throws {
        let schema = """
        {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "Display name" },
            "count": { "type": "integer" },
            "score": { "type": "number" },
            "ok": { "type": "boolean" }
          },
          "required": ["name", "ok"]
        }
        """
        let mapped = try #require(mappedSchema(name: "Answer", json: schema))
        #expect(mapped.name == "Answer")
        #expect(mapped.properties.map(\.name) == ["count", "name", "ok", "score"])
        #expect(mapped.properties.first { $0.name == "name" }?.isOptional == false)
        #expect(mapped.properties.first { $0.name == "count" }?.isOptional == true)
        #expect(mapped.properties.first { $0.name == "name" }?.type == .string)
        #expect(mapped.properties.first { $0.name == "count" }?.type == .integer)
        #expect(mapped.properties.first { $0.name == "score" }?.type == .number)
        #expect(mapped.properties.first { $0.name == "ok" }?.type == .boolean)
    }

    @Test("Nested object and array of objects map")
    func nestedObjectAndArrayMap() throws {
        let schema = """
        {
          "type": "object",
          "properties": {
            "tags": { "type": "array", "items": { "type": "string" }, "minItems": 1, "maxItems": 5 },
            "address": {
              "type": "object",
              "properties": { "city": { "type": "string" } },
              "required": ["city"],
              "additionalProperties": false
            }
          },
          "required": ["tags"]
        }
        """
        let mapped = try #require(mappedSchema(name: "Place", json: schema))
        guard case let .array(element, minItems, maxItems) = mapped.properties.first(where: { $0.name == "tags" })?.type else {
            Issue.record("expected array tags")
            return
        }
        #expect(element == .string)
        #expect(minItems == 1)
        #expect(maxItems == 5)

        guard case let .object(address) = mapped.properties.first(where: { $0.name == "address" })?.type else {
            Issue.record("expected nested address object")
            return
        }
        #expect(address.properties.map(\.name) == ["city"])
    }

    @Test("String enum maps")
    func stringEnumMaps() throws {
        let schema = """
        {
          "type": "object",
          "properties": {
            "status": { "enum": ["open", "closed"] }
          },
          "required": ["status"]
        }
        """
        let mapped = try #require(mappedSchema(name: "Ticket", json: schema))
        #expect(mapped.properties.first?.type == .stringEnum(["open", "closed"]))
    }

    @Test("Local $ref to $defs object maps")
    func localRefToDefsMaps() throws {
        let schema = """
        {
          "type": "object",
          "properties": {
            "home": { "$ref": "#/$defs/Address" }
          },
          "required": ["home"],
          "$defs": {
            "Address": {
              "type": "object",
              "properties": { "city": { "type": "string" } },
              "required": ["city"]
            }
          }
        }
        """
        let mapped = try #require(mappedSchema(name: "Person", json: schema))
        #expect(mapped.properties.first?.type == .reference("Address"))
        #expect(mapped.definitions.map(\.name) == ["Address"])
        #expect(mapped.definitions.first?.properties.map(\.name) == ["city"])
    }

    @Test("additionalProperties true is unsupported")
    func additionalPropertiesTrueIsUnsupported() {
        let schema = """
        {
          "type": "object",
          "properties": { "name": { "type": "string" } },
          "additionalProperties": true
        }
        """
        #expect(
            FoundationModelsStructuredSchemaMapping.evaluate(
                StructuredOutputRequest(format: .jsonSchema(name: "Open", schemaJSON: schema))
            ) == .unsupported(.additionalProperties(path: "$"))
        )
    }

    @Test("additionalProperties schema is unsupported")
    func additionalPropertiesSchemaIsUnsupported() {
        let schema = """
        {
          "type": "object",
          "properties": { "name": { "type": "string" } },
          "additionalProperties": { "type": "string" }
        }
        """
        #expect(
            FoundationModelsStructuredSchemaMapping.evaluate(
                StructuredOutputRequest(format: .jsonSchema(name: "Map", schemaJSON: schema))
            ) == .unsupported(.additionalProperties(path: "$"))
        )
    }

    @Test("pattern is an unsupported keyword")
    func patternIsUnsupported() {
        expectUnsupportedKeyword(
            schema: """
            {
              "type": "object",
              "properties": { "code": { "type": "string", "pattern": "^[A-Z]+$" } }
            }
            """,
            keyword: "pattern",
            path: "$.properties.code"
        )
    }

    @Test("minimum is an unsupported keyword")
    func minimumIsUnsupported() {
        expectUnsupportedKeyword(
            schema: """
            {
              "type": "object",
              "properties": { "n": { "type": "integer", "minimum": 0 } }
            }
            """,
            keyword: "minimum",
            path: "$.properties.n"
        )
    }

    @Test("oneOf is an unsupported keyword")
    func oneOfIsUnsupported() {
        expectUnsupportedKeyword(
            schema: """
            {
              "type": "object",
              "properties": {
                "value": { "oneOf": [{ "type": "string" }, { "type": "integer" }] }
              }
            }
            """,
            keyword: "oneOf",
            path: "$.properties.value"
        )
    }

    @Test("format is an unsupported keyword")
    func formatIsUnsupported() {
        expectUnsupportedKeyword(
            schema: """
            {
              "type": "object",
              "properties": { "email": { "type": "string", "format": "email" } }
            }
            """,
            keyword: "format",
            path: "$.properties.email"
        )
    }

    @Test("type union is unsupported")
    func typeUnionIsUnsupported() {
        let schema = """
        {
          "type": "object",
          "properties": { "name": { "type": ["string", "null"] } }
        }
        """
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "Union", schemaJSON: schema))
        )
        #expect(result == .unsupported(.unsupportedType("union", path: "$.properties.name")))
    }

    @Test("object without properties is unsupported")
    func emptyObjectIsUnsupported() {
        let schema = """
        { "type": "object" }
        """
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "Empty", schemaJSON: schema))
        )
        #expect(result == .unsupported(.emptyProperties(path: "$")))
    }

    @Test("root array is unsupported")
    func rootArrayIsUnsupported() {
        let schema = """
        { "type": "array", "items": { "type": "string" } }
        """
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "List", schemaJSON: schema))
        )
        #expect(result == .unsupported(.rootMustBeObject))
    }

    @Test("invalid JSON is unsupported")
    func invalidJSONIsUnsupported() {
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "Bad", schemaJSON: "{not json"))
        )
        guard case .unsupported(.invalidSchemaJSON) = result else {
            Issue.record("expected invalidSchemaJSON, got \(result)")
            return
        }
    }

    @Test("remote $ref is unsupported")
    func remoteRefIsUnsupported() {
        let schema = """
        {
          "type": "object",
          "properties": { "home": { "$ref": "https://example.com/schema.json" } }
        }
        """
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "Remote", schemaJSON: schema))
        )
        #expect(result == .unsupported(.invalidReference("https://example.com/schema.json")))
    }

    @Test("mixed-type enum is unsupported")
    func mixedEnumIsUnsupported() {
        let schema = """
        {
          "type": "object",
          "properties": { "value": { "enum": ["a", 1] } }
        }
        """
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "Mixed", schemaJSON: schema))
        )
        #expect(result == .unsupported(.invalidEnum(path: "$.properties.value")))
    }

    private func mappedSchema(name: String, json: String) -> FoundationModelsMappedGenerationSchema? {
        switch FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: name, schemaJSON: json))
        ) {
        case let .mapped(mapped):
            return mapped
        case let .unsupported(reason):
            Issue.record("expected mapped schema, got \(reason)")
            return nil
        }
    }

    private func expectUnsupportedKeyword(schema: String, keyword: String, path: String) {
        let result = FoundationModelsStructuredSchemaMapping.evaluate(
            StructuredOutputRequest(format: .jsonSchema(name: "Probe", schemaJSON: schema))
        )
        #expect(result == .unsupported(.unsupportedKeyword(keyword, path: path)))
    }
}
