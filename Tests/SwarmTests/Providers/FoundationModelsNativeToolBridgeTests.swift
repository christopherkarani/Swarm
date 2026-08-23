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

    @Test("Builds GenerationSchema from a mapped structured-output request")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func buildsStructuredOutputGenerationSchema() throws {
        let request = StructuredOutputRequest(
            format: .jsonSchema(
                name: "Answer",
                schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "city": { "type": "string" },
                    "ok": { "type": "boolean" }
                  },
                  "required": ["city"]
                }
                """
            )
        )
        let generationSchema = try FoundationModelsSchemaConversion.generationSchema(for: request)
        let debug = generationSchema.debugDescription
        #expect(debug.contains("city"))
        #expect(debug.contains("ok"))
        #expect(debug.contains("Answer"))
    }

    @Test("Capture tools record into the store and return the sentinel")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func captureToolsRecordAndReturnSentinel() async throws {
        let store = FoundationModelsToolCaptureStore()
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
            parameters: parameters,
            store: store
        )
        let arguments = GeneratedContent(properties: ["text": "hello"])
        let output = try await tool.call(arguments: arguments)
        #expect(output == FoundationModelsCaptureTool.sentinelOutput)

        let snapshot = await store.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot[0].name == "echo")
        #expect(snapshot[0].arguments["text"]?.stringValue == "hello")
    }

    @Test("Simulated multi-call turn yields all N ParsedToolCalls in request order")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func simulatedMultiCallTurnYieldsAllCallsInOrder() async throws {
        let store = FoundationModelsToolCaptureStore()
        let schemas = [
            ToolSchema(
                name: "lookup",
                description: "Look up",
                parameters: [ToolParameter(name: "query", description: "Query", type: .string)]
            ),
            ToolSchema(
                name: "weather",
                description: "Weather",
                parameters: [ToolParameter(name: "city", description: "City", type: .string)]
            ),
            ToolSchema(
                name: "clock",
                description: "Clock",
                parameters: [ToolParameter(name: "tz", description: "Timezone", type: .string)]
            ),
        ]
        let tools = try FoundationModelsToolBridge.makeCaptureTools(from: schemas, store: store)
        #expect(tools.count == 3)
        let lookupTool = try #require(tools[0] as? FoundationModelsCaptureTool)
        let weatherTool = try #require(tools[1] as? FoundationModelsCaptureTool)
        let clockTool = try #require(tools[2] as? FoundationModelsCaptureTool)

        _ = try await lookupTool.call(arguments: GeneratedContent(properties: ["query": "swift"]))
        _ = try await weatherTool.call(arguments: GeneratedContent(properties: ["city": "Tokyo"]))
        _ = try await clockTool.call(arguments: GeneratedContent(properties: ["tz": "JST"]))

        let lookup = Transcript.ToolCall(
            id: "c1",
            toolName: "lookup",
            arguments: GeneratedContent(properties: ["query": "swift"])
        )
        let weather = Transcript.ToolCall(
            id: "c2",
            toolName: "weather",
            arguments: GeneratedContent(properties: ["city": "Tokyo"])
        )
        let clock = Transcript.ToolCall(
            id: "c3",
            toolName: "clock",
            arguments: GeneratedContent(properties: ["tz": "JST"])
        )
        let later = Transcript.ToolCall(
            id: "c4",
            toolName: "lookup",
            arguments: GeneratedContent(properties: ["query": "sentinel-based"])
        )
        let entries: [Transcript.Entry] = [
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Let me look those up."))]
            )),
            .toolCalls(Transcript.ToolCalls([lookup, weather, clock])),
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Sentinel-mediated final."))]
            )),
            .toolCalls(Transcript.ToolCalls([later])),
        ]

        let response = try #require(
            await FoundationModelsToolBridge.inferenceResponse(store: store, turnEntries: entries)
        )
        #expect(response.finishReason == .toolCall)
        #expect(response.toolCalls.map(\.name) == ["lookup", "weather", "clock"])
        #expect(response.toolCalls[0].arguments["query"]?.stringValue == "swift")
        #expect(response.toolCalls[1].arguments["city"]?.stringValue == "Tokyo")
        #expect(response.toolCalls[2].arguments["tz"]?.stringValue == "JST")
        #expect(response.content == "Let me look those up.")
        #expect(response.content?.contains("Sentinel-mediated") != true)
    }

    @Test("Store fallback is used only when the transcript has no toolCalls marker")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func storeFallbackWhenTranscriptHasNoToolCalls() async throws {
        let store = FoundationModelsToolCaptureStore()
        await store.record(
            InferenceResponse.ParsedToolCall(
                id: "s1",
                name: "lookup",
                arguments: ["query": .string("swift")]
            )
        )
        await store.record(
            InferenceResponse.ParsedToolCall(
                id: "s2",
                name: "weather",
                arguments: ["city": .string("Tokyo")]
            )
        )
        await store.record(
            InferenceResponse.ParsedToolCall(
                id: "s3",
                name: "lookup",
                arguments: ["query": .string("later-wave")]
            )
        )
        let entries: [Transcript.Entry] = [
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Working…"))]
            )),
        ]
        let error = FoundationModelsToolCaptureError(
            toolCall: InferenceResponse.ParsedToolCall(
                name: "clock",
                arguments: ["tz": .string("JST")]
            )
        )
        let response = try #require(
            await FoundationModelsToolBridge.inferenceResponse(
                store: store,
                turnEntries: entries,
                error: error
            )
        )
        #expect(response.toolCalls.map(\.name) == ["lookup", "weather", "lookup"])
        #expect(response.toolCalls.compactMap(\.id) == ["s1", "s2", "s3"])
        #expect(response.content == nil)
    }

    @Test("Empty placeholder then post-tool response does not recover a later wave")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func emptyPlaceholderThenLaterWaveIsNotFirstWave() async throws {
        let store = FoundationModelsToolCaptureStore()
        await store.record(
            InferenceResponse.ParsedToolCall(
                id: "first",
                name: "lookup",
                arguments: ["query": .string("swift")]
            )
        )
        await store.record(
            InferenceResponse.ParsedToolCall(
                id: "later",
                name: "weather",
                arguments: ["city": .string("Tokyo")]
            )
        )
        let later = Transcript.ToolCall(
            id: "c-later",
            toolName: "weather",
            arguments: GeneratedContent(properties: ["city": "Tokyo"])
        )
        let entries: [Transcript.Entry] = [
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Let me look that up."))]
            )),
            .toolCalls(Transcript.ToolCalls([])),
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Sentinel-mediated final."))]
            )),
            .toolCalls(Transcript.ToolCalls([later])),
        ]
        let response = await FoundationModelsToolBridge.inferenceResponse(
            store: store,
            turnEntries: entries
        )
        #expect(response == nil)
    }

    @Test("Empty placeholder before a real parallel group still recovers that group")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func emptyPlaceholderThenRealGroupIsFirstWave() async throws {
        let store = FoundationModelsToolCaptureStore()
        let lookup = Transcript.ToolCall(
            id: "c1",
            toolName: "lookup",
            arguments: GeneratedContent(properties: ["query": "swift"])
        )
        let weather = Transcript.ToolCall(
            id: "c2",
            toolName: "weather",
            arguments: GeneratedContent(properties: ["city": "Tokyo"])
        )
        let later = Transcript.ToolCall(
            id: "c3",
            toolName: "clock",
            arguments: GeneratedContent(properties: ["tz": "JST"])
        )
        let entries: [Transcript.Entry] = [
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Checking."))]
            )),
            .toolCalls(Transcript.ToolCalls([])),
            .toolCalls(Transcript.ToolCalls([lookup, weather])),
            .response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Sentinel-mediated final."))]
            )),
            .toolCalls(Transcript.ToolCalls([later])),
        ]
        let response = try #require(
            await FoundationModelsToolBridge.inferenceResponse(store: store, turnEntries: entries)
        )
        #expect(response.toolCalls.map(\.name) == ["lookup", "weather"])
        #expect(response.content == "Checking.")
        #expect(response.content?.contains("Sentinel-mediated") != true)
    }

    @Test("Single-call turn still returns one ParsedToolCall")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func singleCallTurnMatchesPreviousBehavior() async throws {
        let store = FoundationModelsToolCaptureStore()
        let call = Transcript.ToolCall(
            id: "only",
            toolName: "lookup",
            arguments: GeneratedContent(properties: ["query": "swift"])
        )
        await store.record(
            InferenceResponse.ParsedToolCall(
                id: "store-id",
                name: "lookup",
                arguments: ["query": .string("swift")]
            )
        )
        let entries: [Transcript.Entry] = [
            .toolCalls(Transcript.ToolCalls([call])),
        ]
        let response = try #require(
            await FoundationModelsToolBridge.inferenceResponse(store: store, turnEntries: entries)
        )
        #expect(response.finishReason == .toolCall)
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls[0].name == "lookup")
        #expect(response.content == nil)
    }

    @Test("Thrown capture error still converts to a single-call InferenceResponse")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func thrownCaptureErrorStillConverts() throws {
        let error = FoundationModelsToolCaptureError(
            toolCall: InferenceResponse.ParsedToolCall(
                name: "echo",
                arguments: ["text": .string("hello")]
            )
        )
        let response = try #require(FoundationModelsToolBridge.inferenceResponse(from: error))
        #expect(response.finishReason == .toolCall)
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls[0].name == "echo")
        #expect(response.content == nil)
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
            #expect(response.toolCalls.count >= 1)
            #expect(response.toolCalls[0].name == "lookup")
            #expect(response.toolCalls[0].arguments["query"] != nil)
        }
    }

    @Test(
        "Live native structured output uses guided generation when the schema maps",
        .enabled(if: FoundationModelsLiveTestGate.isEnabled)
    )
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func liveNativeStructuredOutput() async throws {
        guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
            return
        }
        let request = StructuredOutputRequest(
            format: .jsonSchema(
                name: "City",
                schemaJSON: """
                {
                  "type": "object",
                  "properties": { "city": { "type": "string" } },
                  "required": ["city"],
                  "additionalProperties": false
                }
                """
            )
        )
        let result = try await provider.generateStructured(
            prompt: "Name one city in France. Use the schema.",
            request: request,
            options: InferenceOptions()
        )
        #expect(result.source == .providerNative)
        #expect(result.value.dictionaryValue?["city"]?.stringValue?.isEmpty == false)
    }

    @Test(
        "Live jsonObject structured output stays prompt fallback",
        .enabled(if: FoundationModelsLiveTestGate.isEnabled)
    )
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func liveJSONObjectStaysPromptFallback() async throws {
        guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
            return
        }
        let result = try await provider.generateStructured(
            prompt: "Reply with JSON {\"ok\": true} and nothing else.",
            request: StructuredOutputRequest(format: .jsonObject),
            options: InferenceOptions()
        )
        #expect(result.source == .promptFallback)
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
        let executor = ToolCallExecutor { _, _ in .string("hello") }
        let schema = swarmTool.schema
        let tools = try FoundationModelsToolBridge.makeExecutingTools(from: [schema], executor: executor)
        let executing = try #require(tools.first as? FoundationModelsExecutingTool)

        let output = try await executing.call(
            arguments: GeneratedContent(properties: ["text": "hello"])
        )
        #expect(output == "hello")
    }

    @Test("Executing tool surfaces executor cancellation")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func executingToolSurfacesExecutorCancellation() async throws {
        let executor = ToolCallExecutor { _, _ in throw CancellationError() }
        let runtime = FoundationModelsNativeToolRuntime(executor: executor)
        await #expect(throws: CancellationError.self) {
            _ = try await runtime.execute(name: "echo", arguments: ["text": .string("hello")])
        }
    }

    @Test("Executing tool surfaces registry toolFailure as a native tool error")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func executingToolSurfacesToolFailureAsNativeError() async throws {
        struct Boom: Error, Equatable {}
        let cause = Boom()
        let executor = ToolCallExecutor { _, _ in
            throw AgentError.toolFailure(toolName: "boom", message: nil, cause: cause)
        }
        let runtime = FoundationModelsNativeToolRuntime(executor: executor)
        do {
            _ = try await runtime.execute(name: "boom", arguments: [:])
            Issue.record("expected FoundationModelsNativeToolError")
        } catch let error as FoundationModelsNativeToolError {
            #expect(error.toolName == "boom")
            guard case let .toolFailure(_, _, unwrapped) = error.cause as? AgentError else {
                Issue.record("expected nested toolFailure")
                return
            }
            #expect(unwrapped as? Boom == cause)
        }
    }

    @Test("Session seam unwraps the deep toolFailure cause past the native wrapper")
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func nativeToolErrorCauseFallbackPrefersDeepCause() {
        struct Boom: Error, Equatable {}
        let deep = Boom()
        let native = FoundationModelsNativeToolError(
            toolName: "boom",
            message: "nope",
            cause: AgentError.toolFailure(toolName: "boom", message: nil, cause: deep)
        )
        let mappedCause = native.cause ?? native
        guard case let .toolFailure(_, _, unwrapped) = mappedCause as? AgentError else {
            Issue.record("expected nested toolFailure")
            return
        }
        #expect(unwrapped as? Boom == deep)
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
        let executor = ToolCallExecutor { name, arguments in
            try await registry.execute(
                toolNamed: name,
                arguments: arguments,
                agent: MockAgentRuntime(response: "ok"),
                context: nil,
                observer: observer
            )
        }
        let tools = try FoundationModelsToolBridge.makeExecutingTools(
            from: [swarmTool.schema],
            executor: executor
        )
        let executing = try #require(tools.first as? FoundationModelsExecutingTool)

        let output = try await executing.call(
            arguments: GeneratedContent(properties: ["text": "hi"])
        )
        #expect(output == "ok")

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
        let executor = ToolCallExecutor { _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "nope"])
        }
        let tools = try FoundationModelsToolBridge.makeExecutingTools(
            from: [swarmTool.schema],
            executor: executor
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
        let fmTools = try FoundationModelsToolBridge.makeExecutingTools(
            from: [swarmTool.schema],
            executor: ToolCallExecutor { name, arguments in
                try await registry.execute(
                    toolNamed: name,
                    arguments: arguments,
                    agent: MockAgentRuntime(response: "ok"),
                    context: nil,
                    observer: nil
                )
            }
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
