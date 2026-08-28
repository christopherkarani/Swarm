import Foundation
import MCP
@testable import Swarm
import SwarmMCP
import Testing

@Suite("SwarmMCPServerService")
struct SwarmMCPServerServiceTests {
    @Test("Real ToolRegistry adapter lists and calls through server service")
    func realToolRegistryAdapterListAndCallPath() async throws {
        let tool = MockTool(
            name: "registry_echo",
            description: "Echoes text through the registry",
            parameters: [
                ToolParameter(name: "text", description: "Text to echo", type: .string),
                ToolParameter(name: "uppercase", description: "Uppercase response", type: .bool, isRequired: false),
            ]
        ) { arguments in
            let text = arguments["text"]?.stringValue ?? ""
            let uppercase = arguments["uppercase"]?.boolValue ?? false
            return .string(uppercase ? text.uppercased() : text)
        }
        let registry = try ToolRegistry(tools: [tool])
        let adapter = SwarmMCPToolRegistryAdapter(registry: registry)
        let harness = try await SwarmMCPTestHarness.make(catalog: adapter, executor: adapter)
        defer {
            Task { await harness.shutdown() }
        }

        let listed = try await harness.client.listTools()
        #expect(listed.tools.map(\.name) == ["registry_echo"])

        guard case let .object(schema) = listed.tools[0].inputSchema,
              case let .object(properties)? = schema["properties"]
        else {
            Issue.record("expected object input schema")
            return
        }
        #expect(properties["text"] != nil)
        #expect(properties["uppercase"] != nil)
        #expect(schema["required"] == .array([.string("text")]))

        let result = try await harness.client.callTool(
            name: "registry_echo",
            arguments: ["text": .string("hello"), "uppercase": .bool(true)]
        )

        #expect(result.isError != true)
        #expect(textContent(from: result.content) == "HELLO")
    }

    @Test("ListTools returns deterministic stable ordering and schemas")
    func listToolsContract() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [
                ToolSchema(
                    name: "zeta_tool",
                    description: "zeta description",
                    parameters: [ToolParameter(name: "query", description: "query", type: .string)]
                ),
                ToolSchema(
                    name: "alpha_tool",
                    description: "alpha description",
                    parameters: [ToolParameter(name: "limit", description: "limit", type: .int, isRequired: false)]
                ),
            ]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in .null }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        let listed = try await harness.client.listTools()
        #expect(listed.tools.map(\.name) == ["alpha_tool", "zeta_tool"])
        #expect(listed.nextCursor == nil)

        guard case let .object(alphaSchema) = listed.tools[0].inputSchema else {
            Issue.record("expected object schema")
            return
        }
        #expect(alphaSchema["type"] == .string("object"))
        #expect(alphaSchema["properties"] != nil)
        #expect(alphaSchema["required"] == .array([]))
    }

    @Test("CallTool routes to executor and returns deterministic success content")
    func callToolSuccessContract() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [
                ToolSchema(
                    name: "echo",
                    description: "echo",
                    parameters: [ToolParameter(name: "text", description: "text", type: .string)]
                )
            ]
        )
        let executor = SwarmMCPToolExecutorStub { _, arguments in
            .string(arguments["text"]?.stringValue ?? "")
        }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        let result = try await harness.client.callTool(
            name: "echo",
            arguments: ["text": .string("hello")]
        )

        #expect(result.isError != true)
        #expect(textContent(from: result.content) == "hello")

        let invocations = await executor.invocationsSnapshot()
        #expect(invocations.count == 1)
        #expect(invocations[0].toolName == "echo")
        #expect(invocations[0].arguments["text"] == .string("hello"))
    }

    @Test("Unknown tool maps to MCP methodNotFound")
    func unknownToolMapping() async throws {
        let catalog = SwarmMCPToolCatalogStub(schemas: [])
        let executor = SwarmMCPToolExecutorStub { _, _ in
            throw SwarmMCPServerServiceTestError.unreachable("Executor should not be called")
        }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        await #expect(throws: MCP.MCPError.self) {
            _ = try await harness.client.callTool(name: "missing_tool", arguments: nil)
        }
    }

    @Test("Invalid args map to MCP invalidParams")
    func invalidArgsMapping() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [
                ToolSchema(name: "lookup", description: "lookup", parameters: [
                    ToolParameter(name: "id", description: "id", type: .string),
                ])
            ]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in
            throw AgentError.invalidToolArguments(toolName: "lookup", reason: "Missing required parameter: id")
        }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        do {
            _ = try await harness.client.callTool(name: "lookup", arguments: [:])
            Issue.record("Expected invalid params error")
        } catch let error as MCP.MCPError {
            #expect(error.code == MCP.MCPError.invalidParams(nil).code)
        }
    }

    @Test("Execution errors return deterministic error result metadata")
    func executionFailureMapping() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "explode", description: "explode", parameters: [])]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in
            throw AgentError.toolFailure(toolName: "explode", message: "boom", cause: nil)
        }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        let result = try await harness.client.callTool(name: "explode", arguments: nil)
        #expect(result.isError == true)

        let metadata = try metadataObject(from: result.content)
        #expect(metadata["code"] == .string("execution_failed"))
        #expect(metadata["action"] == .string("inspect_error_and_retry"))
        #expect(metadata["tool"] == .string("explode"))
    }

    @Test("Approval-required path is deterministic with actionable metadata")
    func approvalRequiredMapping() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "secure_action", description: "secure", parameters: [])]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in
            throw SwarmMCPToolExecutionError.approvalRequired(
                prompt: "Approve secure_action?",
                reason: "Human approval policy",
                metadata: ["approval_token": .string("tok-123")]
            )
        }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        let result = try await harness.client.callTool(name: "secure_action", arguments: nil)
        #expect(result.isError == true)

        let metadata = try metadataObject(from: result.content)
        #expect(metadata["code"] == .string("approval_required"))
        #expect(metadata["action"] == .string("request_human_approval"))

        guard case let .object(details)? = metadata["details"] else {
            Issue.record("Expected details object")
            return
        }
        #expect(details["approval_token"] == .string("tok-123"))
        #expect(details["prompt"] == .string("Approve secure_action?"))
    }

    @Test("Timeout and cancellation are deterministic")
    func timeoutAndCancellationMapping() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "slow_tool", description: "slow", parameters: [])]
        )

        let timeoutExecutor = SwarmMCPToolExecutorStub { _, _ in
            throw AgentError.timeout(duration: .seconds(3))
        }
        let timeoutHarness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: timeoutExecutor)
        defer {
            Task { await timeoutHarness.shutdown() }
        }

        let timeoutResult = try await timeoutHarness.client.callTool(name: "slow_tool", arguments: nil)
        let timeoutMetadata = try metadataObject(from: timeoutResult.content)
        #expect(timeoutResult.isError == true)
        #expect(timeoutMetadata["code"] == .string("timeout"))

        let cancellationExecutor = SwarmMCPToolExecutorStub { _, _ in
            throw CancellationError()
        }
        let cancellationHarness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: cancellationExecutor)
        defer {
            Task { await cancellationHarness.shutdown() }
        }

        let cancelledResult = try await cancellationHarness.client.callTool(name: "slow_tool", arguments: nil)
        let cancelledMetadata = try metadataObject(from: cancelledResult.content)
        #expect(cancelledResult.isError == true)
        #expect(cancelledMetadata["code"] == .string("cancelled"))
    }

    @Test("Parallel CallTool requests complete without races")
    func parallelCallToolRequests() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [
                ToolSchema(
                    name: "echo_parallel",
                    description: "echo parallel",
                    parameters: [ToolParameter(name: "value", description: "value", type: .int)]
                )
            ]
        )
        let executor = SwarmMCPToolExecutorStub { _, arguments in
            guard let value = arguments["value"]?.intValue else {
                throw AgentError.invalidToolArguments(toolName: "echo_parallel", reason: "Missing value")
            }
            return .int(value)
        }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        let total = 24
        let values = try await withThrowingTaskGroup(of: Int.self, returning: [Int].self) { group in
            for i in 0 ..< total {
                group.addTask {
                    let result = try await harness.client.callTool(
                        name: "echo_parallel",
                        arguments: ["value": .int(i)]
                    )
                    guard
                        let text = textContent(from: result.content),
                        let parsed = Int(text)
                    else {
                        throw SwarmMCPServerServiceTestError.unreachable("unexpected content")
                    }
                    return parsed
                }
            }

            var output: [Int] = []
            for try await value in group {
                output.append(value)
            }
            return output
        }

        #expect(Set(values) == Set(0 ..< total))
        let invocations = await executor.invocationsSnapshot()
        #expect(invocations.count == total)
    }

    @Test("ListTools handles duplicate parameter names without crashing")
    func listToolsDuplicateParameters() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [
                ToolSchema(
                    name: "dup_tool",
                    description: "duplicate params",
                    parameters: [
                        ToolParameter(name: "id", description: "first", type: .string),
                        ToolParameter(name: "id", description: "second", type: .string),
                    ]
                )
            ]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in .null }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        let listed = try await harness.client.listTools()
        #expect(listed.tools.count == 1)
        guard case let .object(schema) = listed.tools[0].inputSchema,
              case let .object(properties)? = schema["properties"]
        else {
            Issue.record("expected object properties")
            return
        }
        #expect(properties.keys.count == 1)
        #expect(properties["id"] != nil)
        #expect(schema["required"] == .array([.string("id")]))
    }

    @Test("CallTool returns internal protocol error when tool catalog listing fails")
    func callToolCatalogFailureMapsToInternalError() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "safe", description: "safe", parameters: [])]
        )
        await catalog.setListToolsDelay(.milliseconds(20))
        await catalog.setListToolsError(SwarmMCPServerServiceTestError.unreachable("catalog unavailable"))
        let executor = SwarmMCPToolExecutorStub { _, _ in .string("ok") }
        let harness = try await SwarmMCPTestHarness.make(catalog: catalog, executor: executor)
        defer {
            Task { await harness.shutdown() }
        }

        do {
            _ = try await harness.client.callTool(name: "safe", arguments: nil)
            Issue.record("Expected internal error from catalog failure")
        } catch let error as MCP.MCPError {
            #expect(error.code == MCP.MCPError.internalError(nil).code)
        }

        let metrics = await harness.service.snapshotMetrics()
        #expect(metrics.callToolRequests == 1)
        #expect(metrics.callToolFailures == 1)
        #expect(metrics.callToolSuccesses == 0)
        #expect(metrics.cumulativeCallToolLatencyMs > 0)
    }

    @Test("Server service is single-use and cannot be restarted")
    func serviceSingleUseLifecycle() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "noop", description: "noop", parameters: [])]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in .null }
        let service = SwarmMCPServerService(
            name: "single-use",
            version: "1.0.0",
            toolCatalog: catalog,
            toolExecutor: executor
        )

        let firstPair = await InMemoryTransport.createConnectedPair()
        try await service.start(transport: firstPair.server)
        await service.stop()

        let secondPair = await InMemoryTransport.createConnectedPair()
        await #expect(throws: MCP.MCPError.self) {
            try await service.start(transport: secondPair.server)
        }
    }

    @Test("Concurrent start attempts are rejected deterministically")
    func concurrentStartIsRejected() async throws {
        let catalog = SwarmMCPToolCatalogStub(
            schemas: [ToolSchema(name: "noop", description: "noop", parameters: [])]
        )
        let executor = SwarmMCPToolExecutorStub { _, _ in .null }
        let service = SwarmMCPServerService(
            name: "concurrent-start",
            version: "1.0.0",
            toolCatalog: catalog,
            toolExecutor: executor
        )

        let firstTransport = DelayedTransport(connectDelay: .milliseconds(200))
        let secondTransport = DelayedTransport(connectDelay: .milliseconds(200))

        async let firstStart: Void = service.start(transport: firstTransport)
        try await Task.sleep(for: .milliseconds(20))

        do {
            try await service.start(transport: secondTransport)
            Issue.record("Expected concurrent start rejection")
        } catch let error as MCP.MCPError {
            #expect(error.code == MCP.MCPError.invalidRequest(nil).code)
            #expect((error.errorDescription ?? "").contains("already started"))
        }

        try await firstStart
        await service.stop()
    }
}

private func textContent(from content: [MCP.Tool.Content]) -> String? {
    guard case let .text(text: text, annotations: _, _meta: _)? = content.first else {
        return nil
    }
    return text
}

private func metadataObject(from content: [MCP.Tool.Content]) throws -> [String: Value] {
    for item in content {
        if case let .resource(resource: resourceContent, annotations: _, _meta: _) = item,
           resourceContent.mimeType == "application/json",
           let text = resourceContent.text,
           let data = text.data(using: .utf8)
        {
            let value = try JSONDecoder().decode(Value.self, from: data)
            if case let .object(object) = value {
                return object
            }
        }
    }

    Issue.record("Expected JSON metadata in tool content")
    return [:]
}
