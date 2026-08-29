// ZombieAPIRemovalTests.swift
// SwarmTests
//
// V3 zombie API removal tracking. Commented sections must NOT compile once removals are done.

import Testing
@testable import Swarm

// These must NOT compile once removals are done.
// Comment them in one at a time and confirm compile failure,
// then re-comment and move on. This file serves as the
// removal checklist — each line represents a type to delete.

// AnyAgent — must not exist after Task 2
// let _: AnyAgent = AnyAgent(someAgent as! any AgentRuntime & Sendable)

// AnyTool — must not exist after Task 3
// let _: AnyTool = AnyTool(someTool)

// AgentBuilder — removed in Task 5 (AgentBuilder.swift deleted)
// Verified: AgentBuilder, Instructions, Tools, AgentMemory, Configuration,
// InferenceProviderComponent, TracerConfig, InputGuardrails, OutputGuardrails,
// Handoffs, ParallelToolCalls, PreviousResponseId, AutoPreviousResponseId,
// ModelSettingsComponent, MCPClientConfig — all removed.

@Suite("V3 Zombie API Removal")
struct ZombieAPIRemovalTests {
    @Test("Agent can be created without legacy builder")
    func agentCreatedWithoutBuilder() throws {
        // V3 init path: instructions-first
        let agent = try Agent(
            tools: [],
            instructions: "Be helpful."
        )
        #expect(agent.instructions == "Be helpful.")
    }
}
