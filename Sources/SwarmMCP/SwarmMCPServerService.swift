#if SWARM_MCP
import Foundation
import MCP
import Swarm

/// Runtime service that exposes Swarm tools through an MCP server.
public actor SwarmMCPServerService {
    public struct Metrics: Sendable, Equatable {
        public var listToolsRequests: Int
        public var listedToolCount: Int
        public var callToolRequests: Int
        public var callToolSuccesses: Int
        public var callToolFailures: Int
        public var approvalRequiredCount: Int
        public var approvalRejectedCount: Int
        public var cumulativeCallToolLatencyMs: Double

        public init(
            listToolsRequests: Int = 0,
            listedToolCount: Int = 0,
            callToolRequests: Int = 0,
            callToolSuccesses: Int = 0,
            callToolFailures: Int = 0,
            approvalRequiredCount: Int = 0,
            approvalRejectedCount: Int = 0,
            cumulativeCallToolLatencyMs: Double = 0
        ) {
            self.listToolsRequests = listToolsRequests
            self.listedToolCount = listedToolCount
            self.callToolRequests = callToolRequests
            self.callToolSuccesses = callToolSuccesses
            self.callToolFailures = callToolFailures
            self.approvalRequiredCount = approvalRequiredCount
            self.approvalRejectedCount = approvalRejectedCount
            self.cumulativeCallToolLatencyMs = cumulativeCallToolLatencyMs
        }
    }

    public nonisolated let name: String
    public nonisolated let version: String

    private let toolCatalog: any SwarmMCPToolCatalog
    private let toolExecutor: any SwarmMCPToolExecutor
    private let server: Server
    private var metrics = Metrics()
    private var starting = false
    private var started = false
    private var hasStarted = false
    private var handlersRegistered = false

    // Rate limiting state
    private let maxRequestsPerSecond: Double
    private let maxConcurrentRequests: Int
    private var availableTokens: Double
    private var lastRefillTime: ContinuousClock.Instant
    private var activeRequests: Int

    public init(
        name: String = "swarm-mcp-server",
        version: String = Swarm.version,
        instructions: String? = nil,
        toolCatalog: some SwarmMCPToolCatalog,
        toolExecutor: some SwarmMCPToolExecutor,
        configuration: Server.Configuration = .strict,
        maxRequestsPerSecond: Double = 10,
        maxConcurrentRequests: Int = 50
    ) {
        self.name = name
        self.version = version
        self.toolCatalog = toolCatalog
        self.toolExecutor = toolExecutor
        self.maxRequestsPerSecond = maxRequestsPerSecond
        self.maxConcurrentRequests = maxConcurrentRequests
        self.availableTokens = maxRequestsPerSecond
        self.lastRefillTime = .now
        self.activeRequests = 0
        server = Server(
            name: name,
            version: version,
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false)),
            configuration: configuration
        )
    }

    /// Starts serving MCP requests over the given transport.
    public func start(
        transport: any Transport,
        initializeHook: (@Sendable (Client.Info, Client.Capabilities) async throws -> Void)? = nil
    ) async throws {
        guard !started && !starting else {
            throw MCP.MCPError.invalidRequest("SwarmMCPServerService is already started")
        }
        guard !hasStarted else {
            throw MCP.MCPError.invalidRequest(
                "SwarmMCPServerService instances are single-use. Create a new instance to restart."
            )
        }

        starting = true

        do {
            await registerHandlersIfNeeded()
            try await server.start(transport: transport, initializeHook: initializeHook)
            started = true
            hasStarted = true
            starting = false
            Log.orchestration.info("Swarm MCP server started")
        } catch {
            starting = false
            throw error
        }
    }

    /// Starts serving over stdio transport.
    public func startStdio(
        initializeHook: (@Sendable (Client.Info, Client.Capabilities) async throws -> Void)? = nil
    ) async throws {
        let transport = StdioTransport()
        try await start(transport: transport, initializeHook: initializeHook)
    }

    /// Stops the MCP server.
    public func stop() async {
        await server.stop()
        starting = false
        started = false
        Log.orchestration.info("Swarm MCP server stopped")
    }

    /// Waits for the server loop to complete.
    public func waitUntilCompleted() async {
        await server.waitUntilCompleted()
    }

    /// Returns current service metrics.
    public func snapshotMetrics() -> Metrics {
        metrics
    }

    private func registerHandlersIfNeeded() async {
        guard !handlersRegistered else {
            return
        }

        _ = await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard let self else {
                throw MCP.MCPError.internalError("SwarmMCPServerService was deallocated")
            }
            return try await self.handleListTools()
        }

        _ = await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                throw MCP.MCPError.internalError("SwarmMCPServerService was deallocated")
            }
            return try await self.handleCallTool(params: params)
        }
        handlersRegistered = true
    }

    private func checkRateLimit() throws {
        let now = ContinuousClock.now
        let elapsed = now - lastRefillTime
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        // Refill tokens based on elapsed time
        availableTokens = min(
            maxRequestsPerSecond,
            availableTokens + elapsedSeconds * maxRequestsPerSecond
        )
        lastRefillTime = now

        // Check if token is available
        guard availableTokens >= 1 else {
            throw MCP.MCPError.invalidRequest("Rate limit exceeded: too many requests")
        }

        // Check concurrent request limit
        guard activeRequests < maxConcurrentRequests else {
            throw MCP.MCPError.invalidRequest("Rate limit exceeded: too many concurrent requests")
        }

        // Consume token and increment active requests
        availableTokens -= 1
        activeRequests += 1
    }

    private func releaseRateLimit() {
        activeRequests = max(0, activeRequests - 1)
    }

    private func handleListTools() async throws -> ListTools.Result {
        try checkRateLimit()
        defer { releaseRateLimit() }

        let schemas = try await toolCatalog.listTools()
        let tools = SwarmMCPToolMapper.mapSchemas(schemas)

        metrics.listToolsRequests += 1
        metrics.listedToolCount = tools.count

        Log.orchestration.debug(
            "MCP tools/list",
            metadata: ["tool_count": "\(tools.count)"]
        )

        return ListTools.Result(tools: tools, nextCursor: nil)
    }

    private func handleCallTool(params: CallTool.Parameters) async throws -> CallTool.Result {
        try checkRateLimit()
        defer { releaseRateLimit() }

        let start = ContinuousClock.now
        metrics.callToolRequests += 1

        let availableTools: [ToolSchema]
        do {
            availableTools = try await toolCatalog.listTools()
        } catch let protocolError as MCP.MCPError {
            metrics.callToolFailures += 1
            recordLatency(from: start)
            throw protocolError
        } catch {
            metrics.callToolFailures += 1
            recordLatency(from: start)
            throw MCP.MCPError.internalError("Failed to list tools: \(error.localizedDescription)")
        }

        do {
            let availableToolNames = availableTools.map(\.name)
            guard availableToolNames.contains(params.name) else {
                throw MCP.MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = SwarmMCPValueMapper.sendableObject(from: params.arguments ?? [:])
            let result = try await toolExecutor.executeTool(named: params.name, arguments: arguments)
            let mapped = SwarmMCPErrorMapper.mapToolResult(result)

            metrics.callToolSuccesses += 1
            recordLatency(from: start)
            return mapped
        } catch {
            let mappedError = SwarmMCPErrorMapper.mapCallToolError(error, toolName: params.name)
            recordLatency(from: start)

            switch mappedError {
            case let .success(result):
                metrics.callToolSuccesses += 1
                return result

            case let .failure(result):
                metrics.callToolFailures += 1
                incrementSpecialFailureMetrics(from: result)
                return result

            case let .protocolError(protocolError):
                metrics.callToolFailures += 1
                throw protocolError
            }
        }
    }

    private func incrementSpecialFailureMetrics(from result: CallTool.Result) {
        guard
            let metadata = firstJSONMetadataObject(in: result.content),
            case let .string(code)? = metadata["code"]
        else {
            return
        }

        switch code {
        case "approval_required":
            metrics.approvalRequiredCount += 1
        case "approval_rejected":
            metrics.approvalRejectedCount += 1
        default:
            break
        }
    }

    private func firstJSONMetadataObject(in content: [MCP.Tool.Content]) -> [String: Value]? {
        let decoder = JSONDecoder()
        for entry in content {
            guard case let .resource(resource: resourceContent, annotations: _, _meta: _) = entry,
                  resourceContent.mimeType == "application/json",
                  let text = resourceContent.text,
                  let data = text.data(using: .utf8),
                  let decoded = try? decoder.decode(Value.self, from: data),
                  case let .object(object) = decoded
            else {
                continue
            }
            return object
        }
        return nil
    }

    private func recordLatency(from start: ContinuousClock.Instant) {
        let duration = ContinuousClock.now - start
        let ms = (Double(duration.components.seconds) * 1_000)
            + (Double(duration.components.attoseconds) / 1e15)
        metrics.cumulativeCallToolLatencyMs += ms
    }
}
#endif
