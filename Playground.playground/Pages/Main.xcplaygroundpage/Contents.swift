/*:
 # SwiftAgents Playground
 
 Welcome to **SwiftAgents**! This interactive playground lets you explore
 the framework's key features for building AI agents in Swift.
 
 ## Getting Started
 
 1. Build the project with **⌘ + B**
 2. Run the playground with the **▶️** button
 3. Experiment with the examples below!
 
 ---
 */

import SwiftAgents
import Foundation
import PlaygroundSupport


// Required for async operations in playgrounds
PlaygroundPage.current.needsIndefiniteExecution = true

//: ## 1. Creating a Custom Tool
//: Tools extend your agent's capabilities. Here's a weather lookup example:

//struct WeatherTool: Tool, Sendable {
//    let name = "weather_lookup"
//    let description = "Looks up the current weather for a given city."
//    
//    let parameters: [ToolParameter] = [
//        ToolParameter(
//            name: "city",
//            description: "The city name (e.g., 'San Francisco')",
//            type: .string,
//            isRequired: true
//        )
//    ]
//    
//    mutating func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
//        let city = try requiredString("city", from: arguments)
//        let conditions = ["sunny", "cloudy", "rainy"].randomElement() ?? "clear"
//        let temp = Int.random(in: 15...30)
//        
//        return .dictionary([
//            "city": .string(city),
//            "temperature": .int(temp),
//            "conditions": .string(conditions),
//            "description": .string("Currently \(conditions) in \(city) at \(temp)°C")
//        ])
//    }
//}

//: ## 2. Creating a Custom Memory
//: Memory maintains conversation context across turns:

actor SimpleMemory: Memory {
    private var messages: [MemoryMessage] = []
    private let maxMessages: Int
    
    init(maxMessages: Int = 20) {
        self.maxMessages = maxMessages
    }
    
    var count: Int { messages.count }
    var isEmpty: Bool { messages.isEmpty }
    
    func add(_ message: MemoryMessage) async {
        messages.append(message)
        if messages.count > maxMessages {
            messages.removeFirst()
        }
    }
    
    func context(for query: String, tokenLimit: Int) async -> String {
        formatMessagesForContext(messages, tokenLimit: tokenLimit)
    }
    
    func allMessages() async -> [MemoryMessage] { messages }
    func clear() async { messages.removeAll() }
}

//: ## 3. Run Hooks for Observability
//: Monitor agent execution with custom hooks:

actor LoggingHooks: RunHooks {
    private var logs: [String] = []
    
    func onAgentStart(context: AgentContext?, agent: any Agent, input: String) async {
        let log = "🚀 Agent started: \(input.prefix(40))..."
        logs.append(log)
        print(log)
    }
    
    func onAgentEnd(context: AgentContext?, agent: any Agent, result: AgentResult) async {
        let duration = Double(result.duration.components.seconds)
        let log = "✅ Completed in \(String(format: "%.2f", duration))s"
        logs.append(log)
        print(log)
    }
    
    func onToolStart(context: AgentContext?, agent: any Agent, tool: String, input: [String: SendableValue]) async {
        print("🔧 Using tool: \(tool)")
    }
    
    func onToolEnd(context: AgentContext?, agent: any Agent, tool: String, result: SendableValue) async {
        print("📦 Tool \(tool) completed")
    }
    
    func onThinking(context: AgentContext?, agent: any Agent, thought: String) async {
        print("💭 \(thought.prefix(60))...")
    }
    
    func onError(context: AgentContext?, agent: any Agent, error: Error) async {
        print("❌ Error: \(error.localizedDescription)")
    }
    
    func getLogs() -> [String] { logs }
}

//: ## 4. Input Guardrails
//: Validate and filter inputs before the agent processes them:

struct ContentFilter: InputGuardrail {
    let name = "content_filter"
    let blockedPatterns: [String]
    
    init(blockedPatterns: [String] = ["spam"]) {
        self.blockedPatterns = blockedPatterns
    }
    
    func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
        let lower = input.lowercased()
        for pattern in blockedPatterns {
            if lower.contains(pattern) {
                return .tripwire(message: "Blocked: '\(pattern)'")
            }
        }
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .tripwire(message: "Input cannot be empty")
        }
        return .passed(metadata: ["validated": .bool(true)])
    }
}

//: ## 5. Output Guardrails
//: Sanitize agent responses:

struct PIIRedactor: OutputGuardrail {
    let name = "pii_redactor"
    
    func validate(_ output: String, agent: any Agent, context: AgentContext?) async throws -> GuardrailResult {
        var redacted = output
        
        // Redact email patterns
        let emailPattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = regex.stringByReplacingMatches(in: redacted, range: range, withTemplate: "[EMAIL]")
        }
        
        return .passed(metadata: [
            "redacted": .bool(redacted != output),
            "output": .string(redacted)
        ])
    }
}

//: ## 6. Agent Configuration Presets
//: Different configurations for various use cases:

enum Configs {
    static var fast: AgentConfiguration {
        AgentConfiguration(maxIterations: 3, timeout: .seconds(15))
    }
    
    static var thorough: AgentConfiguration {
        AgentConfiguration(maxIterations: 10, timeout: .seconds(120))
    }
    
    static var creative: AgentConfiguration {
        AgentConfiguration(
            maxIterations: 5,
            timeout: .seconds(60),
            modelSettings: ModelSettings(temperature: 0.9)
        )
    }
}

//: ## 7. Mock Provider for Testing
//: Test without API calls:

struct MockProvider: InferenceProvider {
    let responses: [String]
    
    init(responses: [String] = ["This is a mock response."]) {
        self.responses = responses
    }
    
    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await Task.sleep(for: .milliseconds(50))
        return responses.randomElement() ?? "Mock response"
    }
    
    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let response = responses.randomElement() ?? "Mock"
        return AsyncThrowingStream { c in
            Task {
                for char in response { c.yield(String(char)) }
                c.finish()
            }
        }
    }
    
    func generateWithToolCalls(
        prompt: String,
        tools: [ToolDefinition],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await Task.sleep(for: .milliseconds(50))
        return InferenceResponse(
            content: responses.randomElement() ?? "Mock",
            toolCalls: [],
            finishReason: .completed
        )
    }
}

/*:
 ## 8. Building a Complete Agent
 
 Now let's put it all together! Uncomment the code below and replace
 the provider with your real API key to try it out.
 */

Task { @MainActor in
    // Create a mock provider (replace with real provider for actual use)
    let provider = MockProvider(responses: [
        "Hello! I'm your SwiftAgents assistant.",
        "The weather in Tokyo is sunny at 25°C.",
        "I can help you with various tasks!"
    ])
    
    // Build the agent
    let agent = ReActAgent.Builder()
        .inferenceProvider(provider)
        .instructions("You are a helpful assistant. Be concise.")
        .configuration(Configs.fast)
        .addTool(DateTimeTool())
        .addTool(StringTool())
        .memory(SimpleMemory())
        .inputGuardrails([ContentFilter()])
        .outputGuardrails([PIIRedactor()])
        .build()
    
    // Run with hooks for observability
    let hooks = LoggingHooks()
    
    do {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Running agent...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        let result = try await agent.run("Hello, what can you help me with?", hooks: hooks)
        
        print("\n📝 Output: \(result.output)")
        print("⏱  Duration: \(result.duration)")
        print("🔄 Iterations: \(result.iterationCount)")
        
    } catch {
        print("Error: \(error)")
    }
    
    // Uncomment to try streaming:
    /*
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("Streaming response...")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    for try await event in agent.stream("Tell me about the weather") {
        switch event {
        case .thinking(let thought):
            print("💭 \(thought.prefix(50))...")
        case .outputChunk(let text):
            print(text, terminator: "")
        case .completed(let result):
            print("\n✨ Done in \(result.duration)")
        default:
            break
        }
    }
    */
}

/*:
 ## Using a Real Provider
 
 To use a real AI provider, replace `MockProvider` with:
 
 ```swift
 let provider = OpenRouterProvider(
     configuration: .init(
         apiKey: "your-api-key",
         model: .claude35Sonnet
     )
 )
 ```
 
 ---
 
 ## Next Steps
 
 - Check out the [documentation](https://github.com/yourusername/SwiftAgents)
 - Explore more tools in `BuiltInTools`
 - Try building your own custom agent!
 
 Happy coding! 🚀
 */
