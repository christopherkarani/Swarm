#if SWARM_INTEGRATIONS
import Foundation
import HiveCore

enum HiveChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}

struct HiveToolDefinition: Codable, Sendable, Equatable {
    let name: String
    let description: String
    let parametersJSONSchema: String
}

struct HiveToolCall: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
}

enum HiveChatMessageOp: String, Codable, Sendable, Equatable {
    case remove
    case removeAll
}

struct HiveChatMessage: Codable, Sendable, Equatable {
    let id: String
    let role: HiveChatRole
    let content: String
    let reasoningContent: String?
    let name: String?
    let toolCallID: String?
    let toolCalls: [HiveToolCall]
    let op: HiveChatMessageOp?

    init(
        id: String,
        role: HiveChatRole,
        content: String,
        reasoningContent: String? = nil,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [HiveToolCall] = [],
        op: HiveChatMessageOp? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.op = op
    }
}

struct HiveChatRequest: Sendable, Equatable {
    let model: String
    let messages: [HiveChatMessage]
    let tools: [HiveToolDefinition]

    init(model: String, messages: [HiveChatMessage], tools: [HiveToolDefinition] = []) {
        self.model = model
        self.messages = messages
        self.tools = tools
    }
}

struct HiveChatResponse: Sendable, Equatable {
    let message: HiveChatMessage
}

enum HiveChatStreamChunk: Sendable, Equatable {
    case token(String)
    case final(HiveChatResponse)
}

struct HiveToolResult: Sendable, Equatable {
    let toolCallID: String
    let content: String
}

struct HiveInferenceHints: Sendable, Equatable {
    enum LatencyTier: Sendable, Equatable {
        case interactive
        case background
    }

    enum NetworkState: Sendable, Equatable {
        case offline
        case metered
        case online
    }

    let privacyRequired: Bool
    let networkState: NetworkState

    init(
        privacyRequired: Bool = false,
        networkState: NetworkState = .online
    ) {
        self.privacyRequired = privacyRequired
        self.networkState = networkState
    }

    init(
        latencyTier _: LatencyTier,
        privacyRequired: Bool,
        tokenBudget _: Int?,
        networkState: NetworkState
    ) {
        self.init(privacyRequired: privacyRequired, networkState: networkState)
    }
}

protocol HiveModelClient: Sendable {
    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse
    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error>
}

struct AnyHiveModelClient: Sendable {
    private let completeHandler: @Sendable (HiveChatRequest) async throws -> HiveChatResponse
    private let streamHandler: @Sendable (HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error>

    init(_ client: any HiveModelClient) {
        completeHandler = { request in
            try await client.complete(request)
        }
        streamHandler = { request in
            client.stream(request)
        }
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await completeHandler(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        streamHandler(request)
    }
}

extension HiveModelClient {
    func streamFinal(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        var finalResponse: HiveChatResponse?
        for try await chunk in stream(request) {
            if case .final(let response) = chunk {
                finalResponse = response
            }
        }

        guard let finalResponse else {
            throw SwarmRuntimeError.modelStreamInvalid("Missing final response chunk.")
        }
        return finalResponse
    }
}

protocol HiveModelRouter: Sendable {
    func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient
}

protocol HiveToolRegistry: Sendable {
    func listTools() -> [HiveToolDefinition]
    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult
}

struct AnyHiveToolRegistry: Sendable {
    private let listToolsHandler: @Sendable () -> [HiveToolDefinition]
    private let invokeHandler: @Sendable (HiveToolCall) async throws -> HiveToolResult

    init(_ registry: any HiveToolRegistry) {
        listToolsHandler = {
            registry.listTools()
        }
        invokeHandler = { call in
            try await registry.invoke(call)
        }
    }

    func listTools() -> [HiveToolDefinition] {
        listToolsHandler()
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        try await invokeHandler(call)
    }
}

extension HiveEnvironment where Schema == ChatGraph.Schema {
    init(
        context: RuntimeContext,
        clock: any HiveClock,
        logger: any HiveLogger,
        model: AnyHiveModelClient? = nil,
        modelRouter: (any HiveModelRouter)? = nil,
        inferenceHints: HiveInferenceHints? = nil,
        tools: AnyHiveToolRegistry? = nil,
        checkpointStore: AnyHiveCheckpointStore<Schema>? = nil
    ) {
        self.init(
            context: context.withExecution(
                model: model,
                modelRouter: modelRouter,
                inferenceHints: inferenceHints,
                tools: tools
            ),
            clock: clock,
            logger: logger,
            checkpointStore: checkpointStore
        )
    }
}
#endif
