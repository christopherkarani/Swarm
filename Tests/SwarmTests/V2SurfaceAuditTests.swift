// V2SurfaceAuditTests.swift
// SwarmTests
//
// Build-only tests that lock the v2 public API surface.
// These tests use plain `import Swarm` (not @testable) to verify that
// every referenced type is genuinely public — not just test-accessible.
// A compilation failure here means a public API was accidentally hidden.

import Foundation
import Swarm
import Testing

// MARK: - V2 Surface Audit

/// Verifies the v2 public API surface of the Swarm framework.
///
/// These are compile-time contracts: each test instantiates or references a
/// key public symbol. If any symbol is demoted to internal, the test suite
/// fails to build, catching the regression before it ships.
@Suite("V2 API Surface Audit")
struct V2SurfaceAuditTests {

    // MARK: - Version

    @Test("Swarm.version is 0.6.2")
    func versionIsV2() {
        #expect(Swarm.version == "0.6.2")
    }

    // MARK: - TokenUsage (module-level, not nested)

    @Test("TokenUsage is public at module level")
    func tokenUsagePublic() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 20)
        #expect(usage.inputTokens == 10)
        #expect(usage.outputTokens == 20)
        #expect(usage.totalTokens == 30)
    }

    @Test("TokenUsage is Codable")
    func tokenUsageCodable() throws {
        let usage = TokenUsage(inputTokens: 5, outputTokens: 15)
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(TokenUsage.self, from: data)
        #expect(decoded == usage)
    }

    // MARK: - MemoryMessage.formatContext (free function → static method)

    @Test("MemoryMessage.formatContext static method is public")
    func memoryMessageFormatContextPublic() {
        let messages: [MemoryMessage] = [
            MemoryMessage(role: .user, content: "Hello"),
            MemoryMessage(role: .assistant, content: "Hi there"),
        ]
        let context = MemoryMessage.formatContext(messages, tokenLimit: 1000)
        #expect(!context.isEmpty)
    }

    @Test("MemoryMessage.formatContext with separator is public")
    func memoryMessageFormatContextWithSeparatorPublic() {
        let messages: [MemoryMessage] = [
            MemoryMessage(role: .user, content: "A"),
            MemoryMessage(role: .assistant, content: "B"),
        ]
        let context = MemoryMessage.formatContext(messages, tokenLimit: 1000, separator: "\n---\n")
        #expect(context.contains("---"))
    }

    // MARK: - WorkflowCheckpointing factory methods

    @Test("WorkflowCheckpointing.inMemory() factory is public")
    func workflowCheckpointingInMemoryPublic() {
        let checkpointing = WorkflowCheckpointing.inMemory()
        _ = checkpointing
    }

    @Test("WorkflowCheckpointing.fileSystem(directory:) factory is public")
    func workflowCheckpointingFileSystemPublic() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-audit-test", isDirectory: true)
        let checkpointing = WorkflowCheckpointing.fileSystem(directory: url)
        _ = checkpointing
    }

    // MARK: - AgentResult public init

    @Test("AgentResult public init is accessible")
    func agentResultPublicInit() {
        let usage = TokenUsage(inputTokens: 1, outputTokens: 2)
        let result = AgentResult(
            output: "test",
            toolCalls: [],
            toolResults: [],
            iterationCount: 1,
            duration: .zero,
            tokenUsage: usage,
            metadata: [:]
        )
        #expect(result.output == "test")
        #expect(result.tokenUsage == usage)
    }

    @Test("AgentResult.runtimeEngine metadata helper is public")
    func agentResultRuntimeEnginePublic() {
        let result = AgentResult(
            output: "test",
            metadata: ["runtime.engine": .string("graph")]
        )
        #expect(result.runtimeEngine == "graph")
    }

    // MARK: - AnyHandoffConfiguration (retained after HandoffBuilder removal)

    @Test("AnyHandoffConfiguration stays public at module level")
    func anyHandoffConfigurationPublic() {
        let erased = AnyHandoffConfiguration(
            targetAgent: MockAgentRuntime(),
            toolNameOverride: nil,
            toolDescription: nil,
            onTransfer: nil,
            transform: nil,
            when: nil,
            nestHandoffHistory: false
        )
        #expect(erased.nestHandoffHistory == false)
        #expect(!erased.effectiveToolName.isEmpty)
    }

    @Test("AnyHandoffConfiguration erases a typed configuration")
    func anyHandoffConfigurationTypeErasurePublic() {
        let erased = AnyHandoffConfiguration(
            targetAgent: MockAgentRuntime(instructions: "Specialist")
        )
        #expect(erased.effectiveToolName == "handoff_to_mock_agent_runtime")
        #expect(erased.effectiveToolDescription.contains("MockAgentRuntime"))
    }
}
