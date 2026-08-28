// APIAuditTests.swift
// SwarmTests
//
// Tests for API improvements: FunctionTool, AgentTool, isEnabled, handoffs.

import Foundation
@testable import Swarm
import XCTest

// MARK: - DisabledTool

/// A disabled tool for testing `isEnabled` filtering.
private struct DisabledTool: AnyJSONTool {
    let name = "disabled"
    let description = "A disabled tool"
    let parameters: [ToolParameter] = []

    var isEnabled: Bool { false }

    func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
        .null
    }
}

// MARK: - TestUserContext

/// A typed context for testing `AgentContextProviding`.
private struct TestUserContext: AgentContextProviding {
    static let contextKey = "test_user_context"

    let userId: String
    let isAdmin: Bool
}

// MARK: - TestSessionContext

/// A second typed context to test multiple typed contexts.
private struct TestSessionContext: AgentContextProviding {
    static let contextKey = "test_session_context"

    let sessionId: String
}

// MARK: - APIAuditTests

final class APIAuditTests: XCTestCase {
    // MARK: - FunctionTool Tests

    func testFunctionToolBasicExecution() async throws {
        let tool = FunctionTool(
            name: "greet",
            description: "Greets a user",
            parameters: [
                ToolParameter(name: "name", description: "User name", type: .string, isRequired: true)
            ]
        ) { args in
            let name = try args.require("name", as: String.self)
            return .string("Hello, \(name)!")
        }

        let result = try await tool.execute(arguments: ["name": .string("Alice")])
        XCTAssertEqual(result, .string("Hello, Alice!"))
    }

    func testFunctionToolNameAndDescription() {
        let tool = FunctionTool(
            name: "search",
            description: "Searches the web"
        ) { _ in .null }

        XCTAssertEqual(tool.name, "search")
        XCTAssertEqual(tool.description, "Searches the web")
    }

    func testFunctionToolDefaultParameters() {
        let tool = FunctionTool(
            name: "noop",
            description: "Does nothing"
        ) { _ in .null }

        XCTAssertTrue(tool.parameters.isEmpty)
    }

    func testFunctionToolWithMultipleParameters() async throws {
        let tool = FunctionTool(
            name: "calculate",
            description: "Basic math",
            parameters: [
                ToolParameter(name: "a", description: "First number", type: .int, isRequired: true),
                ToolParameter(name: "b", description: "Second number", type: .int, isRequired: true),
            ]
        ) { args in
            let a = try args.require("a", as: Int.self)
            let b = try args.require("b", as: Int.self)
            return .int(a + b)
        }

        let result = try await tool.execute(arguments: ["a": .int(3), "b": .int(7)])
        XCTAssertEqual(result, .int(10))
    }

    // MARK: - ToolArguments Tests

    func testToolArgumentsRequire() throws {
        let args = ToolArguments(["city": .string("Tokyo"), "count": .int(5)])
        let city: String = try args.require("city", as: String.self)
        let count: Int = try args.require("count", as: Int.self)

        XCTAssertEqual(city, "Tokyo")
        XCTAssertEqual(count, 5)
    }

    func testToolArgumentsRequireMissingKeyThrows() {
        let args = ToolArguments([:])
        XCTAssertThrowsError(try args.require("missing", as: String.self))
    }

    func testToolArgumentsRequireWrongTypeThrows() {
        let args = ToolArguments(["value": .int(42)])
        XCTAssertThrowsError(try args.require("value", as: String.self))
    }

    func testToolArgumentsOptional() {
        let args = ToolArguments(["name": .string("Alice")])
        let name: String? = args.optional("name", as: String.self)
        let missing: String? = args.optional("missing", as: String.self)

        XCTAssertEqual(name, "Alice")
        XCTAssertNil(missing)
    }

    func testToolArgumentsOptionalWrongTypeReturnsNil() {
        let args = ToolArguments(["value": .int(42)])
        let result: String? = args.optional("value", as: String.self)
        XCTAssertNil(result)
    }

    func testToolArgumentsStringWithDefault() {
        let args = ToolArguments(["greeting": .string("hi")])
        XCTAssertEqual(args.string("greeting", default: "hello"), "hi")
        XCTAssertEqual(args.string("missing", default: "hello"), "hello")
    }

    func testToolArgumentsIntWithDefault() {
        let args = ToolArguments(["count": .int(10)])
        XCTAssertEqual(args.int("count", default: 0), 10)
        XCTAssertEqual(args.int("missing", default: 0), 0)
    }

    // MARK: - Tool isEnabled Tests

    func testToolIsEnabledDefaultsToTrue() {
        let tool = MockTool(name: "enabled_tool", result: .string("ok"))
        XCTAssertTrue(tool.isEnabled)
    }

    func testDisabledToolIsEnabledReturnsFalse() {
        let tool = DisabledTool()
        XCTAssertFalse(tool.isEnabled)
    }

    func testToolRegistrySchemasFiltersByIsEnabled() async throws {
        let enabledTool = MockTool(name: "enabled", result: .string("ok"))
        let disabledTool = DisabledTool()

        let registry = try ToolRegistry(tools: [enabledTool, disabledTool])
        let schemas = await registry.schemas

        XCTAssertEqual(schemas.count, 1)
        XCTAssertEqual(schemas.first?.name, "enabled")
    }

    func testToolRegistryRejectsDisabledToolExecution() async throws {
        let disabledTool = DisabledTool()
        let registry = try ToolRegistry(tools: [disabledTool])

        do {
            _ = try await registry.execute(toolNamed: "disabled", arguments: [:])
            XCTFail("Expected toolNotFound error for disabled tool")
        } catch {
            // Disabled tools throw toolNotFound
            if let agentError = error as? AgentError {
                switch agentError {
                case .toolNotFound:
                    break // Expected
                default:
                    XCTFail("Unexpected error type: \(agentError)")
                }
            }
        }
    }

    // MARK: - Agent Name Convenience Init Tests

    func testAgentNameConvenienceInit() async throws {
        let agent = try Agent(name: "TestAgent", instructions: "You are helpful.")
        let name = agent.configuration.name
        XCTAssertEqual(name, "TestAgent")
    }

    func testAgentNameConvenienceInitPreservesInstructions() async throws {
        let agent = try Agent(name: "Helper", instructions: "Be concise.")
        let instructions = agent.instructions
        XCTAssertEqual(instructions, "Be concise.")
    }

    func testAgentNameAccessedViaRuntimeProperty() async throws {
        let agent = try Agent(name: "RuntimeName", instructions: "test")
        let name = agent.name
        XCTAssertEqual(name, "RuntimeName")
    }

    // MARK: - Agent handoffAgents Init Tests

    func testAgentHandoffAgentsInit() async throws {
        let billing = try Agent(name: "Billing", instructions: "Handle billing")
        let support = try Agent(name: "Support", instructions: "Handle support")

        let triage = try Agent(
            name: "Triage",
            instructions: "Route requests",
            handoffAgents: [billing, support]
        )

        let handoffs = triage.handoffs
        XCTAssertEqual(handoffs.count, 2)
    }

    func testAgentHandoffAgentsTargetsCorrectAgents() async throws {
        let billing = try Agent(name: "Billing", instructions: "Handle billing")
        let triage = try Agent(
            name: "Triage",
            instructions: "Route requests",
            handoffAgents: [billing]
        )

        let handoffs = triage.handoffs
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertEqual(handoffs.first?.targetAgent.name, "Billing")
    }

    // MARK: - Agent.Builder Canonical Handoff API Tests

    func testAgentBuilderHandoffToAddsSingleTarget() async throws {
        let billing = try Agent(name: "Billing", instructions: "Handle billing")

        let triage = try Agent.Builder()
            .instructions("Route requests")
            .handoff(to: billing)
            .build()

        let handoffs = triage.handoffs
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertEqual(handoffs.first?.targetAgent.name, "Billing")
    }

    func testAgentBuilderVariadicHandoffsAddsAllTargets() async throws {
        let billing = try Agent(name: "Billing", instructions: "Handle billing")
        let support = try Agent(name: "Support", instructions: "Handle support")
        let sales = try Agent(name: "Sales", instructions: "Handle sales")

        let triage = try Agent.Builder()
            .instructions("Route requests")
            .handoffs(billing, support, sales)
            .build()

        let handoffs = triage.handoffs
        XCTAssertEqual(handoffs.count, 3)
        XCTAssertEqual(handoffs[0].targetAgent.name, "Billing")
        XCTAssertEqual(handoffs[1].targetAgent.name, "Support")
        XCTAssertEqual(handoffs[2].targetAgent.name, "Sales")
    }

    func testAgentBuilderHandoffOptionsMapToConfiguration() async throws {
        let billing = try Agent(name: "Billing", instructions: "Handle billing")

        let triage = try Agent.Builder()
            .instructions("Route requests")
            .handoff(to: billing) {
                $0
                    .name("transfer_to_billing")
                    .description("Transfer billing/refund issues")
                    .policy(.strict)
                    .history(.summarized(maxTokens: 300))
            }
            .build()

        let handoffs = triage.handoffs
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertEqual(handoffs[0].toolNameOverride, "transfer_to_billing")
        XCTAssertEqual(handoffs[0].toolDescription, "Transfer billing/refund issues")
        XCTAssertTrue(handoffs[0].nestHandoffHistory)
    }

    // MARK: - AgentTool Tests

    func testAgentToolCreation() async throws {
        let innerAgent = try Agent(
            name: "Researcher",
            instructions: "Research topics",
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
            name: "Worker",
            instructions: "Work",
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

    func testAgentAsToolExtension() async throws {
        let agent = try Agent(
            name: "Helper",
            instructions: "Help users",
            inferenceProvider: MockInferenceProvider()
        )

        let tool = agent.asTool()
        XCTAssertEqual(tool.name, "helper")
        XCTAssertTrue(tool.description.contains("Helper"))
    }

    func testAgentAsToolWithCustomParams() async throws {
        let agent = try Agent(
            name: "Helper",
            instructions: "Help users",
            inferenceProvider: MockInferenceProvider()
        )

        let tool = agent.asTool(name: "my_helper", description: "My helper tool")
        XCTAssertEqual(tool.name, "my_helper")
        XCTAssertEqual(tool.description, "My helper tool")
    }

    func testAgentToolRejectsEmptyInput() async throws {
        let mock = MockInferenceProvider()
        await mock.setResponses(["Final Answer: done"])

        let innerAgent = try Agent(
            name: "Worker",
            instructions: "Work",
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

    // MARK: - AgentRuntime.name Tests

    func testAgentRuntimeNameDefaultsToConfigName() async throws {
        let config = AgentConfiguration(name: "ConfiguredName")
        let agent = try Agent(
            instructions: "test",
            configuration: config,
            inferenceProvider: MockInferenceProvider()
        )

        let name = agent.name
        XCTAssertEqual(name, "ConfiguredName")
    }

    func testAgentRuntimeNameDefaultName() async throws {
        let agent = try Agent(
            instructions: "test",
            inferenceProvider: MockInferenceProvider()
        )
        // Default configuration name is "Agent"
        let name = agent.name
        XCTAssertEqual(name, "Agent")
    }

    // MARK: - AgentRuntime.asHandoff() Tests

    func testAgentAsHandoffReturnsCorrectTarget() async throws {
        let agent = try Agent(
            name: "Billing",
            instructions: "Handle billing",
            inferenceProvider: MockInferenceProvider()
        )

        let handoff = agent.asHandoff()
        XCTAssertEqual(handoff.targetAgent.name, "Billing")
    }

    func testAgentAsHandoffWithCustomConfiguration() async throws {
        let agent = try Agent(
            name: "Support",
            instructions: "Handle support",
            inferenceProvider: MockInferenceProvider()
        )

        let handoff = agent.asHandoff {
            $0.name("transfer_to_support")
                .description("Transfer to support team")
        }

        XCTAssertEqual(handoff.toolNameOverride, "transfer_to_support")
        XCTAssertEqual(handoff.toolDescription, "Transfer to support team")
    }

    func testAgentAsHandoffDefaultsNilOverrides() async throws {
        let agent = try Agent(
            name: "Worker",
            instructions: "Work",
            inferenceProvider: MockInferenceProvider()
        )

        let handoff = agent.asHandoff()
        XCTAssertNil(handoff.toolNameOverride)
        XCTAssertNil(handoff.toolDescription)
        XCTAssertNil(handoff.onTransfer)
        XCTAssertNil(handoff.transform)
        XCTAssertNil(handoff.when)
        XCTAssertFalse(handoff.nestHandoffHistory)
    }

    // MARK: - AgentContextProviding Tests

    func testSetTypedAndRetrieveTyped() async {
        let context = AgentContext(input: "test")
        let userContext = TestUserContext(userId: "user_123", isAdmin: true)

        await context.setTyped(userContext)
        let retrieved: TestUserContext? = await context.typed(TestUserContext.self)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.userId, "user_123")
        XCTAssertEqual(retrieved?.isAdmin, true)
    }

    func testTypedReturnsNilWhenNotSet() async {
        let context = AgentContext(input: "test")
        let retrieved: TestUserContext? = await context.typed(TestUserContext.self)
        XCTAssertNil(retrieved)
    }

    func testHasTypedReturnsTrueWhenSet() async {
        let context = AgentContext(input: "test")
        await context.setTyped(TestUserContext(userId: "u1", isAdmin: false))

        let hasIt = await context.hasTyped(TestUserContext.self)
        XCTAssertTrue(hasIt)
    }

    func testHasTypedReturnsFalseWhenNotSet() async {
        let context = AgentContext(input: "test")
        let hasIt = await context.hasTyped(TestUserContext.self)
        XCTAssertFalse(hasIt)
    }

    func testRemoveTypedRemovesContext() async {
        let context = AgentContext(input: "test")
        await context.setTyped(TestUserContext(userId: "u1", isAdmin: false))

        let removed: TestUserContext? = await context.removeTyped(TestUserContext.self)
        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.userId, "u1")

        let afterRemoval: TestUserContext? = await context.typed(TestUserContext.self)
        XCTAssertNil(afterRemoval)
    }

    func testRemoveTypedReturnsNilWhenNotSet() async {
        let context = AgentContext(input: "test")
        let removed: TestUserContext? = await context.removeTyped(TestUserContext.self)
        XCTAssertNil(removed)
    }

    func testMultipleTypedContextsCoexist() async {
        let context = AgentContext(input: "test")
        await context.setTyped(TestUserContext(userId: "u1", isAdmin: true))
        await context.setTyped(TestSessionContext(sessionId: "s1"))

        let user: TestUserContext? = await context.typed(TestUserContext.self)
        let session: TestSessionContext? = await context.typed(TestSessionContext.self)

        XCTAssertEqual(user?.userId, "u1")
        XCTAssertEqual(session?.sessionId, "s1")
    }

    func testSetTypedOverwritesPrevious() async {
        let context = AgentContext(input: "test")
        await context.setTyped(TestUserContext(userId: "u1", isAdmin: false))
        await context.setTyped(TestUserContext(userId: "u2", isAdmin: true))

        let retrieved: TestUserContext? = await context.typed(TestUserContext.self)
        XCTAssertEqual(retrieved?.userId, "u2")
        XCTAssertEqual(retrieved?.isAdmin, true)
    }

    // MARK: - AgentContext Basic Tests

    func testAgentContextInitialization() async {
        let context = AgentContext(input: "Hello")
        let input = context.originalInput
        XCTAssertEqual(input, "Hello")
    }

    func testAgentContextInitialValues() async {
        let context = AgentContext(
            input: "test",
            initialValues: ["key": .string("value")]
        )
        let value = await context.get("key")
        XCTAssertEqual(value, .string("value"))
    }

    // MARK: - AgentConfiguration.defaultTracingEnabled Tests

    func testDefaultTracingEnabledDefaultsToTrue() {
        let config = AgentConfiguration()
        XCTAssertTrue(config.defaultTracingEnabled)
    }

    func testDefaultTracingEnabledCanBeSetToFalse() {
        let config = AgentConfiguration(defaultTracingEnabled: false)
        XCTAssertFalse(config.defaultTracingEnabled)
    }

    func testDefaultTracingEnabledViaBuilder() {
        let config = AgentConfiguration.default.defaultTracingEnabled(false)
        XCTAssertFalse(config.defaultTracingEnabled)
    }

    func testDefaultTracingEnabledExplicitlyTrue() {
        let config = AgentConfiguration(defaultTracingEnabled: true)
        XCTAssertTrue(config.defaultTracingEnabled)
    }

    // MARK: - FunctionTool as AnyJSONTool Tests

    func testFunctionToolConformsToAnyJSONTool() {
        let tool: any AnyJSONTool = FunctionTool(
            name: "test",
            description: "A test tool"
        ) { _ in .null }

        XCTAssertEqual(tool.name, "test")
        XCTAssertEqual(tool.description, "A test tool")
        XCTAssertTrue(tool.isEnabled)
    }

    func testFunctionToolSchema() {
        let tool = FunctionTool(
            name: "lookup",
            description: "Look up a value",
            parameters: [
                ToolParameter(name: "key", description: "The key", type: .string, isRequired: true)
            ]
        ) { _ in .null }

        let schema = tool.schema
        XCTAssertEqual(schema.name, "lookup")
        XCTAssertEqual(schema.description, "Look up a value")
        XCTAssertEqual(schema.parameters.count, 1)
    }

    // MARK: - ToolRegistry with Mixed Enabled/Disabled Tools

    func testToolRegistryMixedEnabledDisabled() async throws {
        let tool1 = MockTool(name: "tool_a", result: .string("a"))
        let tool2 = DisabledTool()
        let tool3 = MockTool(name: "tool_c", result: .string("c"))

        let registry = try ToolRegistry(tools: [tool1, tool2, tool3])

        // allTools should include all
        let allTools = await registry.allTools
        XCTAssertEqual(allTools.count, 3)

        // schemas should exclude disabled
        let schemas = await registry.schemas
        XCTAssertEqual(schemas.count, 2)
        let schemaNames = schemas.map(\.name)
        XCTAssertTrue(schemaNames.contains("tool_a"))
        XCTAssertTrue(schemaNames.contains("tool_c"))
        XCTAssertFalse(schemaNames.contains("disabled"))
    }

    // MARK: - SendableValue Equality in Tests

    func testSendableValueEquality() {
        XCTAssertEqual(SendableValue.string("hello"), SendableValue.string("hello"))
        XCTAssertEqual(SendableValue.int(42), SendableValue.int(42))
        XCTAssertEqual(SendableValue.double(3.14), SendableValue.double(3.14))
        XCTAssertEqual(SendableValue.bool(true), SendableValue.bool(true))
        XCTAssertEqual(SendableValue.null, SendableValue.null)
        XCTAssertNotEqual(SendableValue.string("a"), SendableValue.string("b"))
    }
}
