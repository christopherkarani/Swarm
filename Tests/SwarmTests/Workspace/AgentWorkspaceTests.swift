import Foundation
@testable import Swarm
import Testing

@Suite("Agent Workspace")
struct AgentWorkspaceTests {
    @Test("Agent uses policy-aware memory query when available")
    func agentUsesPolicyAwareMemoryQuery() async throws {
        let provider = MockInferenceProvider(responses: ["ok"])
        let memory = PolicyAwareMemoryStub(context: "skill-snippet")
        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "policy-aware", contextMode: .strict4k, defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("refund question")

        let lastQuery = await memory.lastQuery
        #expect(lastQuery?.text == "refund question")
        #expect(lastQuery?.tokenLimit == ContextProfile.strict4k.memoryTokenLimit)
        #expect(lastQuery?.maxItems == ContextProfile.strict4k.maxRetrievedItems)
        #expect(lastQuery?.maxItemTokens == ContextProfile.strict4k.maxRetrievedItemTokens)
    }

    @Test("Agent does not seed session history into memory when import policy opts out")
    func agentSkipsSessionSeedingWhenMemoryOptsOut() async throws {
        let provider = MockInferenceProvider(responses: ["ok"])
        let memory = SessionImportOptOutMemory()
        let session = InMemorySession()
        try await session.addItems([
            .user("history user"),
            .assistant("history assistant"),
        ])

        let agent = try Agent(
            "You are helpful.",
            configuration: AgentConfiguration(name: "no-seed", defaultTracingEnabled: false),
            memory: memory,
            inferenceProvider: provider
        )

        _ = try await agent.run("new input", session: session)

        #expect(await memory.addCalls.isEmpty)
    }

    @Test("Agent.spec loads AGENTS and spec body into instructions")
    func agentSpecLoadsAgentsAndSpecInstructions() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        try writeFile(at: workspaceRoot.appendingPathComponent("AGENTS.md"), contents: "Global workspace rule.")
        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/agents/support.md"),
            contents: """
            ---
            schema_version: 1
            id: support
            title: Support
            skills: []
            revision: 1
            updated_at: 2026-03-20T00:00:00Z
            ---
            You are the support agent.
            """
        )

        let workspace = try AgentWorkspace(
            bundleRoot: workspaceRoot,
            writableRoot: workspaceRoot.appendingPathComponent("Writable", isDirectory: true),
            indexCacheRoot: workspaceRoot.appendingPathComponent("Cache", isDirectory: true)
        )
        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent.spec("support", in: workspace, inferenceProvider: provider)

        _ = try await agent.run("hello")

        let prompt = await capturedPromptText(from: provider)
        #expect(prompt?.contains("Global workspace rule.") == true)
        #expect(prompt?.contains("You are the support agent.") == true)
    }

    @Test("Agent.onDevice also loads AGENTS instructions from workspace")
    func agentOnDeviceLoadsAgentsInstructions() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        try writeFile(at: workspaceRoot.appendingPathComponent("AGENTS.md"), contents: "Global workspace rule.")

        let workspace = try AgentWorkspace(
            bundleRoot: workspaceRoot,
            writableRoot: workspaceRoot.appendingPathComponent("Writable", isDirectory: true),
            indexCacheRoot: workspaceRoot.appendingPathComponent("Cache", isDirectory: true)
        )
        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent.onDevice(
            "Local agent instructions.",
            workspace: workspace,
            inferenceProvider: provider
        )

        _ = try await agent.run("hello")

        let prompt = await capturedPromptText(from: provider)
        #expect(prompt?.contains("Global workspace rule.") == true)
        #expect(prompt?.contains("Local agent instructions.") == true)
    }

    @Test("Agent.spec uses listed SKILL.md content as retrieved context")
    func agentSpecUsesSkillContentAsRetrievedContext() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        try writeFile(at: workspaceRoot.appendingPathComponent("AGENTS.md"), contents: "Global workspace rule.")
        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/agents/support.md"),
            contents: """
            ---
            schema_version: 1
            id: support
            title: Support
            skills:
              - refund-policy
            revision: 1
            updated_at: 2026-03-20T00:00:00Z
            ---
            You are the support agent.
            """
        )
        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/skills/refund-policy/SKILL.md"),
            contents: """
            ---
            name: refund-policy
            description: Handle refund and return questions
            compatibility:
              - Swarm
            metadata:
              swarm.on-device-optimized: true
            ---
            If a user asks about a refund, first confirm the original order details and then explain the refund window.
            """
        )

        let workspace = try AgentWorkspace(
            bundleRoot: workspaceRoot,
            writableRoot: workspaceRoot.appendingPathComponent("Writable", isDirectory: true),
            indexCacheRoot: workspaceRoot.appendingPathComponent("Cache", isDirectory: true)
        )
        let provider = MockInferenceProvider(responses: ["ok"])
        let agent = try Agent.spec("support", in: workspace, inferenceProvider: provider)

        _ = try await agent.run("I need a refund for my order")

        let prompt = await capturedPromptText(from: provider)
        #expect(prompt?.contains("refund window") == true)
    }

    @Test("Agent.spec unions constrained tool allowlists across skills")
    func agentSpecUnionsConstrainedToolAllowlists() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/agents/support.md"),
            contents: """
            ---
            schema_version: 1
            id: support
            title: Support
            skills:
              - refunds
              - tickets
            revision: 1
            updated_at: 2026-05-13T00:00:00Z
            ---
            You are the support agent.
            """
        )
        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/skills/refunds/SKILL.md"),
            contents: """
            ---
            name: refunds
            description: Refund support
            allowed-tools:
              - refund_lookup
            ---
            Use refund_lookup for refund status.
            """
        )
        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/skills/tickets/SKILL.md"),
            contents: """
            ---
            name: tickets
            description: Ticket support
            allowed-tools:
              - ticket_create
            ---
            Use ticket_create for support tickets.
            """
        )

        let workspace = try AgentWorkspace(
            bundleRoot: workspaceRoot,
            writableRoot: workspaceRoot.appendingPathComponent("Writable", isDirectory: true),
            indexCacheRoot: workspaceRoot.appendingPathComponent("Cache", isDirectory: true)
        )
        let agent = try Agent.spec("support", in: workspace) {
            [
                MockTool(name: "refund_lookup"),
                MockTool(name: "ticket_create"),
                MockTool(name: "unlisted")
            ]
        }

        #expect(Set(agent.tools.map(\.name)) == ["refund_lookup", "ticket_create"])
    }

    @Test("Workspace validation reports malformed SKILL.md")
    func workspaceValidationReportsMalformedSkill() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        try writeFile(at: workspaceRoot.appendingPathComponent("AGENTS.md"), contents: "Global workspace rule.")
        try writeFile(
            at: workspaceRoot.appendingPathComponent(".swarm/skills/broken-skill/SKILL.md"),
            contents: """
            ---
            name: broken-skill
            ---
            Missing description should fail validation.
            """
        )

        let workspace = try AgentWorkspace(
            bundleRoot: workspaceRoot,
            writableRoot: workspaceRoot.appendingPathComponent("Writable", isDirectory: true),
            indexCacheRoot: workspaceRoot.appendingPathComponent("Cache", isDirectory: true)
        )

        let report = try await workspace.validate()
        #expect(report.isValid == false)
        #expect(report.issues.contains { $0.message.contains("description") })
    }

    @Test("WorkspaceWriter preserves notes with duplicate titles")
    func workspaceWriterPreservesDuplicateTitles() async throws {
        let workspaceRoot = try makeWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let workspace = try AgentWorkspace(
            bundleRoot: workspaceRoot,
            writableRoot: workspaceRoot.appendingPathComponent("Writable", isDirectory: true),
            indexCacheRoot: workspaceRoot.appendingPathComponent("Cache", isDirectory: true)
        )

        let writer = workspace.makeWriter()
        let firstURL = try await writer.recordFact(title: "Duplicate Title", content: "First fact")
        let secondURL = try await writer.recordFact(title: "Duplicate Title", content: "Second fact")

        #expect(firstURL != secondURL)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))

        let firstContents = try String(contentsOf: firstURL, encoding: .utf8)
        let secondContents = try String(contentsOf: secondURL, encoding: .utf8)
        #expect(firstContents.contains("First fact"))
        #expect(secondContents.contains("Second fact"))
    }
}

private actor PolicyAwareMemoryStub: Memory, MemoryRetrievalPolicyAware {
    let contextToReturn: String
    private(set) var addCalls: [MemoryMessage] = []
    private(set) var queries: [MemoryQuery] = []

    init(context: String) {
        contextToReturn = context
    }

    var count: Int { get async { 0 } }
    var isEmpty: Bool { get async { false } }
    var lastQuery: MemoryQuery? { get async { queries.last } }

    func add(_ message: MemoryMessage) async {
        addCalls.append(message)
    }

    func context(for query: String, tokenLimit: Int) async -> String {
        contextToReturn
    }

    func context(for query: MemoryQuery) async -> String {
        queries.append(query)
        return contextToReturn
    }

    func allMessages() async -> [MemoryMessage] { [] }
    func clear() async {}
}

private actor SessionImportOptOutMemory: Memory, MemorySessionImportPolicy {
    private(set) var addCalls: [MemoryMessage] = []

    var count: Int { get async { 0 } }
    var isEmpty: Bool { get async { true } }
    nonisolated let allowsAutomaticSessionSeeding = false

    func add(_ message: MemoryMessage) async {
        addCalls.append(message)
    }

    func context(for query: String, tokenLimit: Int) async -> String { "" }
    func allMessages() async -> [MemoryMessage] { [] }
    func clear() async {}
}

private func makeWorkspaceRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swarm-workspace-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent(".swarm/agents", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent(".swarm/skills", isDirectory: true),
        withIntermediateDirectories: true
    )
    return root
}

private func writeFile(at url: URL, contents: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

private func capturedPromptText(from provider: MockInferenceProvider) async -> String? {
    if let prompt = await provider.lastGenerateCall?.prompt {
        return prompt
    }

    if let prompt = await provider.toolCallCalls.last?.prompt {
        return prompt
    }

    if let prompt = await provider.streamCalls.last?.prompt {
        return prompt
    }

    if let messages = await provider.generateMessageCalls.last?.messages {
        return messages.compactMap(\.content).joined(separator: "\n")
    }

    if let messages = await provider.toolCallMessageCalls.last?.messages {
        return messages.compactMap(\.content).joined(separator: "\n")
    }

    if let messages = await provider.streamMessageCalls.last?.messages {
        return messages.compactMap(\.content).joined(separator: "\n")
    }

    return nil
}
