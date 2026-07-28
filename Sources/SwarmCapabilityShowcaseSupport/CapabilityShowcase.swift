import Foundation
import Swarm

public enum CapabilityFamily: String, CaseIterable, Sendable, Hashable {
    case agentTools = "agent-tools"
    case streaming = "streaming"
    case conversationSession = "conversation-session"
    case workflowCore = "workflow-core"
    case handoff = "handoff"
    case memory = "memory"
    case workspace = "workspace"
    case guardrails = "guardrails"
    case resilience = "resilience"
    case durable = "durable"
    case observability = "observability"
    case mcp = "mcp"
    case providers = "providers"
    case foundationModels = "foundation-models"
}

public enum CapabilityScenarioKind: String, Sendable {
    case deterministic
    case smoke
}

public enum CapabilityScenarioStatus: String, Sendable, Equatable {
    case passed
    case failed
    case skipped
}

public struct CapabilityEvidence: Sendable, Equatable {
    public let label: String
    public let detail: String
    public let artifactPath: String?

    public init(label: String, detail: String, artifactPath: String? = nil) {
        self.label = label
        self.detail = detail
        self.artifactPath = artifactPath
    }
}

public struct CapabilityScenarioResult: Sendable, Equatable {
    public let id: String
    public let name: String
    public let families: [CapabilityFamily]
    public let status: CapabilityScenarioStatus
    public let summary: String
    public let evidence: [CapabilityEvidence]

    public init(
        id: String,
        name: String,
        families: [CapabilityFamily],
        status: CapabilityScenarioStatus,
        summary: String,
        evidence: [CapabilityEvidence] = []
    ) {
        self.id = id
        self.name = name
        self.families = families
        self.status = status
        self.summary = summary
        self.evidence = evidence
    }
}

public struct CapabilityScenario: Sendable {
    public typealias RunHandler = @Sendable (CapabilityScenarioContext) async throws -> CapabilityScenarioResult

    public let id: String
    public let name: String
    public let families: [CapabilityFamily]
    public let kind: CapabilityScenarioKind

    let runHandler: RunHandler

    public init(
        id: String,
        name: String,
        families: [CapabilityFamily],
        kind: CapabilityScenarioKind,
        runHandler: @escaping RunHandler
    ) {
        self.id = id
        self.name = name
        self.families = families
        self.kind = kind
        self.runHandler = runHandler
    }

    func run(in context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
        try await runHandler(context)
    }
}

public struct CapabilityScenarioContext: Sendable {
    public let artifactsDirectory: URL
    public let environment: [String: String]

    public init(artifactsDirectory: URL, environment: [String: String]) {
        self.artifactsDirectory = artifactsDirectory
        self.environment = environment
    }

    @discardableResult
    public func writeArtifact(named name: String, contents: String) throws -> URL {
        let url = artifactsDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func relativeArtifactPath(for url: URL) -> String {
        url.path.replacingOccurrences(of: artifactsDirectory.path + "/", with: "")
    }
}

public struct CapabilityShowcase: Sendable {
    public static let requiredFamilies = Set(CapabilityFamily.allCases)

    public let scenarios: [CapabilityScenario]

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        scenarios = Self.makeScenarios(environment: environment)
    }

    public func runDeterministicScenarios() async throws -> [CapabilityScenarioResult] {
        try await run(scenarios.filter { $0.kind == .deterministic })
    }

    public func runSmokeScenarios() async throws -> [CapabilityScenarioResult] {
        try await run(scenarios.filter { $0.kind == .smoke })
    }

    public func runScenario(id: String) async throws -> CapabilityScenarioResult {
        guard let scenario = scenarios.first(where: { $0.id == id }) else {
            throw CapabilityShowcaseError.unknownScenario(id)
        }
        return try await execute(scenario)
    }

    public func renderCatalog() -> String {
        let lines = scenarios.map { scenario in
            let families = scenario.families.map(\.rawValue).joined(separator: ", ")
            return "\(scenario.kind.rawValue)\t\(scenario.id)\t\(families)"
        }
        return (["kind\tid\tfamilies"] + lines).joined(separator: "\n")
    }

    public static func renderSummary(_ results: [CapabilityScenarioResult]) -> String {
        let header = "status\tid\tfamilies\tsummary"
        let rows = results
            .sorted { $0.id < $1.id }
            .map { result in
                let families = result.families.map(\.rawValue).joined(separator: ",")
                return "\(result.status.rawValue)\t\(result.id)\t\(families)\t\(result.summary)"
            }
        return ([header] + rows).joined(separator: "\n")
    }
}

private extension CapabilityShowcase {
    func run(_ selectedScenarios: [CapabilityScenario]) async throws -> [CapabilityScenarioResult] {
        var results: [CapabilityScenarioResult] = []
        for scenario in selectedScenarios {
            results.append(try await execute(scenario))
        }
        return results
    }

    func execute(_ scenario: CapabilityScenario) async throws -> CapabilityScenarioResult {
        let root = try makeArtifactsDirectory(for: scenario.id)
        let context = CapabilityScenarioContext(artifactsDirectory: root, environment: environment)

        do {
            let result = try await scenario.run(in: context)
            return result
        } catch {
            return CapabilityScenarioResult(
                id: scenario.id,
                name: scenario.name,
                families: scenario.families,
                status: .failed,
                summary: error.localizedDescription,
                evidence: []
            )
        }
    }

    func makeArtifactsDirectory(for scenarioID: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-capability-showcase", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(scenarioID, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func makeScenarios(environment: [String: String]) -> [CapabilityScenario] {
        let deterministic: [CapabilityScenario] = [
            .init(
                id: "agent-tools",
                name: "Agent Tools",
                families: [.agentTools],
                kind: .deterministic,
                runHandler: runAgentToolsScenario
            ),
            .init(
                id: "streaming",
                name: "Streaming",
                families: [.streaming],
                kind: .deterministic,
                runHandler: runStreamingScenario
            ),
            .init(
                id: "conversation-session",
                name: "Conversation Session",
                families: [.conversationSession],
                kind: .deterministic,
                runHandler: runConversationSessionScenario
            ),
            .init(
                id: "workflow-core",
                name: "Workflow Core",
                families: [.workflowCore],
                kind: .deterministic,
                runHandler: runWorkflowCoreScenario
            ),
            .init(
                id: "handoff",
                name: "Handoff",
                families: [.handoff],
                kind: .deterministic,
                runHandler: runHandoffScenario
            ),
            .init(
                id: "memory",
                name: "Memory",
                families: [.memory],
                kind: .deterministic,
                runHandler: runMemoryScenario
            ),
            .init(
                id: "workspace",
                name: "Workspace",
                families: [.workspace],
                kind: .deterministic,
                runHandler: runWorkspaceScenario
            ),
            .init(
                id: "guardrails",
                name: "Guardrails",
                families: [.guardrails],
                kind: .deterministic,
                runHandler: runGuardrailsScenario
            ),
            .init(
                id: "resilience",
                name: "Resilience",
                families: [.resilience],
                kind: .deterministic,
                runHandler: runResilienceScenario
            ),
            .init(
                id: "durable",
                name: "Durable Execution",
                families: [.durable],
                kind: .deterministic,
                runHandler: runDurableScenario
            ),
            .init(
                id: "observability",
                name: "Observability",
                families: [.observability],
                kind: .deterministic,
                runHandler: runObservabilityScenario
            ),
            .init(
                id: "mcp",
                name: "MCP",
                families: [.mcp],
                kind: .deterministic,
                runHandler: runMCPScenario
            ),
            .init(
                id: "providers",
                name: "Providers",
                families: [.providers],
                kind: .deterministic,
                runHandler: runProvidersScenario
            ),
            .init(
                id: "foundation-models",
                name: "Foundation Models Path",
                families: [.foundationModels, .providers],
                kind: .deterministic,
                runHandler: runFoundationModelsScenario
            ),
        ]

        let smoke: [CapabilityScenario] = [
            .init(
                id: "live-provider-smoke",
                name: "Live Provider Smoke",
                families: [.providers],
                kind: .smoke
            ) { context in
                try await runLiveProviderSmokeScenario(context: context)
            },
            .init(
                id: "live-foundation-models-smoke",
                name: "Live Foundation Models Smoke",
                families: [.foundationModels, .providers],
                kind: .smoke
            ) { context in
                try await runLiveFoundationModelsSmokeScenario(context: context, environment: environment)
            },
        ]

        return deterministic + smoke
    }
}

// MARK: - Deterministic Scenarios

private func runAgentToolsScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let additionTool = ShowcaseAdditionTool().asAnyJSONTool()
    let uppercaseTool = FunctionTool(
        name: "uppercase_text",
        description: "Uppercases text.",
        parameters: [
            ToolParameter(name: "text", description: "Text to uppercase", type: .string),
        ]
    ) { arguments in
        let text = try arguments.require("text", as: String.self)
        return .string(text.uppercased())
    }
    let provider = ScriptedInferenceProvider(
        toolCallResponses: [
            .init(
                toolCalls: [
                    .init(id: "call-1", name: additionTool.name, arguments: ["lhs": .int(20), "rhs": .int(22)]),
                ],
                finishReason: .toolCall
            ),
            .init(
                toolCalls: [
                    .init(id: "call-2", name: uppercaseTool.name, arguments: ["text": .string("tool chain")]),
                ],
                finishReason: .toolCall
            ),
            .init(content: "The tools produced 42 and TOOL CHAIN.", finishReason: .completed),
        ]
    )

    let agent = try Agent(
        tools: [additionTool, uppercaseTool],
        instructions: "Use tools when needed.",
        memory: makeScenarioMemory(),
        inferenceProvider: provider
    )
    let result = try await agent.run("Show that the framework can chain tools.")

    try ensure(result.output.contains("42"), "Expected the addition tool result in final output.")
    try ensure(result.output.contains("TOOL CHAIN"), "Expected the function tool result in final output.")
    try ensure(result.toolResults.count == 2, "Expected two tool results.")

    let toolSummary = result.toolResults
        .map { $0.output.description }
        .joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "tool-results.txt", contents: toolSummary)

    return .init(
        id: "agent-tools",
        name: "Agent Tools",
        families: [.agentTools],
        status: .passed,
        summary: "Executed a macro tool and a closure tool through a real Agent loop.",
        evidence: [
            .init(label: "tool-results", detail: toolSummary, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runStreamingScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let provider = ScriptedInferenceProvider(responses: ["Streaming proves token-by-token emission."])
    let agent = try Agent("Stream the answer.", memory: makeScenarioMemory(), inferenceProvider: provider)

    var output = ""
    var sawStart = false
    var sawComplete = false

    for try await event in agent.stream("Stream this") {
        switch event {
        case .lifecycle(.started):
            sawStart = true
        case .lifecycle(.completed(let result)):
            sawComplete = true
            if output.isEmpty {
                output = result.output
            }
        case .output(.token(let token)):
            output += token
        case .output(.chunk(let chunk)):
            output += chunk
        default:
            break
        }
    }

    try ensure(sawStart, "Expected a streaming lifecycle start event.")
    try ensure(sawComplete, "Expected a streaming lifecycle completion event.")
    try ensure(output.contains("Streaming proves"), "Expected streamed output to be collected.")

    let artifact = try context.writeArtifact(named: "stream.txt", contents: output)
    return .init(
        id: "streaming",
        name: "Streaming",
        families: [.streaming],
        status: .passed,
        summary: "Collected streamed output and lifecycle events from agent.stream.",
        evidence: [
            .init(label: "stream-output", detail: output, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runConversationSessionScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let provider = ScriptedInferenceProvider(responses: [
        "Hi Casey, nice to meet you.",
        "Yes, I remember that your name is Casey.",
    ])
    let agent = try Agent("Remember prior turns.", memory: makeScenarioMemory(), inferenceProvider: provider)
    let session = InMemorySession()
    let conversation = Conversation(with: agent, session: session)

    _ = try await conversation.send("My name is Casey.")
    let reply = try await conversation.send("Do you remember my name?")
    let transcript = await conversation.messages
    let sessionItems = try await session.getAllItems()
    let prompts = await provider.generatePrompts()

    try ensure(reply.output.contains("Casey"), "Expected the follow-up response to reference Casey.")
    try ensure(transcript.count == 4, "Expected a two-turn conversation transcript.")
    try ensure(sessionItems.count == 4, "Expected session persistence across both turns.")
    try ensure(prompts.last?.contains("Casey") == true, "Expected the provider prompt to include prior session context.")

    let artifactBody = transcript.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "conversation.txt", contents: artifactBody)
    return .init(
        id: "conversation-session",
        name: "Conversation Session",
        families: [.conversationSession],
        status: .passed,
        summary: "Persisted a multi-turn conversation through Conversation and InMemorySession.",
        evidence: [
            .init(label: "transcript", detail: "Stored \(transcript.count) messages and \(sessionItems.count) session items.", artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runWorkflowCoreScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let sequential = try await Workflow()
        .step(makeTextAgent(output: "researched"))
        .step(makeTextAgent(output: "drafted"))
        .step(makeTextAgent(output: "published"))
        .run("topic")

    let parallel = try await Workflow()
        .parallel([
            makeTextAgent(output: "bullish"),
            makeTextAgent(output: "bearish"),
        ], merge: .indexed)
        .run("market")

    let routeBilling = makeTextAgent(output: "billing")
    let routeGeneral = makeTextAgent(output: "general")
    let routed = try await Workflow()
        .route { input in
            input.contains("invoice") ? routeBilling : routeGeneral
        }
        .run("invoice question")

    let loopProvider = ScriptedInferenceProvider(responses: ["running", "done"])
    let repeatAgent = try Agent("Repeat until done.", memory: makeScenarioMemory(), inferenceProvider: loopProvider)
    let repeated = try await Workflow()
        .step(repeatAgent)
        .repeatUntil(maxIterations: 3) { $0.output == "done" }
        .timeout(.seconds(5))
        .run("monitor")

    try ensure(sequential.output == "published", "Expected sequential workflow to forward output through all steps.")
    try ensure(parallel.output.contains("bullish"), "Expected parallel merge to include the first branch.")
    try ensure(parallel.output.contains("bearish"), "Expected parallel merge to include the second branch.")
    try ensure(routed.output == "billing", "Expected route to select the billing branch.")
    try ensure(repeated.output == "done", "Expected repeatUntil to stop on done.")

    let artifactBody = [
        "sequential=\(sequential.output)",
        "parallel=\(parallel.output)",
        "routed=\(routed.output)",
        "repeated=\(repeated.output)",
    ].joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "workflow.txt", contents: artifactBody)
    return .init(
        id: "workflow-core",
        name: "Workflow Core",
        families: [.workflowCore],
        status: .passed,
        summary: "Exercised sequential, parallel, route, repeatUntil, and timeout workflow APIs.",
        evidence: [
            .init(label: "workflow-results", detail: artifactBody, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runHandoffScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let billingProvider = ScriptedInferenceProvider(responses: ["Billing handled the refund request."])
    let billingAgent = try Agent("Billing specialist.", memory: makeScenarioMemory(), inferenceProvider: billingProvider)
    let triageProvider = ScriptedInferenceProvider(
        toolCallResponses: [
            .init(
                toolCalls: [
                    .init(
                        id: "handoff-1",
                        name: "handoff_to_billing",
                        arguments: ["reason": .string("refund request")]
                    ),
                ],
                finishReason: .toolCall
            ),
        ]
    )
    let triageAgent = try Agent(
        tools: [],
        instructions: "Route refund requests to billing.",
        memory: makeScenarioMemory(),
        inferenceProvider: triageProvider,
        handoffs: [
            AnyHandoffConfiguration(
                targetAgent: billingAgent,
                toolNameOverride: "handoff_to_billing",
                toolDescription: "Transfer the conversation to billing."
            ),
        ]
    )

    var sawRequest = false
    var finalOutput = ""

    for try await event in triageAgent.stream("I need a refund.") {
        switch event {
        case .handoff(.requested):
            sawRequest = true
        case .lifecycle(.completed(let result)):
            finalOutput = result.output
        default:
            break
        }
    }

    try ensure(sawRequest, "Expected a handoff request event.")
    try ensure(finalOutput.contains("Billing handled"), "Expected the specialist output after handoff.")

    let artifact = try context.writeArtifact(named: "handoff.txt", contents: finalOutput)
    return .init(
        id: "handoff",
        name: "Handoff",
        families: [.handoff],
        status: .passed,
        summary: "Delegated from a triage agent to a billing specialist via handoff tool routing.",
        evidence: [
            .init(label: "handoff-output", detail: finalOutput, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runMemoryScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let provider = ScriptedInferenceProvider(responses: ["Noted. Your preferred editor is Nova."])
    let memory = ConversationMemory(maxMessages: 10)
    let agent = try Agent("Keep track of user preferences.", memory: memory, inferenceProvider: provider)

    _ = try await agent.run("My preferred editor is Nova.")
    await memory.add(.assistant("Your preferred editor is Nova."))
    let recalled = await memory.context(for: "preferred editor", tokenLimit: 200)

    try ensure(recalled.contains("Nova"), "Expected memory context to retain Nova.")

    let artifact = try context.writeArtifact(named: "memory.txt", contents: recalled)
    return .init(
        id: "memory",
        name: "Memory",
        families: [.memory],
        status: .passed,
        summary: "Stored and recalled context through ConversationMemory.",
        evidence: [
            .init(label: "memory-context", detail: recalled, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runWorkspaceScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let workspaceRoot = context.artifactsDirectory.appendingPathComponent("workspace", isDirectory: true)
    let writableRoot = context.artifactsDirectory.appendingPathComponent("workspace-writable", isDirectory: true)
    let cacheRoot = context.artifactsDirectory.appendingPathComponent("workspace-cache", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    try writeWorkspaceFixture(at: workspaceRoot)

    let workspace = try AgentWorkspace(
        bundleRoot: workspaceRoot,
        writableRoot: writableRoot,
        indexCacheRoot: cacheRoot
    )

    let report = try await workspace.validate()
    try ensure(report.isValid, "Expected fixture workspace to validate cleanly.")

    let onDeviceProvider = ScriptedInferenceProvider(responses: ["Local workspace instructions loaded."])
    let onDeviceAgent = try Agent.onDevice(
        "Local helper instructions.",
        workspace: workspace,
        inferenceProvider: onDeviceProvider
    )
    _ = try await onDeviceAgent.run("hello")

    let specProvider = ScriptedInferenceProvider(responses: ["Spec instructions and skill context loaded."])
    let specAgent = try Agent.spec("support", in: workspace, inferenceProvider: specProvider)
    _ = try await specAgent.run("I need a refund")

    let onDevicePrompt = await onDeviceProvider.lastPrompt() ?? ""
    let specPrompt = await specProvider.lastPrompt() ?? ""
    try ensure(onDevicePrompt.contains("Global workspace rule."), "Expected AGENTS.md content in on-device prompt.")
    try ensure(specPrompt.contains("You are the support agent."), "Expected agent spec body in spec prompt.")
    try ensure(specPrompt.contains("refund window"), "Expected skill body to be retrieved into the spec prompt.")

    let writer = workspace.makeWriter()
    let noteURL = try await writer.recordFact(title: "Capability Showcase", content: "Workspace writer stored a fact.")
    try ensure(FileManager.default.fileExists(atPath: noteURL.path), "Expected workspace writer to persist a note.")

    let artifactBody = [
        "onDevicePromptContainsGlobal=\(onDevicePrompt.contains("Global workspace rule."))",
        "specPromptContainsSkill=\(specPrompt.contains("refund window"))",
        "note=\(noteURL.lastPathComponent)",
    ].joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "workspace.txt", contents: artifactBody)
    return .init(
        id: "workspace",
        name: "Workspace",
        families: [.workspace],
        status: .passed,
        summary: "Validated, loaded, and wrote through AgentWorkspace, Agent.onDevice, Agent.spec, and WorkspaceWriter.",
        evidence: [
            .init(label: "workspace", detail: artifactBody, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runGuardrailsScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let blockedProvider = ScriptedInferenceProvider(responses: ["This should never be returned."])
    let inputAgent = try Agent(
        "Reject sensitive input.",
        memory: makeScenarioMemory(),
        inferenceProvider: blockedProvider,
        inputGuardrails: [
            InputGuard("reject-ssn") { input, _ in
                input.contains("ssn") ? .tripwire(message: "Sensitive input blocked") : .passed()
            },
        ]
    )

    var inputBlocked = false
    do {
        _ = try await inputAgent.run("my ssn is 123")
    } catch {
        inputBlocked = true
    }
    try ensure(inputBlocked, "Expected the input guardrail to block execution.")

    let outputProvider = ScriptedInferenceProvider(responses: ["SECRET: do not reveal"])
    let outputAgent = try Agent(
        "Reject secret output.",
        memory: makeScenarioMemory(),
        inferenceProvider: outputProvider,
        outputGuardrails: [
            OutputGuard("reject-secret") { output, _, _ in
                output.contains("SECRET") ? .tripwire(message: "Secret output blocked") : .passed()
            },
        ]
    )

    var outputBlocked = false
    do {
        _ = try await outputAgent.run("respond")
    } catch {
        outputBlocked = true
    }
    try ensure(outputBlocked, "Expected the output guardrail to block execution.")

    let guardedTool = GuardedEchoTool()
    let registry = try ToolRegistry(tools: [guardedTool])
    let okResult = try await registry.execute(toolNamed: guardedTool.name, arguments: ["text": .string("safe")])
    try ensure(okResult.stringValue == "safe", "Expected guarded tool to pass on safe input.")

    var toolBlocked = false
    do {
        _ = try await registry.execute(toolNamed: guardedTool.name, arguments: ["text": .string("DROP TABLE users")])
    } catch {
        toolBlocked = true
    }
    try ensure(toolBlocked, "Expected the tool input guardrail to block unsafe input.")

    let artifactBody = "inputBlocked=\(inputBlocked)\noutputBlocked=\(outputBlocked)\ntoolBlocked=\(toolBlocked)"
    let artifact = try context.writeArtifact(named: "guardrails.txt", contents: artifactBody)
    return .init(
        id: "guardrails",
        name: "Guardrails",
        families: [.guardrails],
        status: .passed,
        summary: "Triggered agent input/output guardrails and tool guardrails deterministically.",
        evidence: [
            .init(label: "guardrails", detail: artifactBody, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runResilienceScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let retryCounter = AttemptCounter()
    let retryResult = try await RetryPolicy(maxAttempts: 2, backoff: .immediate).execute {
        let attempt = await retryCounter.incrementAndGet()
        if attempt < 3 {
            throw CapabilityShowcaseError.expectationFailed("retry \(attempt)")
        }
        return "recovered"
    }

    let fallbackResult = try await FallbackChain<String>()
        .attempt(name: "primary") {
            throw CapabilityShowcaseError.expectationFailed("primary unavailable")
        }
        .fallback(name: "cache", "fallback-ok")
        .execute()

    let limiter = RateLimiter(maxRequestsPerMinute: 1)
    let firstAcquire = await limiter.tryAcquire()
    let secondAcquire = await limiter.tryAcquire()

    let breaker = CircuitBreaker(name: "showcase-breaker", failureThreshold: 1, resetTimeout: 60)
    do {
        _ = try await breaker.execute {
            throw CapabilityShowcaseError.expectationFailed("boom")
        } as String
    } catch {}
    var breakerOpened = false
    do {
        _ = try await breaker.execute { "unreachable" }
    } catch let error as ResilienceError {
        breakerOpened = error == .circuitBreakerOpen(serviceName: "showcase-breaker")
    }

    try ensure(retryResult == "recovered", "Expected retry policy to recover.")
    try ensure(fallbackResult == "fallback-ok", "Expected fallback chain to return the fallback.")
    try ensure(firstAcquire && !secondAcquire, "Expected rate limiter to allow once and then reject.")
    try ensure(breakerOpened, "Expected circuit breaker to open after the failure threshold.")

    let artifactBody = [
        "retry=\(retryResult)",
        "fallback=\(fallbackResult)",
        "rateLimiter=\(firstAcquire),\(secondAcquire)",
        "breakerOpened=\(breakerOpened)",
    ].joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "resilience.txt", contents: artifactBody)
    return .init(
        id: "resilience",
        name: "Resilience",
        families: [.resilience],
        status: .passed,
        summary: "Exercised RetryPolicy, FallbackChain, RateLimiter, and CircuitBreaker.",
        evidence: [
            .init(label: "resilience", detail: artifactBody, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runDurableScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let provider = ScriptedInferenceProvider(responses: ["running", "done"])
    let agent = try Agent("Checkpoint progress.", memory: makeScenarioMemory(), inferenceProvider: provider)
    let checkpointing = WorkflowCheckpointing.inMemory()

    let workflow = Workflow()
        .step(agent)
        .repeatUntil(maxIterations: 5) { $0.output == "done" }
        .durable
        .checkpoint(id: "showcase-durable", policy: .everyStep)
        .durable
        .checkpointing(checkpointing)

    _ = try await workflow.durable.execute("start")
    let resumed = try await workflow.durable.execute("ignored", resumeFrom: "showcase-durable")

    try ensure(resumed.output == "done", "Expected resume to continue from the checkpoint.")

    let artifact = try context.writeArtifact(named: "durable.txt", contents: resumed.output)
    return .init(
        id: "durable",
        name: "Durable Execution",
        families: [.durable],
        status: .passed,
        summary: "Checkpointed and resumed a repeat-until workflow using in-memory durable storage.",
        evidence: [
            .init(label: "resumed-output", detail: resumed.output, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runObservabilityScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let tracer = RecordingTracer()
    let provider = ScriptedInferenceProvider(responses: ["Tracing is active."])
    let agent = try Agent("Trace this run.", memory: makeScenarioMemory(), inferenceProvider: provider, tracer: tracer)

    _ = try await agent.run("hello")
    let events = await tracer.snapshot()

    try ensure(events.contains(where: { $0.kind == .agentStart }), "Expected an agentStart trace event.")
    try ensure(events.contains(where: { $0.kind == .agentComplete }), "Expected an agentComplete trace event.")

    let artifactBody = events.map { String(describing: $0.kind) }.joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "trace.txt", contents: artifactBody)
    return .init(
        id: "observability",
        name: "Observability",
        families: [.observability],
        status: .passed,
        summary: "Captured trace events through a custom Tracer implementation.",
        evidence: [
            .init(label: "trace-events", detail: "Recorded \(events.count) events.", artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runMCPScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let discoveryServer = ShowcaseMCPServer(name: "showcase-discovery")
    await discoveryServer.setTools([
        ToolSchema(name: "lookup_note", description: "Lookup a note", parameters: []),
    ])

    let client = MCPClient()
    try await client.addServer(discoveryServer)
    let discovered = try await client.getAllTools()

    let bridgeServer = ShowcaseMCPServer(name: "showcase-bridge")
    await bridgeServer.setTools([
        ToolSchema(name: "lookup_note", description: "Lookup a note", parameters: []),
    ])
    let bridge = MCPToolBridge(server: bridgeServer)
    let bridgedTools = try await bridge.bridgeTools()
    let bridgedResult = try await bridgedTools[0].execute(arguments: ["query": .string("refund")])
    let invocations = await bridgeServer.callToolHistory

    try ensure(discovered.contains(where: { $0.name == "lookup_note" }), "Expected MCPClient to discover lookup_note.")
    try ensure(bridgedResult.stringValue == "result-from-showcase-bridge:lookup_note", "Expected bridged MCP tool execution to return the server result.")
    try ensure(invocations.count == 1, "Expected bridged tool execution to call the MCP server exactly once.")

    let artifactBody = [
        "discovered=\(discovered.map(\.name).joined(separator: ","))",
        "executed=\(bridgedResult.description)",
    ].joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "mcp.txt", contents: artifactBody)
    return .init(
        id: "mcp",
        name: "MCP",
        families: [.mcp],
        status: .passed,
        summary: "Discovered MCP tools through MCPClient and executed one through MCPToolBridge.",
        evidence: [
            .init(label: "mcp", detail: artifactBody, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

private func runProvidersScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let baseProvider = ScriptedInferenceProvider(responses: ["from base provider"])
    let baseAgent = try Agent("Use the supplied provider.", memory: makeScenarioMemory())
        .environment(\.inferenceProvider, baseProvider)
    let baseResult = try await baseAgent.run("hello")

    let overrideProvider = ScriptedInferenceProvider(responses: ["from override"])
    let overridden = try Agent("Use the override provider.", memory: makeScenarioMemory())
        .environment(\.inferenceProvider, overrideProvider)
    let overrideResult = try await overridden.run("hello")

    let fallbackProvider = ScriptedInferenceProvider(responses: ["from default provider"])
    let alternateProvider = ScriptedInferenceProvider(responses: ["from alternate provider"])
    let multiProvider = MultiProvider(defaultProvider: fallbackProvider)
    try await multiProvider.register(prefix: "alt", provider: alternateProvider)
    await multiProvider.setModel("alt/demo")
    let multiResponse = try await multiProvider.generate(prompt: "route", options: .default)

    try ensure(baseResult.output == "from base provider", "Expected the task-local provider to satisfy the base agent.")
    try ensure(overrideResult.output == "from override", "Expected a task-local provider override to be honored.")
    try ensure(multiResponse == "from alternate provider", "Expected MultiProvider to route by prefix.")

    let artifactBody = [
        "base=\(baseResult.output)",
        "override=\(overrideResult.output)",
        "multi=\(multiResponse)",
    ].joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "providers.txt", contents: artifactBody)
    return .init(
        id: "providers",
        name: "Providers",
        families: [.providers],
        status: .passed,
        summary: "Verified task-local provider wiring and MultiProvider routing.",
        evidence: [
            .init(label: "providers", detail: artifactBody, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

// MARK: - Smoke Scenario

private func runLiveProviderSmokeScenario(
    context: CapabilityScenarioContext
) async throws -> CapabilityScenarioResult {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
        guard let provider = FoundationModelsInferenceProvider.ifAvailable() else {
            return .init(
                id: "live-provider-smoke",
                name: "Live Provider Smoke",
                families: [.providers],
                status: .skipped,
                summary: "Apple Foundation Models are not available on this host."
            )
        }
        let agent = try Agent("Reply with the single word ok.", memory: makeScenarioMemory(), inferenceProvider: provider)
        let result = try await agent.run("Say ok.")
        let artifact = try context.writeArtifact(named: "live-provider-smoke.txt", contents: result.output)
        return .init(
            id: "live-provider-smoke",
            name: "Live Provider Smoke",
            families: [.providers],
            status: .passed,
            summary: "Ran a live Foundation Models smoke check.",
            evidence: [
                .init(label: "live-output", detail: result.output, artifactPath: context.relativeArtifactPath(for: artifact)),
            ]
        )
    }
    #endif

    return .init(
        id: "live-provider-smoke",
        name: "Live Provider Smoke",
        families: [.providers],
        status: .skipped,
        summary: "Live provider smoke requires Apple Foundation Models on a supported platform."
    )
}


// MARK: - Fixtures

@Tool("Adds two integers together.")
struct ShowcaseAdditionTool {
    @Parameter("Left-hand value") var lhs: Int = 0
    @Parameter("Right-hand value") var rhs: Int = 0

    func execute() async throws -> String {
        String(lhs + rhs)
    }
}

private struct GuardedEchoTool: AnyJSONTool {
    let name = "guarded_echo"
    let description = "Echoes text if it passes tool guardrails."
    let parameters = [
        ToolParameter(name: "text", description: "Text to echo", type: .string),
    ]
    let inputGuardrails: [any ToolInputGuardrail] = [
        ClosureToolInputGuardrail(name: "reject-sql") { data in
            if data.arguments["text"]?.stringValue?.contains("DROP TABLE") == true {
                return .tripwire(message: "SQL-like content blocked")
            }
            return .passed()
        },
    ]
    let outputGuardrails: [any ToolOutputGuardrail] = [
        ClosureToolOutputGuardrail(name: "require-text") { _, output in
            output.stringValue == nil ? .tripwire(message: "Missing text output") : .passed()
        },
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .string(arguments["text"]?.stringValue ?? "")
    }
}

actor ScriptedInferenceProvider: InferenceProvider {
    private var responses: [String]
    private var toolCallResponses: [InferenceResponse]
    private var responseIndex = 0
    private var toolCallIndex = 0
    private(set) var generateCalls: [(prompt: String, options: InferenceOptions)] = []
    private(set) var streamCalls: [(prompt: String, options: InferenceOptions)] = []
    private(set) var toolCallCalls: [(prompt: String, tools: [ToolSchema], options: InferenceOptions)] = []

    init(
        responses: [String] = [],
        toolCallResponses: [InferenceResponse] = []
    ) {
        self.responses = responses
        self.toolCallResponses = toolCallResponses
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        generateCalls.append((prompt, options))
        return nextTextResponse()
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        Task {
            do {
                let response = try await self.generateForStream(prompt: prompt, options: options)
                for character in response {
                    continuation.yield(String(character))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        toolCallCalls.append((prompt, tools, options))
        if toolCallIndex < toolCallResponses.count {
            let response = toolCallResponses[toolCallIndex]
            toolCallIndex += 1
            return response
        }
        return InferenceResponse(content: nextTextResponse(), finishReason: .completed)
    }

    func generatePrompts() -> [String] {
        generateCalls.map(\.prompt)
    }

    func lastPrompt() -> String? {
        if let prompt = toolCallCalls.last?.prompt {
            return prompt
        }
        if let prompt = generateCalls.last?.prompt {
            return prompt
        }
        return streamCalls.last?.prompt
    }

    private func generateForStream(prompt: String, options: InferenceOptions) async throws -> String {
        streamCalls.append((prompt, options))
        return nextTextResponse()
    }

    private func nextTextResponse() -> String {
        defer { responseIndex += 1 }
        guard responseIndex < responses.count else {
            return "ok"
        }
        return responses[responseIndex]
    }
}

private actor RecordingTracer: Tracer {
    private var events: [TraceEvent] = []

    func trace(_ event: TraceEvent) async {
        events.append(event)
    }

    func flush() async {}

    func snapshot() -> [TraceEvent] {
        events
    }
}

private actor AttemptCounter {
    private var value = 0

    func incrementAndGet() -> Int {
        value += 1
        return value
    }
}

private actor ShowcaseMCPServer: MCPServer {
    let name: String
    private var schemas: [ToolSchema] = []
    private var serverCapabilities: MCPCapabilities
    private(set) var callToolHistory: [(name: String, arguments: [String: SendableValue])] = []

    nonisolated var capabilities: MCPCapabilities {
        get async { await serverCapabilities }
    }

    init(name: String, capabilities: MCPCapabilities = MCPCapabilities(tools: true, resources: true)) {
        self.name = name
        serverCapabilities = capabilities
    }

    func setTools(_ schemas: [ToolSchema]) {
        self.schemas = schemas
    }

    func initialize() async throws -> MCPCapabilities {
        serverCapabilities
    }

    func close() async throws {}

    func listTools() async throws -> [ToolSchema] {
        schemas
    }

    func callTool(name: String, arguments: [String: SendableValue]) async throws -> SendableValue {
        callToolHistory.append((name: name, arguments: arguments))
        return .string("result-from-\(self.name):\(name)")
    }

    func listResources() async throws -> [MCPResource] {
        []
    }

    func readResource(uri: String) async throws -> MCPResourceContent {
        try MCPResourceContent(uri: uri, text: "")
    }
}

// MARK: - Helpers

private func makeTextAgent(output: String) -> Agent {
    let provider = ScriptedInferenceProvider(responses: [output])
    return try! Agent("Return deterministic output.", memory: makeScenarioMemory(), inferenceProvider: provider)
}

func makeScenarioMemory() -> any Memory {
    ConversationMemory(maxMessages: 32)
}

private func writeWorkspaceFixture(at root: URL) throws {
    try "Global workspace rule."
        .write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

    let agentDirectory = root.appendingPathComponent(".swarm/agents", isDirectory: true)
    let skillDirectory = root.appendingPathComponent(".swarm/skills/refund-policy", isDirectory: true)
    try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)

    let spec = """
    ---
    schema_version: 1
    id: support
    title: Support
    skills:
      - refund-policy
    revision: 1
    updated_at: 2026-04-08T00:00:00Z
    ---
    You are the support agent.
    """
    try spec.write(
        to: agentDirectory.appendingPathComponent("support.md"),
        atomically: true,
        encoding: .utf8
    )

    let skill = """
    ---
    name: refund-policy
    description: Handle refund and return questions.
    compatibility:
      - Swarm
    metadata:
      swarm.on-device-optimized: true
    ---
    If a user asks about a refund, confirm the order and explain the refund window.
    """
    try skill.write(
        to: skillDirectory.appendingPathComponent("SKILL.md"),
        atomically: true,
        encoding: .utf8
    )
}

func ensure(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw CapabilityShowcaseError.expectationFailed(message)
    }
}

public enum CapabilityShowcaseError: LocalizedError {
    case unknownScenario(String)
    case expectationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownScenario(let id):
            return "Unknown capability scenario '\(id)'."
        case .expectationFailed(let message):
            return message
        }
    }
}
