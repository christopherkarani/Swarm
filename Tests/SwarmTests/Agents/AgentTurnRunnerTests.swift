// AgentTurnRunnerTests.swift
// SwarmTests
//
// Runner-owned turn progress: admission applies the iteration and clears
// per-iteration resolution.

@testable import Swarm
import Testing

struct AgentTurnRunnerTests {
    @Test("Admission applies the iteration and clears per-iteration resolution")
    func admitClearsPerIterationResolution() {
        var progress = AgentTurnRunner.TurnProgress(
            iteration: 1,
            maxIterations: 3,
            mode: .hostTools(streaming: false),
            hasToolSchemas: true
        )
        progress.admit(iteration: 2)
        #expect(progress == AgentTurnRunner.TurnProgress(
            iteration: 2,
            maxIterations: 3,
            mode: nil,
            hasToolSchemas: false
        ))
    }
}
