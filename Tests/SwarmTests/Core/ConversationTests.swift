import Testing
@testable import Swarm

@Suite("Conversation")
struct ConversationTests {
    @Test("send appends user and assistant messages")
    func sendAppendsMessages() async throws {
        let mock = MockAgentRuntime(response: "hello back")
        let conversation = Conversation(with: mock)

        try await conversation.send("hello")

        let messages = await conversation.messages
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].text == "hello")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].text == "hello back")
    }

    @Test("streamText appends assistant from token stream")
    func streamTextAppendsTokens() async throws {
        let mock = MockAgentRuntime(streamTokens: ["Hello", " ", "world"])
        let conversation = Conversation(with: mock)

        try await conversation.streamText("say hi")

        let messages = await conversation.messages
        #expect(messages.count == 2)
        #expect(messages[1].role == .assistant)
        #expect(messages[1].text == "Hello world")
    }

    @Test("stream returns raw event stream")
    func streamReturnsEvents() async throws {
        let mock = MockAgentRuntime(streamTokens: ["Hi"])
        let conversation = Conversation(with: mock)

        var events: [AgentEvent] = []
        for try await event in conversation.stream("test") {
            events.append(event)
        }

        #expect(!events.isEmpty)
    }

    @Test("observer is passed to send")
    func observerPassedToSend() async throws {
        let mock = MockAgentRuntime(response: "ok")
        let observer = TestObserver()
        let conversation = Conversation(with: mock, observer: observer)

        try await conversation.send("hello")

        #expect(await observer.agentStartCount == 1)
    }

    @Test("branch copies transcript and isolates future appends")
    func branchCopiesTranscriptIndependently() async throws {
        let conversation = Conversation(with: MockAgentRuntime(response: "hello back"))
        try await conversation.send("hello")

        let branch = try await conversation.branch()
        try await branch.send("branch only")

        let originalMessages = await conversation.messages
        let branchMessages = await branch.messages

        #expect(originalMessages.count == 2)
        #expect(branchMessages.count == 4)
        #expect(branchMessages.prefix(2) == originalMessages.prefix(2))
    }

    @Test("branch clones session instead of sharing it")
    func branchClonesSession() async throws {
        let provider = MockInferenceProvider(responses: ["first reply", "branch reply"])
        let agent = try Agent(
            instructions: "You are a helpful assistant.",
            inferenceProvider: provider
        )
        let session = InMemorySession(sessionId: "original")
        let conversation = Conversation(with: agent, session: session)

        try await conversation.send("hello")
        let branch = try await conversation.branch()
        try await branch.send("branch only")

        let originalSessionItems = try await session.getAllItems()
        let originalMessages = await conversation.messages
        let branchMessages = await branch.messages

        #expect(originalSessionItems.count == 2)
        #expect(originalMessages.count == 2)
        #expect(branchMessages.count == 4)
    }

    @Test("branch uses runtime-specific branching when available")
    func branchUsesRuntimeSpecificBranching() async throws {
        let conversation = Conversation(with: BranchingMockAgentRuntime(response: "original"))

        let branch = try await conversation.branch()
        let originalResult = try await conversation.send("hello")
        let branchResult = try await branch.send("hello")

        #expect(originalResult.output == "original")
        #expect(branchResult.output == "branched")
    }
}

private actor TestObserver: AgentObserver {
    var agentStartCount = 0

    func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async {
        agentStartCount += 1
    }
}

private final class BranchingMockAgentRuntime: ConversationBranchingRuntime, @unchecked Sendable {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "Branching mock"
    nonisolated let configuration: AgentConfiguration = .default
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil
    nonisolated let handoffs: [AnyHandoffConfiguration] = []
    nonisolated let inputGuardrails: [any InputGuardrail] = []
    nonisolated let outputGuardrails: [any OutputGuardrail] = []

    private let response: String

    init(response: String) {
        self.response = response
    }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult {
        await observer?.onAgentStart(context: nil, agent: self, input: input)
        let result = AgentResult(output: response)
        await observer?.onAgentEnd(context: nil, agent: self, result: result)
        return result
    }

    nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error> {
        let response = response
        return StreamHelper.makeTrackedStream { continuation in
            continuation.yield(AgentEvent.lifecycle(.started(input: input)))
            continuation.yield(AgentEvent.lifecycle(.completed(result: AgentResult(output: response))))
            continuation.finish()
        }
    }

    func branchConversationRuntime() async throws -> any AgentRuntime {
        BranchingMockAgentRuntime(response: "branched")
    }

    func cancel() async {}
}
