// AgentToolTests.swift
// SwarmTests
//
// Tests for AgentTool and the .asTool() extension.

import Foundation
@testable import Swarm
import XCTest

final class AgentToolTests: XCTestCase {
    // MARK: - AgentTool Creation Tests

    func testAgentToolCreation() async throws {
        let innerAgent = try Agent(
            "Research topics",
            configuration: .default.name("Researcher"),
            inferenceProvider: MockInferenceProvider()
        )

        let tool = AgentTool(agent: innerAgent)
        XCTAssertEqual(tool.name, "researcher")
        XCTAssertTrue(tool.description.contains("Researcher"))
        XCTAssertEqual(tool.parameters.count, 1)
        XCTAssertEqual(tool.parameters.first?.name, "input")
        XCTAssertEqual(tool.parameters.first?.type, .string)
    }

    func testAgentToolCustomNameAndDescription() async throws {
        let innerAgent = try Agent(
            "Work",
            configuration: .default.name("Worker"),
            inferenceProvider: MockInferenceProvider()
        )

        let tool = AgentTool(
            agent: innerAgent,
            name: "custom_worker",
            description: "A custom worker tool"
        )

        XCTAssertEqual(tool.name, "custom_worker")
        XCTAssertEqual(tool.description, "A custom worker tool")
    }

    // MARK: - .asTool() Extension Tests

    func testAgentAsToolExtension() async throws {
        let agent = try Agent(
            "Help users",
            configuration: .default.name("Helper"),
            inferenceProvider: MockInferenceProvider()
        )

        let tool = agent.asTool()
        XCTAssertEqual(tool.name, "helper")
        XCTAssertTrue(tool.description.contains("Helper"))
    }

    func testAgentAsToolWithCustomParams() async throws {
        let agent = try Agent(
            "Help users",
            configuration: .default.name("Helper"),
            inferenceProvider: MockInferenceProvider()
        )

        let tool = agent.asTool(name: "my_helper", description: "My helper tool")
        XCTAssertEqual(tool.name, "my_helper")
        XCTAssertEqual(tool.description, "My helper tool")
    }

    // MARK: - AgentTool Execution Tests

    func testAgentToolRejectsEmptyInput() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["Final Answer: done"])

        let innerAgent = try Agent(
            "Work",
            configuration: .default.name("Worker"),
            inferenceProvider: mock
        )

        let tool = AgentTool(agent: innerAgent)

        do {
            _ = try await tool.execute(arguments: ["input": .string("")])
            XCTFail("Expected error for empty input")
        } catch {
            // Expected: invalid tool arguments
        }
    }

    func testAgentToolRejectsMissingInput() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["Final Answer: done"])

        let innerAgent = try Agent(
            "Work",
            configuration: .default.name("Worker"),
            inferenceProvider: mock
        )

        let tool = AgentTool(agent: innerAgent)

        do {
            _ = try await tool.execute(arguments: [:])
            XCTFail("Expected error for missing input")
        } catch {
            // Expected: invalid tool arguments
        }
    }

    // MARK: - AgentTool Name Derivation Tests

    func testAgentToolNameDerivedFromAgentName() async throws {
        let agent = try Agent(
            "Research",
            configuration: .default.name("MyResearchAgent"),
            inferenceProvider: MockInferenceProvider()
        )

        let tool = AgentTool(agent: agent)
        // camelCase to snake_case
        XCTAssertEqual(tool.name, "my_research_agent")
    }

    func testAgentToolNameFallbackForEmptyAgentName() async throws {
        let agent = try Agent(
            instructions: "Test",
            configuration: AgentConfiguration(name: ""),
            inferenceProvider: MockInferenceProvider()
        )

        let tool = AgentTool(agent: agent)
        XCTAssertEqual(tool.name, "agent_tool")
    }
}
