#if SWARM_MCP
import Foundation
import Logging
import MCP
@_spi(ColonyInternal) @testable import Swarm
import SwarmMCP

actor SwarmMCPToolCatalogStub: SwarmMCPToolCatalog {
    private var schemas: [ToolSchema]
    private var listToolsError: (any Error)?
    private var listToolsDelay: Duration?
    private(set) var listToolsCallCount: Int = 0

    init(schemas: [ToolSchema]) {
        self.schemas = schemas
    }

    func listTools() async throws -> [ToolSchema] {
        if let listToolsDelay {
            try await Task.sleep(for: listToolsDelay)
        }
        if let listToolsError {
            throw listToolsError
        }
        listToolsCallCount += 1
        return schemas
    }

    func setSchemas(_ schemas: [ToolSchema]) {
        self.schemas = schemas
    }

    func setListToolsError(_ error: (any Error)?) {
        listToolsError = error
    }

    func setListToolsDelay(_ delay: Duration?) {
        listToolsDelay = delay
    }
}

actor SwarmMCPToolExecutorStub: SwarmMCPToolExecutor {
    struct Invocation: Sendable, Equatable {
        let toolName: String
        let arguments: [String: SendableValue]
    }

    typealias Handler =
        @Sendable (_ toolName: String, _ arguments: [String: SendableValue]) async throws -> SendableValue

    private let handler: Handler
    private(set) var invocations: [Invocation] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func executeTool(named toolName: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        invocations.append(Invocation(toolName: toolName, arguments: arguments))
        return try await handler(toolName, arguments)
    }

    func invocationsSnapshot() -> [Invocation] {
        invocations
    }
}

struct SwarmMCPTestHarness {
    let service: SwarmMCPServerService
    let client: Client

    static func make(
        catalog: some SwarmMCPToolCatalog,
        executor: some SwarmMCPToolExecutor
    ) async throws -> SwarmMCPTestHarness {
        let service = SwarmMCPServerService(
            name: "swarm-mcp-test-server",
            version: "1.0.0",
            toolCatalog: catalog,
            toolExecutor: executor,
            maxRequestsPerSecond: 10_000,
            maxConcurrentRequests: 1_000
        )
        let client = Client(name: "swarm-mcp-test-client", version: "1.0.0")
        let transports = await InMemoryTransport.createConnectedPair()

        try await service.start(transport: transports.server)
        _ = try await client.connect(transport: transports.client)

        return SwarmMCPTestHarness(service: service, client: client)
    }

    /// Builds a started harness whose throttle reads time from `clock`.
    static func make(
        catalog: some SwarmMCPToolCatalog,
        executor: some SwarmMCPToolExecutor,
        maxRequestsPerSecond: Double,
        maxConcurrentRequests: Int,
        clock: any SwarmClock
    ) async throws -> SwarmMCPTestHarness {
        let service = SwarmMCPServerService(
            name: "swarm-mcp-test-server",
            version: "1.0.0",
            toolCatalog: catalog,
            toolExecutor: executor,
            maxRequestsPerSecond: maxRequestsPerSecond,
            maxConcurrentRequests: maxConcurrentRequests,
            clock: clock
        )
        let client = Client(name: "swarm-mcp-test-client", version: "1.0.0")
        let transports = await InMemoryTransport.createConnectedPair()

        try await service.start(transport: transports.server)
        _ = try await client.connect(transport: transports.client)

        return SwarmMCPTestHarness(service: service, client: client)
    }

    func shutdown() async {
        await client.disconnect()
        await service.stop()
    }
}

enum SwarmMCPServerServiceTestError: Error, Sendable, Equatable {
    case unreachable(String)
}

/// Transport whose `connect()` signals entry and then suspends until
/// `releaseConnect()` is called, so tests can observe a start in progress
/// without sleeping.
actor GatedTransport: Transport {
    let logger: Logger = .init(label: "swarm.tests.gated-transport")

    /// Yields once when `connect()` begins.
    nonisolated let connectEntered: AsyncStream<Void>
    private let connectEnteredContinuation: AsyncStream<Void>.Continuation
    private let release: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init() {
        (connectEntered, connectEnteredContinuation) = AsyncStream.makeStream(of: Void.self)
        (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// Lets a pending (or future) `connect()` complete.
    nonisolated func releaseConnect() {
        releaseContinuation.yield()
    }

    func connect() async throws {
        connectEnteredContinuation.yield()
        for await _ in release {
            break
        }
    }

    func disconnect() async {}

    func send(_ data: Data) async throws {}

    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
#endif
