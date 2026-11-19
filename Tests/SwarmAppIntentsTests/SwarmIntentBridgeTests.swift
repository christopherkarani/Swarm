// SwarmIntentBridgeTests.swift
// SwarmAppIntentsTests
//
// Platform-independent tests for the runtime that @IntentTool / @AgentIntent
// generated code calls into.

import Foundation
import SwarmAppIntents
import Testing

// MARK: - Fixtures

@Tool("Echoes a greeting")
struct GreetingTool {
    @Parameter("Who to greet")
    var person: String = ""

    @Parameter("Greeting word", default: "Hello")
    var greeting: String = "Hello"

    @Parameter("Exclamation count", default: 1)
    var excitement: Int = 1

    func execute() async throws -> String {
        "\(greeting), \(person)" + String(repeating: "!", count: excitement)
    }
}

struct Forecast: Codable, Sendable {
    let city: String
    let highs: [Double]
}

@Tool("Returns a structured forecast")
struct ForecastTool {
    @Parameter("City")
    var city: String = ""

    @Parameter("Scale factor")
    var scale: Float = 1

    func execute() async throws -> Forecast {
        Forecast(city: city, highs: [20 * Double(scale), 21 * Double(scale)])
    }
}

@Tool("Counts list items")
struct CountTool {
    @Parameter("Items")
    var items: [String] = []

    @Parameter("Optional label")
    var label: String?

    func execute() async throws -> Int {
        items.count + (label == nil ? 0 : 100)
    }
}

struct GuardedTool: Tool {
    struct Input: Codable, Sendable { let text: String }
    typealias Output = String

    let name = "guarded"
    let description = "Rejects the word 'secret'"
    let parameters = [ToolParameter(name: "text", description: "Text", type: .string, isRequired: true)]

    var inputGuardrails: [any ToolInputGuardrail] {
        [ClosureToolInputGuardrail(name: "no_secrets") { data in
            data.arguments["text"]?.stringValue == "secret"
                ? .tripwire(message: "secret content")
                : .passed()
        }]
    }

    func execute(_ input: Input) async throws -> String { input.text }
}

struct StubAgent: AgentRuntime {
    enum Failure: Error { case boom }

    let reply: @Sendable (String) throws -> String

    var tools: [any AnyJSONTool] { [] }
    var instructions: String { "stub" }
    var configuration: AgentConfiguration { .default }

    func run(_ input: String, session _: (any Session)?, observer _: (any AgentObserver)?) async throws -> AgentResult {
        try AgentResult(output: reply(input))
    }

    func stream(
        _ input: String,
        session _: (any Session)?,
        observer _: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}

// MARK: - Tool bridge

@Suite("SwarmIntentBridge tools")
struct SwarmIntentBridgeToolTests {
    @Test("Forwards arguments and applies tool defaults for omitted ones")
    func forwardsArgumentsAndDefaults() async throws {
        let output = try await SwarmIntentBridge.run(GreetingTool(), arguments: ["person": .string("Ada")])
        #expect(output == "Hello, Ada!")

        let custom = try await SwarmIntentBridge.run(
            GreetingTool(),
            arguments: ["person": .string("Ada"), "greeting": .string("Hi"), "excitement": .int(3)]
        )
        #expect(custom == "Hi, Ada!!!")
    }

    @Test("Generated-style argument encoding drops nil optionals so defaults apply")
    func generatedStyleEncoding() async throws {
        let greeting: String? = nil
        var arguments: [String: SendableValue] = [:]
        arguments["person"] = SwarmIntentArgument.encode("Grace")
        arguments["greeting"] = SwarmIntentArgument.encode(greeting)
        #expect(arguments["greeting"] == nil)

        let output = try await SwarmIntentBridge.run(GreetingTool(), arguments: arguments)
        #expect(output == "Hello, Grace!")
    }

    @Test("Structured output renders as sorted, pretty JSON; Float params accept Double")
    func structuredOutput() async throws {
        let output = try await SwarmIntentBridge.run(
            ForecastTool(),
            arguments: ["city": .string("Oslo"), "scale": SwarmIntentArgument.encode(Float(0.5))!]
        )
        let decoded = try JSONDecoder().decode(Forecast.self, from: Data(output.utf8))
        #expect(decoded.city == "Oslo")
        #expect(decoded.highs == [10, 10.5])
        #expect(output.contains("\n"))
        #expect(try #require(output.range(of: "\"city\"")).lowerBound < #require(output.range(of: "\"highs\"")).lowerBound)
    }

    @Test("Arrays and optionals round-trip")
    func arraysAndOptionals() async throws {
        let none = try await SwarmIntentBridge.run(
            CountTool(),
            arguments: ["items": SwarmIntentArgument.encode(["a", "b", "c"])!]
        )
        #expect(none == "3")

        let labeled = try await SwarmIntentBridge.run(
            CountTool(),
            arguments: [
                "items": SwarmIntentArgument.encode([String]())!,
                "label": SwarmIntentArgument.encode(Optional("x"))!,
            ]
        )
        #expect(labeled == "100")
    }

    @Test("Missing required arguments surface as toolFailed")
    func missingRequiredArgument() async {
        await #expect {
            _ = try await SwarmIntentBridge.run(GuardedTool(), arguments: [:])
        } throws: { error in
            guard case let .toolFailed(toolName, _) = error as? SwarmIntentError else { return false }
            return toolName == "guarded"
        }
    }

    @Test("Tool input guardrails still run when invoked from an intent")
    func guardrailsApply() async throws {
        #expect(try await SwarmIntentBridge.run(GuardedTool(), arguments: ["text": .string("fine")]) == "fine")

        await #expect {
            _ = try await SwarmIntentBridge.run(GuardedTool(), arguments: ["text": .string("secret")])
        } throws: { error in
            guard case let .toolFailed(toolName, _) = error as? SwarmIntentError else { return false }
            return toolName == "guarded"
        }
    }
}

// MARK: - Rendering & encoding

@Suite("SwarmIntentBridge rendering")
struct SwarmIntentBridgeRenderingTests {
    @Test("Scalars render naturally and null renders as Done.")
    func scalars() {
        #expect(SwarmIntentBridge.render(.string("hi")) == "hi")
        #expect(SwarmIntentBridge.render(.int(42)) == "42")
        #expect(SwarmIntentBridge.render(.double(1.5)) == "1.5")
        #expect(SwarmIntentBridge.render(.bool(true)) == "true")
        #expect(SwarmIntentBridge.render(.null) == "Done.")
    }

    @Test("Collections render as sorted JSON")
    func collections() {
        #expect(SwarmIntentBridge.render(.array([.int(1), .string("a/b")])) == "[\n  1,\n  \"a/b\"\n]")
        #expect(SwarmIntentBridge.render(["b": .int(2), "a": .int(1)]) == "{\n  \"a\" : 1,\n  \"b\" : 2\n}")
    }

    @Test("Argument encoding covers every supported intent type")
    func argumentEncoding() {
        #expect(SwarmIntentArgument.encode("x") == .string("x"))
        #expect(SwarmIntentArgument.encode(7) == .int(7))
        #expect(SwarmIntentArgument.encode(2.5) == .double(2.5))
        #expect(SwarmIntentArgument.encode(Float(0.25)) == .double(0.25))
        #expect(SwarmIntentArgument.encode(false) == .bool(false))
        #expect(SwarmIntentArgument.encode([1, 2]) == .array([.int(1), .int(2)]))
        #expect(SwarmIntentArgument.encode(Int?.none) == nil)
        #expect(SwarmIntentArgument.encode(Int?.some(3)) == .int(3))
        #expect(SwarmIntentArgument.encode([Bool]?.some([true])) == .array([.bool(true)]))
    }
}

// MARK: - Agent bridge

@Suite("SwarmIntentBridge agents")
struct SwarmIntentBridgeAgentTests {
    @Test("Returns the agent's output for the prompt")
    func runsAgent() async throws {
        let agent = StubAgent { "You said: \($0)" }
        #expect(try await SwarmIntentBridge.run(agent: agent, prompt: "hi") == "You said: hi")
    }

    @Test("Accepts an existential agent")
    func existentialAgent() async throws {
        let agent: any AgentRuntime = StubAgent { $0.uppercased() }
        #expect(try await SwarmIntentBridge.run(agent: agent, prompt: "hey") == "HEY")
    }

    @Test("Agent failures surface as agentFailed")
    func agentFailure() async {
        let agent = StubAgent { _ in throw StubAgent.Failure.boom }
        await #expect {
            _ = try await SwarmIntentBridge.run(agent: agent, prompt: "x")
        } throws: { error in
            guard case .agentFailed = error as? SwarmIntentError else { return false }
            return true
        }
    }

    @Test("Error messages are user-presentable")
    func errorMessages() {
        let error = SwarmIntentError.toolFailed(toolName: "weather", reason: "offline")
        #expect(error.errorDescription == "The weather action failed: offline")
        #expect(SwarmIntentError.agentNotFound(id: "x").errorDescription == "No assistant named \"x\" is available.")
    }
}

// MARK: - Directory

@Suite("SwarmAgentDirectory")
struct SwarmAgentDirectoryTests {
    @Test("Keeps registration order and replaces in place")
    func registrationOrder() {
        let directory = SwarmAgentDirectory()
        directory.register(StubAgent { $0 }, id: "a", name: "Alpha")
        directory.register(StubAgent { $0 }, id: "b", name: "Beta", summary: "Second")
        directory.register(StubAgent { $0 }, id: "a", name: "Alpha 2")

        #expect(directory.entries.map(\.id) == ["a", "b"])
        #expect(directory.entries.map(\.name) == ["Alpha 2", "Beta"])

        directory.unregister(id: "a")
        #expect(directory.entries.map(\.id) == ["b"])
    }

    @Test("Looks up by identifier in request order and ignores unknown ids")
    func lookupByIdentifier() {
        let directory = SwarmAgentDirectory()
        directory.register(StubAgent { $0 }, id: "a", name: "Alpha")
        directory.register(StubAgent { $0 }, id: "b", name: "Beta")
        #expect(directory.entries(ids: ["b", "missing", "a"]).map(\.id) == ["b", "a"])
    }

    @Test("Matches name or summary case- and diacritic-insensitively")
    func matching() {
        let directory = SwarmAgentDirectory()
        directory.register(StubAgent { $0 }, id: "travel", name: "Travel Planner", summary: "Plans trips")
        directory.register(StubAgent { $0 }, id: "cafe", name: "Café Finder")

        #expect(directory.entries(matching: "planner").map(\.id) == ["travel"])
        #expect(directory.entries(matching: "TRIPS").map(\.id) == ["travel"])
        #expect(directory.entries(matching: "cafe").map(\.id) == ["cafe"])
        #expect(directory.entries(matching: "  ").count == 2)
    }

    @Test("Builds a fresh agent per request and reports unknown ids")
    func makeAgent() async throws {
        let directory = SwarmAgentDirectory()
        let counter = Counter()
        directory.register(id: "echo", name: "Echo") {
            await counter.increment()
            return StubAgent { $0 }
        }

        let agent = try await directory.makeAgent(id: "echo")
        #expect(try await SwarmIntentBridge.run(agent: agent, prompt: "ping") == "ping")
        _ = try await directory.makeAgent(id: "echo")
        #expect(await counter.value == 2)

        await #expect(throws: SwarmIntentError.agentNotFound(id: "nope")) {
            _ = try await directory.makeAgent(id: "nope")
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
