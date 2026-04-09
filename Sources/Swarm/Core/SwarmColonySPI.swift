import Foundation

@_spi(ColonyInternal) public enum SwarmChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}

@_spi(ColonyInternal) public struct SwarmToolDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let parametersJSONSchema: String

    public init(name: String, description: String, parametersJSONSchema: String) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
    }
}

@_spi(ColonyInternal) public struct SwarmToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

@_spi(ColonyInternal) public enum SwarmChatMessageOp: String, Codable, Sendable, Equatable {
    case remove
    case removeAll
}

@_spi(ColonyInternal) public struct SwarmChatMessage: Codable, Sendable, Equatable {
    public let id: String
    public let role: SwarmChatRole
    public let content: String
    public let name: String?
    public let toolCallID: String?
    public let toolCalls: [SwarmToolCall]
    public let op: SwarmChatMessageOp?

    public init(
        id: String,
        role: SwarmChatRole,
        content: String,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [SwarmToolCall] = [],
        op: SwarmChatMessageOp? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.op = op
    }
}

@_spi(ColonyInternal) public struct SwarmChatRequest: Sendable, Equatable {
    public let model: String
    public let messages: [SwarmChatMessage]
    public let tools: [SwarmToolDefinition]

    public init(
        model: String,
        messages: [SwarmChatMessage],
        tools: [SwarmToolDefinition] = []
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
    }
}

@_spi(ColonyInternal) public struct SwarmChatResponse: Sendable, Equatable {
    public let message: SwarmChatMessage

    public init(message: SwarmChatMessage) {
        self.message = message
    }
}

@_spi(ColonyInternal) public enum SwarmChatStreamChunk: Sendable, Equatable {
    case token(String)
    case final(SwarmChatResponse)
}

@_spi(ColonyInternal) public struct SwarmToolResult: Sendable, Equatable {
    public let toolCallID: String
    public let content: String

    public init(toolCallID: String, content: String) {
        self.toolCallID = toolCallID
        self.content = content
    }
}

@_spi(ColonyInternal) public protocol SwarmModelClient: Sendable {
    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse
    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error>
}

@_spi(ColonyInternal) public struct SwarmAnyModelClient: Sendable {
    private let completeHandler: @Sendable (SwarmChatRequest) async throws -> SwarmChatResponse
    private let streamHandler: @Sendable (SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error>

    public init(_ client: any SwarmModelClient) {
        completeHandler = { request in
            try await client.complete(request)
        }
        streamHandler = { request in
            client.stream(request)
        }
    }

    public func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await completeHandler(request)
    }

    public func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        streamHandler(request)
    }
}

@_spi(ColonyInternal) public extension SwarmModelClient {
    func streamFinal(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        var finalResponse: SwarmChatResponse?
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

@_spi(ColonyInternal) public protocol SwarmModelRouter: Sendable {
    func route(_ request: SwarmChatRequest, hints: SwarmInferenceHints?) -> SwarmAnyModelClient
}

@_spi(ColonyInternal) public protocol SwarmToolRegistry: Sendable {
    func listTools() -> [SwarmToolDefinition]
    func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult
}

@_spi(ColonyInternal) public struct SwarmAnyToolRegistry: Sendable {
    private let listToolsHandler: @Sendable () -> [SwarmToolDefinition]
    private let invokeHandler: @Sendable (SwarmToolCall) async throws -> SwarmToolResult

    public init(_ registry: any SwarmToolRegistry) {
        listToolsHandler = {
            registry.listTools()
        }
        invokeHandler = { call in
            try await registry.invoke(call)
        }
    }

    public func listTools() -> [SwarmToolDefinition] {
        listToolsHandler()
    }

    public func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult {
        try await invokeHandler(call)
    }
}

@_spi(ColonyInternal) public protocol SwarmClock: Sendable {
    func nowNanoseconds() -> UInt64
    func sleep(nanoseconds: UInt64) async throws
}

@_spi(ColonyInternal) public protocol SwarmLogger: Sendable {
    func debug(_ message: String, metadata: [String: String])
    func info(_ message: String, metadata: [String: String])
    func error(_ message: String, metadata: [String: String])
}

@_spi(ColonyInternal) public struct SwarmInferenceHints: Sendable, Equatable {
    public enum LatencyTier: Sendable, Equatable {
        case interactive
        case background
    }

    public enum NetworkState: Sendable, Equatable {
        case offline
        case metered
        case online
    }

    public let privacyRequired: Bool
    public let networkState: NetworkState

    public init(
        privacyRequired: Bool = false,
        networkState: NetworkState = .online
    ) {
        self.privacyRequired = privacyRequired
        self.networkState = networkState
    }

    public init(
        latencyTier: LatencyTier,
        privacyRequired: Bool,
        tokenBudget: Int?,
        networkState: NetworkState
    ) {
        _ = latencyTier
        _ = tokenBudget
        self.init(
            privacyRequired: privacyRequired,
            networkState: networkState
        )
    }
}

@_spi(ColonyInternal) public enum SwarmRuntimeError: Error, Sendable, Equatable {
    case modelClientMissing
    case modelStreamInvalid(String)
    case invalidMessagesUpdate
    case resumeInterruptMismatch(expected: String, found: String)
    case noInterruptToResume
    case executionChannelMissing(String)
    case executionChannelTypeMismatch(String)
}
