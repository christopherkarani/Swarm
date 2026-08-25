@testable import Swarm
import Testing

private struct EchoTypedTool: Tool, Sendable {
    struct Input: Codable, Sendable {
        let text: String
    }

    struct Output: Codable, Sendable {
        let echoed: String
    }

    let name: String = "echo"
    let description: String = "Echoes input text."
    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "text",
            description: "Text to echo.",
            type: .string,
            isRequired: true
        )
    ]

    func execute(_ input: Input) async throws -> Output {
        Output(echoed: input.text)
    }
}

@AgentActor(instructions: "You are an echo agent.")
actor MacroEchoAgent {
    func process(_ input: String) async throws -> String {
        "Echo: \(input)"
    }
}

@Suite("AgentActor macro conformance")
struct AgentActorMacroConformanceTests {
    @Test("Conforms to AgentRuntime and supports session/observer signatures")
    func runSupportsSessionAndHooks() async throws {
        let agent: any AgentRuntime = MacroEchoAgent()
        let session = InMemorySession()

        let result = try await agent.run("hi", session: session, observer: nil)
        #expect(result.output == "Echo: hi")

        let items = try await session.getItems(limit: nil)
        #expect(items.count == 2)
        #expect(items.first?.role == .user)
        #expect(items.first?.content == "hi")
        #expect(items.last?.role == .assistant)
        #expect(items.last?.content == "Echo: hi")
    }

    @Test("Streams via AgentRuntime signature")
    func streamSupportsSessionAndHooks() async throws {
        let agent: any AgentRuntime = MacroEchoAgent()

        var completed: AgentResult?
        for try await event in agent.stream("hello", session: nil, observer: nil) {
            if case let .lifecycle(.completed(result: result)) = event {
                completed = result
            }
        }

        #expect(completed?.output == "Echo: hello")
    }

    @Test("Generated Builder supports typed tool bridging")
    func builderSupportsTypedToolBridging() async throws {
        let agent = MacroEchoAgent.Builder()
            .addTool(EchoTypedTool())
            .build()

        #expect(agent.tools.contains { $0.name == "echo" })
    }

    @Test("Generated run seeds replay into eligible composite memory layers")
    func generatedRunSeedsReplayIntoCompositeMemoryLayer() async throws {
        let seedable = ConversationMemory(maxMessages: 20)
        let staticMemory = StaticMacroContextMemory(context: "Static context includes the garnet-anchor marker.")
        let composite = CompositeMemory([seedable, staticMemory])
        let session = InMemorySession(sessionId: "macro-composite-memory")
        try await session.addItems([
            .user("Replay history includes the prism-session marker.")
        ])

        let agent = MacroEchoAgent(memory: composite)

        _ = try await agent.run("current turn", session: session)

        let seedableContext = await seedable.context(for: "prism current", tokenLimit: 1_000)
        #expect(seedableContext.contains("prism-session marker"))
        #expect(seedableContext.contains("current turn"))
    }

    @Test("Generated run dispatches lifecycle to defaulted Memory requirements without marker conformance")
    func generatedRunDispatchesLifecycleWithoutMarkerConformance() async throws {
        let memory = WitnessLifecycleMemory()
        let agent = MacroEchoAgent(memory: memory)

        _ = try await agent.run("lifecycle probe")

        let counts = await memory.sessionCounts()
        #expect(counts.begins == 1)
        #expect(counts.ends == 1)
    }
}

private actor WitnessLifecycleMemory: Memory {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    var count: Int { get async { 0 } }
    var isEmpty: Bool { get async { true } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return ""
    }

    func allMessages() async -> [MemoryMessage] { [] }
    func clear() async {}

    func beginMemorySession() async {
        beginCount += 1
    }

    func endMemorySession() async {
        endCount += 1
    }

    func sessionCounts() -> (begins: Int, ends: Int) {
        (beginCount, endCount)
    }
}

private actor StaticMacroContextMemory: Memory, MemorySessionImportPolicy {
    nonisolated let allowsAutomaticSessionSeeding = false

    private let contextText: String

    init(context: String) {
        self.contextText = context
    }

    var count: Int { get async { 1 } }
    var isEmpty: Bool { get async { false } }

    func add(_ message: MemoryMessage) async {
        _ = message
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        _ = query
        _ = tokenLimit
        return contextText
    }

    func allMessages() async -> [MemoryMessage] {
        []
    }

    func clear() async {}
}
