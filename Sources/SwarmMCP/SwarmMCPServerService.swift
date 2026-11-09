#if SWARM_MCP
import Foundation
import MCP
@_spi(ColonyInternal) import Swarm

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
    private var lifecycle = Lifecycle.idle
    private var handlersRegistered = false

    /// Time source for the request throttle.
    private let clock: any SwarmClock
    private var throttle: SwarmMCPThrottle

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
        self.init(
            name: name,
            version: version,
            instructions: instructions,
            toolCatalog: toolCatalog,
            toolExecutor: toolExecutor,
            configuration: configuration,
            maxRequestsPerSecond: maxRequestsPerSecond,
            maxConcurrentRequests: maxConcurrentRequests,
            clock: LiveSwarmClock.live
        )
    }

    /// Creates a service whose request throttle reads time from `clock`.
    ///
    /// Package-only seam so tests can drive token refill with a virtual clock;
    /// the public initializer delegates here with a live continuous clock.
    package init(
        name: String = "swarm-mcp-server",
        version: String = Swarm.version,
        instructions: String? = nil,
        toolCatalog: some SwarmMCPToolCatalog,
        toolExecutor: some SwarmMCPToolExecutor,
        configuration: Server.Configuration = .strict,
        maxRequestsPerSecond: Double = 10,
        maxConcurrentRequests: Int = 50,
        clock: any SwarmClock
    ) {
        self.name = name
        self.version = version
        self.toolCatalog = toolCatalog
        self.toolExecutor = toolExecutor
        self.clock = clock
        throttle = SwarmMCPThrottle(
            maxRequestsPerSecond: maxRequestsPerSecond,
            maxConcurrentRequests: maxConcurrentRequests,
            nowNanoseconds: clock.nowNanoseconds()
        )
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
        switch lifecycle {
        case .starting, .running:
            throw MCP.MCPError.invalidRequest("SwarmMCPServerService is already started")
        case .stopped:
            throw MCP.MCPError.invalidRequest(
                "SwarmMCPServerService instances are single-use. Create a new instance to restart."
            )
        case .idle:
            break
        }

        lifecycle = .starting

        do {
            await registerHandlersIfNeeded()
            try await server.start(transport: transport, initializeHook: initializeHook)
            lifecycle = .running
            Log.orchestration.info("Swarm MCP server started")
        } catch {
            if lifecycle == .starting {
                lifecycle = .idle
            }
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
        switch lifecycle {
        case .running, .stopped:
            lifecycle = .stopped
        case .idle, .starting:
            lifecycle = .idle
        }
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

    /// Admits the request or rejects it immediately; never waits for a token.
    private func checkRateLimit() throws {
        let (decision, next) = throttle.admitting(atNanoseconds: clock.nowNanoseconds())
        throttle = next

        switch decision {
        case .admitted:
            return
        case .rateLimited:
            throw MCP.MCPError.invalidRequest("Rate limit exceeded: too many requests")
        case .concurrencyLimited:
            throw MCP.MCPError.invalidRequest("Rate limit exceeded: too many concurrent requests")
        }
    }

    private func releaseRateLimit() {
        throttle = throttle.releasing()
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

// MARK: - Lifecycle

extension SwarmMCPServerService {
    /// Single-use lifecycle of a service instance.
    private enum Lifecycle: Sendable, Equatable {
        /// Never started, or the last start attempt failed; `start` is allowed.
        case idle
        /// A `start` call is in flight; concurrent starts are rejected.
        case starting
        /// Serving requests.
        case running
        /// Stopped after a successful start; the instance cannot restart.
        case stopped
    }
}

// MARK: - SwarmMCPThrottle

/// Pure admission state for the MCP server's request throttle: a token bucket
/// plus an in-flight request cap.
///
/// Transitions return new values and never wait, so a request that finds no
/// token or no free slot is rejected immediately. Refill math is shared with
/// `RateLimiter` through `TokenBucketMath`. `maxRequestsPerSecond` is both the
/// bucket capacity and the per-second refill rate, used as-is: a fractional
/// rate keeps a fractional capacity, and rates below one, negative, or NaN
/// never reach a whole token, so they admit nothing.
struct SwarmMCPThrottle: Sendable, Equatable {
    /// Outcome of one admission attempt.
    enum Decision: Sendable, Equatable {
        /// A token was consumed and an in-flight slot taken.
        case admitted
        /// Fewer than one token is available.
        case rateLimited
        /// Tokens remain but every in-flight slot is taken.
        case concurrencyLimited
    }

    /// Bucket capacity, and tokens added per second of elapsed clock time.
    let maxRequestsPerSecond: Double
    /// Maximum number of admitted, unreleased requests.
    let maxConcurrentRequests: Int
    /// Tokens available as of `lastRefillNanoseconds`.
    let tokens: Double
    /// Clock reading of the most recent refill.
    let lastRefillNanoseconds: UInt64
    /// Admitted requests not yet released.
    let activeRequests: Int

    /// Creates a full bucket (`maxRequestsPerSecond` tokens) with no requests
    /// in flight.
    init(maxRequestsPerSecond: Double, maxConcurrentRequests: Int, nowNanoseconds: UInt64) {
        self.init(
            maxRequestsPerSecond: maxRequestsPerSecond,
            maxConcurrentRequests: maxConcurrentRequests,
            tokens: maxRequestsPerSecond,
            lastRefillNanoseconds: nowNanoseconds,
            activeRequests: 0
        )
    }

    /// Creates throttle state with explicit token and in-flight counts.
    init(
        maxRequestsPerSecond: Double,
        maxConcurrentRequests: Int,
        tokens: Double,
        lastRefillNanoseconds: UInt64,
        activeRequests: Int
    ) {
        self.maxRequestsPerSecond = maxRequestsPerSecond
        self.maxConcurrentRequests = maxConcurrentRequests
        self.tokens = tokens
        self.lastRefillNanoseconds = lastRefillNanoseconds
        self.activeRequests = activeRequests
    }

    /// Refills to `now`, then admits the request if a token and an in-flight
    /// slot are both available. The rate check runs first; a rejection keeps
    /// the refill but consumes nothing.
    func admitting(atNanoseconds now: UInt64) -> (Decision, SwarmMCPThrottle) {
        let refilledTokens = TokenBucketMath.refilled(
            tokens: tokens,
            elapsedSeconds: TokenBucketMath.elapsedSeconds(from: lastRefillNanoseconds, to: now),
            refillRate: maxRequestsPerSecond,
            capacity: maxRequestsPerSecond
        )
        guard refilledTokens >= 1 else {
            return (.rateLimited, with(tokens: refilledTokens, lastRefill: now, activeRequests: activeRequests))
        }
        guard activeRequests < maxConcurrentRequests else {
            return (.concurrencyLimited, with(tokens: refilledTokens, lastRefill: now, activeRequests: activeRequests))
        }
        return (.admitted, with(tokens: refilledTokens - 1, lastRefill: now, activeRequests: activeRequests + 1))
    }

    /// Frees one in-flight slot; never drops below zero.
    func releasing() -> SwarmMCPThrottle {
        with(tokens: tokens, lastRefill: lastRefillNanoseconds, activeRequests: max(0, activeRequests - 1))
    }

    private func with(tokens: Double, lastRefill: UInt64, activeRequests: Int) -> SwarmMCPThrottle {
        SwarmMCPThrottle(
            maxRequestsPerSecond: maxRequestsPerSecond,
            maxConcurrentRequests: maxConcurrentRequests,
            tokens: tokens,
            lastRefillNanoseconds: lastRefill,
            activeRequests: activeRequests
        )
    }
}
#endif
