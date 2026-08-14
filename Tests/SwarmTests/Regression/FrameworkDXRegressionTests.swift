import Foundation
@testable import Swarm
import Testing

@Suite("Framework DX Regression Tests")
struct FrameworkDXRegressionTests {
    @Test("SendableValue encodes and decodes plain JSON values")
    func sendableValueUsesPlainJSONWireFormat() throws {
        let value: SendableValue = [
            "query": .string("swift"),
            "limit": .int(3),
            "includeRaw": .bool(true),
            "tags": .array([.string("docs"), .string("mcp")]),
            "metadata": .dictionary(["score": .double(0.75)]),
            "empty": .null
        ]

        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["query"] as? String == "swift")
        #expect(object["limit"] as? Int == 3)
        #expect(object["includeRaw"] as? Bool == true)
        #expect(object["empty"] is NSNull)
        #expect(object["dictionary"] == nil)

        let decoded = try JSONDecoder().decode(SendableValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("MCP response decodes normal JSON-RPC result objects")
    func mcpResponseDecodesPlainJSONResult() throws {
        let data = Data("""
        {
          "jsonrpc": "2.0",
          "id": "request-1",
          "result": {
            "capabilities": {
              "tools": {}
            }
          }
        }
        """.utf8)

        let response = try JSONDecoder().decode(MCPResponse.self, from: data)

        #expect(response.result?["capabilities"]?["tools"]?.dictionaryValue?.isEmpty == true)
    }

    @Test("Workflow structured parallel merge preserves agent input order")
    func workflowParallelStructuredMergePreservesInputOrder() async throws {
        let slow = OrderedWorkflowAgent(output: "slow-zero", delay: .milliseconds(120))
        let fast = OrderedWorkflowAgent(output: "fast-one", delay: .milliseconds(10))

        let result = try await Workflow()
            .parallel([slow, fast], merge: .structured)
            .run("input")

        let data = try #require(result.output.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])

        #expect(object["0"] == "slow-zero")
        #expect(object["1"] == "fast-one")
    }

    @Test("Workflow indexed parallel merge preserves agent input order")
    func workflowParallelIndexedMergePreservesInputOrder() async throws {
        let slow = OrderedWorkflowAgent(output: "slow-zero", delay: .milliseconds(120))
        let fast = OrderedWorkflowAgent(output: "fast-one", delay: .milliseconds(10))

        let result = try await Workflow()
            .parallel([slow, fast], merge: .indexed)
            .run("input")

        #expect(result.output == "[0]: slow-zero\n[1]: fast-one")
    }

    @Test("MCP tool cache invalidation wins over in-flight refresh")
    func mcpToolCacheInvalidationWinsOverInflightRefresh() async throws {
        let client = MCPClient()
        let oldTool = ToolSchema(name: "old_tool", description: "Old", parameters: [])
        let newTool = ToolSchema(name: "new_tool", description: "New", parameters: [])
        let server = BlockingToolListServer(name: "blocking", initialTools: [oldTool])
        try await client.addServer(server)

        let firstRefresh = Task {
            try await client.getAllTools().map(\.name).sorted()
        }

        await server.waitUntilListToolsIsBlocked()
        await client.invalidateCache()
        await server.setTools([newTool])

        let secondRefresh = Task {
            try await client.getAllTools().map(\.name).sorted()
        }

        #expect(try await secondRefresh.value == ["new_tool"])
        await server.releaseBlockedListTools()

        #expect(try await firstRefresh.value == ["new_tool"])
        #expect(try await client.getAllTools().map(\.name).sorted() == ["new_tool"])
    }

    @Test("MCP tool cache waiters retry when their in-flight refresh is invalidated")
    func mcpToolCacheWaiterRetriesInvalidatedInflightRefresh() async throws {
        let client = MCPClient()
        let oldTool = ToolSchema(name: "old_tool", description: "Old", parameters: [])
        let newTool = ToolSchema(name: "new_tool", description: "New", parameters: [])
        let server = BlockingToolListServer(name: "blocking", initialTools: [oldTool])
        try await client.addServer(server)

        let firstRefresh = Task {
            try await client.getAllTools().map(\.name).sorted()
        }

        await server.waitUntilListToolsIsBlocked()
        let waiterRefresh = Task {
            try await client.getAllTools().map(\.name).sorted()
        }
        try await Task.sleep(for: .milliseconds(20))

        await client.invalidateCache()
        await server.setTools([newTool])
        await server.releaseBlockedListTools()

        #expect(try await firstRefresh.value == ["new_tool"])
        #expect(try await waiterRefresh.value == ["new_tool"])
        #expect(try await client.getAllTools().map(\.name).sorted() == ["new_tool"])
    }

    @Test("MCP resource cache invalidation wins over in-flight refresh")
    func mcpResourceCacheInvalidationWinsOverInflightRefresh() async throws {
        let client = MCPClient()
        let oldResource = MCPResource(uri: "file://old", name: "Old")
        let newResource = MCPResource(uri: "file://new", name: "New")
        let server = BlockingResourceListServer(name: "resources", initialResources: [oldResource])
        try await client.addServer(server)

        let firstRefresh = Task {
            try await client.getAllResources().map(\.uri).sorted()
        }

        await server.waitUntilListResourcesIsBlocked()
        await client.invalidateResourceCache()
        await server.setResources([newResource])
        await server.releaseBlockedListResources()

        #expect(try await firstRefresh.value == ["file://new"])
        #expect(try await client.getAllResources().map(\.uri).sorted() == ["file://new"])
    }

    @Test("MCP resource cache waiters retry when their in-flight refresh is invalidated")
    func mcpResourceCacheWaiterRetriesInvalidatedInflightRefresh() async throws {
        let client = MCPClient()
        let oldResource = MCPResource(uri: "file://old", name: "Old")
        let newResource = MCPResource(uri: "file://new", name: "New")
        let server = BlockingResourceListServer(name: "resources", initialResources: [oldResource])
        try await client.addServer(server)

        let firstRefresh = Task {
            try await client.getAllResources().map(\.uri).sorted()
        }

        await server.waitUntilListResourcesIsBlocked()
        let waiterRefresh = Task {
            try await client.getAllResources().map(\.uri).sorted()
        }
        try await Task.sleep(for: .milliseconds(20))

        await client.invalidateResourceCache()
        await server.setResources([newResource])
        await server.releaseBlockedListResources()

        #expect(try await firstRefresh.value == ["file://new"])
        #expect(try await waiterRefresh.value == ["file://new"])
        #expect(try await client.getAllResources().map(\.uri).sorted() == ["file://new"])
    }

    @Test("Workflow timeout returns without waiting for non-cooperative work")
    func workflowTimeoutReturnsWithoutWaitingForNonCooperativeWork() async throws {
        let agent = BlockingWorkflowAgent()
        let timeout: Duration = .milliseconds(200)
        let start = ContinuousClock.now

        let task = Task {
            try await Workflow()
                .step(agent)
                .timeout(timeout)
                .run("input")
        }

        await agent.waitUntilBlocked()

        do {
            _ = try await task.value
            Issue.record("Expected workflow timeout")
        } catch AgentError.timeout(let duration) {
            #expect(duration == timeout)
        } catch {
            Issue.record("Expected workflow timeout, got \(error)")
        }

        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(500))
        await agent.release()
    }

    @Test("MultiProvider stream uses selected provider from stream creation")
    func multiProviderStreamUsesCreationTimeProvider() async throws {
        let defaultProvider = StreamingNameProvider(name: "default")
        let firstProvider = StreamingNameProvider(name: "first")
        let secondProvider = StreamingNameProvider(name: "second")
        let provider = MultiProvider(defaultProvider: defaultProvider)

        try await provider.register(prefix: "a", provider: firstProvider)
        try await provider.register(prefix: "b", provider: secondProvider)
        await provider.setModel("a/model")

        let stream = provider.stream(prompt: "hello", options: .default)
        await provider.setModel("b/model")

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        #expect(tokens.joined() == "first")
    }

    @Test("TracingHelper redacts sensitive reasoning and tool arguments by default")
    func tracingHelperRedactsSensitiveContentByDefault() async throws {
        let tracer = RegressionSpyTracer()
        let helper = TracingHelper(tracer: tracer, agentName: "spy")

        await helper.traceThought("password=secret")
        await helper.tracePlan("call customer 123")
        _ = await helper.traceToolCall(name: "lookup", arguments: ["api_key": .string("secret")])

        let events = await tracer.snapshot()
        #expect(events.contains { $0.kind == EventKind.thought && $0.message == "Thought recorded" })
        #expect(events.contains { $0.metadata["thought_redacted"] == SendableValue.bool(true) })
        #expect(events.contains { $0.metadata["plan_redacted"] == SendableValue.bool(true) })
        #expect(events.contains { $0.metadata["arguments_redacted"] == SendableValue.bool(true) })
        #expect(!events.contains { $0.metadata["thought"] == SendableValue.string("password=secret") })
        #expect(!events.contains { $0.metadata["plan"] == SendableValue.string("call customer 123") })
        #expect(!events.contains {
            $0.metadata["arguments"] == SendableValue.dictionary(["api_key": .string("secret")])
        })
    }

    @Test("SlidingWindowMemory keeps token count within budget for an oversized latest message")
    func slidingWindowMemoryTruncatesOversizedLatestMessage() async {
        let memory = SlidingWindowMemory(maxTokens: 100, tokenEstimator: CharacterBasedTokenEstimator(charactersPerToken: 1))
        await memory.add(.user(String(repeating: "a", count: 500)))

        #expect(await memory.count == 1)
        #expect(await memory.tokenCount <= 100)

        let context = await memory.context(for: "latest", tokenLimit: 100)
        #expect(!context.isEmpty)
    }

    @Test("ToolRegistry batch register is atomic when a later tool duplicates")
    func toolRegistryBatchRegisterIsAtomicOnDuplicate() async throws {
        let existing = MockRegistryTool(name: "existing")
        let newTool = MockRegistryTool(name: "new_tool")
        let duplicate = MockRegistryTool(name: "existing")
        let registry = try ToolRegistry(tools: [existing])

        await #expect(throws: ToolRegistryError.self) {
            try await registry.register([newTool, duplicate])
        }

        #expect(await registry.tool(named: "existing") != nil)
        #expect(await registry.tool(named: "new_tool") == nil)
    }
}

private struct OrderedWorkflowAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Return a deterministic output."
    nonisolated let configuration = AgentConfiguration.default

    let output: String
    let delay: Duration

    func run(_ input: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        try await Task.sleep(for: delay)
        return AgentResult(output: output)
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: output))))
            continuation.finish()
        }
    }

    func cancel() async {}
}

private actor BlockingToolListServer: MCPServerConnection {
    let name: String
    private var tools: [ToolSchema]
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldBlockNextListTools = true

    nonisolated var capabilities: MCPCapabilities {
        get async { MCPCapabilities(tools: true, resources: false) }
    }

    init(name: String, initialTools: [ToolSchema]) {
        self.name = name
        tools = initialTools
    }

    func initialize() async throws -> MCPCapabilities {
        MCPCapabilities(tools: true, resources: false)
    }

    func close() async throws {}

    func listTools() async throws -> [ToolSchema] {
        let snapshot = tools
        if shouldBlockNextListTools {
            shouldBlockNextListTools = false
            await withCheckedContinuation { continuation in
                blockedContinuation = continuation
                let waiters = blockedWaiters
                blockedWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }
        return snapshot
    }

    func waitUntilListToolsIsBlocked() async {
        if blockedContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseBlockedListTools() {
        blockedContinuation?.resume()
        blockedContinuation = nil
    }

    func setTools(_ tools: [ToolSchema]) {
        self.tools = tools
    }

    func callTool(name _: String, arguments _: [String: SendableValue]) async throws -> SendableValue {
        .null
    }

    func listResources() async throws -> [MCPResource] {
        []
    }

    func readResource(uri: String) async throws -> MCPResourceContent {
        throw MCPError.invalidParams("Resource not found: \(uri)")
    }
}

private actor BlockingResourceListServer: MCPServerConnection {
    let name: String
    private var resources: [MCPResource]
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldBlockNextListResources = true

    nonisolated var capabilities: MCPCapabilities {
        get async { MCPCapabilities(tools: false, resources: true) }
    }

    init(name: String, initialResources: [MCPResource]) {
        self.name = name
        resources = initialResources
    }

    func initialize() async throws -> MCPCapabilities {
        MCPCapabilities(tools: false, resources: true)
    }

    func close() async throws {}

    func listTools() async throws -> [ToolSchema] {
        []
    }

    func callTool(name _: String, arguments _: [String: SendableValue]) async throws -> SendableValue {
        .null
    }

    func listResources() async throws -> [MCPResource] {
        let snapshot = resources
        if shouldBlockNextListResources {
            shouldBlockNextListResources = false
            await withCheckedContinuation { continuation in
                blockedContinuation = continuation
                let waiters = blockedWaiters
                blockedWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }
        return snapshot
    }

    func waitUntilListResourcesIsBlocked() async {
        if blockedContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseBlockedListResources() {
        blockedContinuation?.resume()
        blockedContinuation = nil
    }

    func setResources(_ resources: [MCPResource]) {
        self.resources = resources
    }

    func readResource(uri: String) async throws -> MCPResourceContent {
        throw MCPError.invalidParams("Resource not found: \(uri)")
    }
}

private actor BlockingWorkflowAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Block until released."
    nonisolated let configuration = AgentConfiguration.default
    private var continuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    var isBlocked: Bool {
        continuation != nil
    }

    func waitUntilBlocked() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { waiter in
            blockedWaiters.append(waiter)
        }
    }

    func run(_ input: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = blockedWaiters
            blockedWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        return AgentResult(output: input)
    }

    nonisolated func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.finish()
        }
    }

    func cancel() async {}

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor StreamingNameProvider: InferenceProvider {
    let name: String

    init(name: String) {
        self.name = name
    }

    func generate(prompt _: String, options _: InferenceOptions) async throws -> String {
        name
    }

    nonisolated func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let name = name
        return AsyncThrowingStream { continuation in
            continuation.yield(name)
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt _: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        InferenceResponse(content: name, finishReason: .completed)
    }
}

private actor RegressionSpyTracer: Tracer {
    private(set) var events: [TraceEvent] = []

    func trace(_ event: TraceEvent) async {
        events.append(event)
    }

    func snapshot() -> [TraceEvent] {
        events
    }
}

private struct MockRegistryTool: AnyJSONTool {
    let name: String
    let description = "Mock registry tool"
    let parameters: [ToolParameter] = []

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        .string(name)
    }
}
