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

enum FoundationModelsLiveTestGate {
    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["SWARM_FM_LIVE_TESTS"] == "1"
            || env["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1"
    }
}

@Suite("FoundationModels Executing Tool Bridge")
struct FoundationModelsExecutingToolTests {
    @Test("GeneratedContent round-trips through SendableValue")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func generatedContentRoundTrip() {
        let original: [String: SendableValue] = [
            "query": .string("Swift"),
            "limit": .int(3),
            "flag": .bool(true),
        ]
        let content = FoundationModelsSchemaConversion.generatedContent(from: original)
        let roundTripped = FoundationModelsSchemaConversion.argumentDictionary(from: content)
        #expect(roundTripped["query"]?.stringValue == "Swift")
        #expect(roundTripped["limit"]?.intValue == 3 || roundTripped["limit"]?.doubleValue == 3)
        #expect(roundTripped["flag"]?.boolValue == true)
    }

    @Test("Executing tool runs the Swarm tool and returns its output")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func executingToolRunsSwarmTool() async throws {
        let swarmTool = MockTool(
            name: "echo",
            description: "Echo text",
            parameters: [ToolParameter(name: "text", description: "Text", type: .string)],
            result: .string("hello")
        )
        let registry = try ToolRegistry(tools: [swarmTool])
        let runtime = FoundationModelsNativeToolRuntime(
            registry: registry,
            agent: MockAgentRuntime(response: "ok"),
            context: nil,
            observer: nil,
            tracing: nil,
            resultBuilder: AgentResult.Builder(),
            stopOnToolError: false
        )
        let schema = swarmTool.schema
        let tools = try FoundationModelsToolBridge.makeExecutingTools(from: [schema], runtime: runtime)
        let executing = try #require(tools.first as? FoundationModelsExecutingTool)

        let output = try await executing.call(
            arguments: GeneratedContent(properties: ["text": "hello"])
        )
        #expect(output == "hello")
    }

    @Test("Executing tool fires observer hooks and input guardrails")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func executingToolFiresObserverAndGuardrails() async throws {
        let observer = NativeToolHookObserver()
        let guardrail = ClosureToolInputGuardrail(name: "require_text") { data in
            if data.arguments["text"] == nil {
                return .tripwire(message: "missing text")
            }
            return .passed()
        }
        let swarmTool = MockTool(
            name: "echo",
            description: "Echo text",
            parameters: [ToolParameter(name: "text", description: "Text", type: .string)],
            result: .string("ok"),
            inputGuardrails: [guardrail]
        )
        let registry = try ToolRegistry(tools: [swarmTool])
        let runtime = FoundationModelsNativeToolRuntime(
            registry: registry,
            agent: MockAgentRuntime(response: "ok"),
            context: nil,
            observer: observer,
            tracing: nil,
            resultBuilder: AgentResult.Builder(),
            stopOnToolError: false
        )
        let tools = try FoundationModelsToolBridge.makeExecutingTools(
            from: [swarmTool.schema],
            runtime: runtime
        )
        let executing = try #require(tools.first as? FoundationModelsExecutingTool)

        let output = try await executing.call(
            arguments: GeneratedContent(properties: ["text": "hi"])
        )
        #expect(output == "ok")
        #expect(await observer.started == ["echo"])
        #expect(await observer.ended == ["echo"])

        let blocked = try await executing.call(arguments: GeneratedContent(properties: [:]))
        #expect(blocked.contains("failed"))
    }

    @Test("Tool errors return a recoverable string instead of crashing")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func toolErrorsAreRecoverableStrings() async throws {
        let swarmTool = MockTool(
            name: "boom",
            description: "Always fails",
            handler: { _ in throw AgentError.toolExecutionFailed(toolName: "boom", underlyingError: "nope") }
        )
        let registry = try ToolRegistry(tools: [swarmTool])
        let runtime = FoundationModelsNativeToolRuntime(
            registry: registry,
            agent: MockAgentRuntime(response: "ok"),
            context: nil,
            observer: nil,
            tracing: nil,
            resultBuilder: AgentResult.Builder(),
            stopOnToolError: false
        )
        let tools = try FoundationModelsToolBridge.makeExecutingTools(
            from: [swarmTool.schema],
            runtime: runtime
        )
        let executing = try #require(tools.first as? FoundationModelsExecutingTool)
        let output = try await executing.call(arguments: GeneratedContent(properties: [:]))
        #expect(output.contains("failed"))
        #expect(output.contains("boom"))
    }
}

@Suite("FoundationModels Native Tool Adapter")
struct FoundationModelsNativeToolAdapterTests {
    @Test("Wraps a FoundationModels.Tool as AnyJSONTool and executes it")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func wrapsAndExecutesFoundationModelsTool() async throws {
        let parameters = try FoundationModelsSchemaConversion.argumentSchema(
            for: ToolSchema(
                name: "echo",
                description: "Echo",
                parameters: [ToolParameter(name: "text", description: "Text", type: .string)]
            )
        )
        let fmTool = NativeEchoFoundationTool(parameters: parameters)
        let wrapped = FoundationModelsNativeTool(fmTool)
        #expect(wrapped.name == "echo")
        let result = try await wrapped.execute(arguments: ["text": .string("ping")])
        #expect(result.stringValue == "ping")
    }
}

@Suite("FoundationModels Native Transcript Mapper")
struct FoundationModelsNativeTranscriptMapperTests {
    @Test("Maps tool calls, tool output, and assistant response into memory messages")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func mapsTranscriptEntries() {
        let prompt = Transcript.Prompt(
            segments: [.text(Transcript.TextSegment(content: "Hi"))]
        )
        let call = Transcript.ToolCall(
            id: "call-1",
            toolName: "echo",
            arguments: GeneratedContent(properties: ["text": "hi"])
        )
        let calls = Transcript.ToolCalls([call])
        let output = Transcript.ToolOutput(
            id: "call-1",
            toolName: "echo",
            segments: [.text(Transcript.TextSegment(content: "hi"))]
        )
        let response = Transcript.Response(
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(content: "Done"))]
        )
        let messages = FoundationModelsNativeTranscriptMapper.turnTranscriptMessages(
            from: [
                .prompt(prompt),
                .toolCalls(calls),
                .toolOutput(output),
                .response(response),
            ]
        )
        #expect(messages.count == 3)
        #expect(messages[0].role == .assistant)
        #expect(messages[1].role == .tool)
        #expect(messages[1].content == "hi")
        #expect(messages[2].role == .assistant)
        #expect(messages[2].content == "Done")
    }
}

@Suite("FoundationModels Native Session Live")
struct FoundationModelsNativeSessionLiveTests {
    @Test(
        "Live native session executes a Swarm tool inside LanguageModelSession",
        .enabled(if: FoundationModelsLiveTestGate.isEnabled)
    )
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func liveNativeSessionExecutesTools() async throws {
        guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
            return
        }
        let swarmTool = MockTool(
            name: "echo",
            description: "Echo the text argument back unchanged. Always call this tool.",
            parameters: [ToolParameter(name: "text", description: "Text to echo", type: .string)],
            handler: { arguments in
                .string(arguments["text"]?.stringValue ?? "missing")
            }
        )
        let registry = try ToolRegistry(tools: [swarmTool])
        let runtime = FoundationModelsNativeToolRuntime(
            registry: registry,
            agent: MockAgentRuntime(response: "ok"),
            context: nil,
            observer: nil,
            tracing: nil,
            resultBuilder: AgentResult.Builder(),
            stopOnToolError: false
        )
        let fmTools = try FoundationModelsToolBridge.makeExecutingTools(
            from: [swarmTool.schema],
            runtime: runtime
        )
        let result = try await provider.respondUsingNativeSession(
            messages: [.user("Call the echo tool with text 'hello native'. Then reply with the tool output.")],
            tools: fmTools,
            toolSchemas: [swarmTool.schema],
            options: InferenceOptions(toolChoice: .required),
            conversationID: "live-native-test"
        )
        #expect(!result.content.isEmpty)
        #expect(!result.transcriptMessages.isEmpty)
    }
}

actor NativeToolHookObserver: AgentObserver {
    var started: [String] = []
    var ended: [String] = []

    func onToolStart(context _: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async {
        started.append(call.toolName)
    }

    func onToolEnd(context _: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async {
        ended.append(result.isSuccess ? "echo" : "echo")
    }
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
private struct NativeEchoFoundationTool: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    var name: String { "echo" }
    var description: String { "Echo" }
    let parameters: GenerationSchema
    var includesSchemaInInstructions: Bool { true }

    func call(arguments: GeneratedContent) async throws -> String {
        FoundationModelsSchemaConversion.argumentDictionary(from: arguments)["text"]?.stringValue ?? ""
    }
}
#endif
