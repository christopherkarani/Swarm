// FoundationModelsNativeToolBridgeTests.swift
//
// Unit + live tests for first-class Foundation Models integration.

import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels

@Suite("FoundationModels Schema Conversion")
struct FoundationModelsSchemaConversionTests {
    @Test("Builds argument GenerationSchema from ToolSchema")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func buildsArgumentSchema() throws {
        let schema = ToolSchema(
            name: "lookup",
            description: "Look up information",
            parameters: [
                ToolParameter(name: "query", description: "Search query", type: .string),
                ToolParameter(name: "limit", description: "Result limit", type: .int, isRequired: false),
            ]
        )

        let generationSchema = try FoundationModelsSchemaConversion.argumentSchema(for: schema)
        let debug = generationSchema.debugDescription
        #expect(debug.contains("query"))
        #expect(debug.contains("limit"))
        #expect(debug.contains("lookup"))
    }

    @Test("Converts GeneratedContent structure to SendableValue dictionary")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func convertsGeneratedContent() {
        let content = GeneratedContent(properties: [
            "query": "Swift concurrency",
            "limit": 3,
        ])
        let dictionary = FoundationModelsSchemaConversion.argumentDictionary(from: content)
        #expect(dictionary["query"]?.stringValue == "Swift concurrency")
        #expect(dictionary["limit"]?.intValue == 3 || dictionary["limit"]?.doubleValue == 3)
    }

    @Test("Capture tools throw FoundationModelsToolCaptureError")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func captureToolsThrow() async throws {
        let parameters = try FoundationModelsSchemaConversion.argumentSchema(
            for: ToolSchema(
                name: "echo",
                description: "Echo",
                parameters: [
                    ToolParameter(name: "text", description: "Text", type: .string),
                ]
            )
        )
        let tool = FoundationModelsCaptureTool(
            name: "echo",
            description: "Echo",
            parameters: parameters
        )
        let arguments = GeneratedContent(properties: ["text": "hello"])

        do {
            _ = try await tool.call(arguments: arguments)
            Issue.record("Expected capture error")
        } catch let error as FoundationModelsToolCaptureError {
            #expect(error.toolCall.name == "echo")
            #expect(error.toolCall.arguments["text"]?.stringValue == "hello")
            let response = try #require(FoundationModelsToolBridge.inferenceResponse(from: error))
            #expect(response.finishReason == .toolCall)
            #expect(response.toolCalls.first?.name == "echo")
        }
    }
}

@Suite("FoundationModels Inference Provider")
struct FoundationModelsInferenceProviderTests {
    @Test("Reports private native tool-calling capabilities")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func reportsCapabilities() {
        let provider = FoundationModelsInferenceProvider()
        let capabilities = InferenceProviderCapabilities.resolved(for: provider)
        #expect(capabilities.contains(.nativeToolCalling))
        #expect(capabilities.contains(.conversationMessages))
        #expect(capabilities.contains(.privateInference))
        #expect(capabilities.contains(.structuredOutputs))
        #expect(capabilities.contains(.streamingToolCalls) == false)
        #expect(provider.providerName == "foundationmodels")
    }

    @Test("Dot-syntax foundationModels resolves to first-class provider")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func dotSyntaxResolves() throws {
        let provider: any InferenceProvider = .foundationModels()
        #expect(provider is FoundationModelsInferenceProvider)
    }

    @Test("Default factory returns first-class provider when available")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func defaultFactoryUsesNativeProvider() {
        guard FoundationModelsInferenceProvider.isAvailable else { return }
        let provider = DefaultInferenceProviderFactory.makeFoundationModelsProviderIfAvailable()
        #expect(provider is FoundationModelsInferenceProvider)
    }

    @Test("Live native tool calling surfaces structured tool calls")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func liveNativeToolCalling() async throws {
        guard ProcessInfo.processInfo.environment["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1" else {
            return
        }
        guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
            return
        }

        let tools = [
            ToolSchema(
                name: "lookup",
                description: "Look up information by query",
                parameters: [
                    ToolParameter(name: "query", description: "Search query", type: .string),
                ]
            ),
        ]

        let response = try await provider.generateWithToolCalls(
            prompt: "Use the lookup tool to search for Swift concurrency right now.",
            tools: tools,
            options: InferenceOptions(toolChoice: .required)
        )

        #expect(response.finishReason == .toolCall || response.finishReason == .completed)
        if response.finishReason == .toolCall {
            #expect(response.toolCalls.count == 1)
            #expect(response.toolCalls[0].name == "lookup")
            #expect(response.toolCalls[0].arguments["query"] != nil)
        }
    }
}
#endif
