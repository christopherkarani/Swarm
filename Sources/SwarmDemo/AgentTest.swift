import Foundation
import Swarm

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(AnyLanguageModel) && SWARM_DEMO_ANYLANGUAGEMODEL
import AnyLanguageModel
#endif

// Welcome to Swarm Playground!
// ---------------------------------
// 1. Open Swarm.xcworkspace in Xcode.
// 2. Select the 'Swarm' scheme (for macOS).
// 3. Build the scheme (Cmd + B).
// 4. Run this playground.

@main
struct MyApp {
    static func main() async {
        Log.bootstrap()
        print("🚀 Starting Swarm Playground...")

        // MARK: - Provider: Apple Foundation Models (on-device, macOS 26+)
        let inferenceProvider: any InferenceProvider
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
            let session = LanguageModelSession()
            print("✅ Using Apple Foundation Models (on-device)")
            inferenceProvider = session
        } else {
            print("❌ Apple Foundation Models are unavailable. Swarm's only built-in backend is Foundation Models.")
            print("   Inject a custom InferenceProvider for other backends.")
            return
        }
        #else
        print("❌ Foundation Models not supported on this platform.")
        print("   Inject a custom InferenceProvider for other backends.")
        return
        #endif

        // MARK: - Tools: built-in only (no API keys required)
        let searchTool = WebSearchTool.fromEnvironment()
        print("Search tool initialized: \(searchTool.name)")

        let tools: [any AnyJSONTool] = [
            searchTool,
            StringTool(),
            DateTimeTool(),
            CalculatorTool(),
        ]

        // MARK: - Agent
        let input = """
        Conduct deep research on Metal 4 and MLX for Apple Silicon. Cover:

        1. Metal 4 — new compute pipeline (MTL4CommandBuffer, MTL4ComputeCommandEncoder, MTL4ArgumentTable), residency sets, barriers, Shader ML, GPU Neural Accelerators, MSL 4.0 features, and ray tracing improvements. Include a minimal compute shader example showing the new dispatch pattern.

        2. MLX — array framework for Apple Silicon. Explain how it differs from PyTorch/Metal, its lazy evaluation model, automatic differentiation, and how to build/train a simple neural network in Swift or Python. Include a code example.

        3. How Metal 4 and MLX complement each other — when to use raw Metal vs MLX for on-device inference, fine-tuning, and training.

        4. Performance considerations — memory management, kernel dispatch overhead, quantization, and ANE vs GPU vs CPU routing.

        Provide a comprehensive technical report with code examples for each section.
        """

        let agent: Agent
        do {
            var config = AgentConfiguration.default
                .maxIterations(50)

            // For Foundation Models (4096 token window), enforce strict context management:
            // 1. strict4k activates PromptEnvelope truncation (keeps head + tail, cuts middle)
            // 2. Membrane pointerizes tool results > 1KB into 240-char summaries + pointers
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), SystemLanguageModel.default.availability == .available {
                config = config.contextProfile(.strict4k)
                print("📐 Context profile: strict4k (Membrane pointer + PromptEnvelope truncation)")
            }
            #endif

            agent = try Agent(
                tools: tools,
                instructions: """
                You are a senior Apple Silicon ML/GPU engineer conducting deep research.
                Use the websearch tool to find the latest WWDC sessions, Apple documentation, and GitHub repos.
                Always search for current information before answering.
                Provide detailed, technically accurate responses with working code examples.
                Structure your response with clear sections and subsections.
                """,
                configuration: config,
                inferenceProvider: inferenceProvider,
                tracer: ConsoleTracer()
            )
        } catch {
            fatalError("Failed to create agent: \(error)")
        }

        do {
            for try await event in agent.stream(input) {
                switch event {
                // Lifecycle
                case .lifecycle(.started(input: let input)):
                    print("Agent started with input: \(input.prefix(80))...")
                case .lifecycle(.completed(result: let result)):
                    print("🏁 Finished with reason: \(result.output)")
                case .lifecycle(.failed(error: let error)):
                    print("❌ Agent failed: \(error)")
                case .lifecycle(.cancelled):
                    print("⚠️ Agent cancelled")
                case .lifecycle(.guardrailFailed(error: let error)):
                    print("❌ Guardrail failed: \(error)")
                case .lifecycle(.iterationStarted), .lifecycle(.iterationCompleted):
                    break

                // Output
                case .output(.thinking(thought: let text)):
                    print(text, terminator: "")
                case .output(.thinkingPartial(let text)):
                    print(text, terminator: "")
                case .output(.token):
                    break
                case .output(.chunk(let chunk)):
                    print(chunk, terminator: "")

                // Tool calls
                case .tool(.started(call: let call)):
                    print("-> Calling \"\(call.toolName)\" with \(call.arguments)")
                case .tool(.partial):
                    break
                case .tool(.completed(call: let tool, result: let result)):
                    print("✅ Tool \"\(tool.toolName)\" returned: \(result.output)")
                case .tool(.failed(call: let tool, error: let error)):
                    print("❌ Tool \"\(tool.toolName)\" failed: \(error)")

                // Handoffs
                case .handoff(.requested(from: let from, to: let to, reason: let reason)):
                    print("Handoff requested: \(from) -> \(to) (\(reason ?? "no reason"))")
                case .handoff(.started(from: let from, to: let to, input: _)):
                    print("Handoff started: \(from) -> \(to)")
                case .handoff(.completed(from: let from, to: let to)):
                    print("Handoff completed: \(from) -> \(to)")
                case .handoff(.completedWithResult(from: let from, to: let to, result: _)):
                    print("Handoff completed with result: \(from) -> \(to)")
                case .handoff(.skipped(from: let from, to: let to, reason: let reason)):
                    print("Handoff skipped: \(from) -> \(to) (\(reason))")

                // Observation
                case .observation(.decision(let decision, options: _)):
                    print("Decision: \(decision)")
                case .observation(.planUpdated(let plan, stepCount: let steps)):
                    print("Plan updated (\(steps) steps): \(plan.prefix(80))...")
                case .observation(.guardrailStarted(name: let name, type: _)):
                    print("Guardrail started: \(name)")
                case .observation(.guardrailPassed(name: let name, type: _)):
                    print("Guardrail passed: \(name)")
                case .observation(.guardrailTriggered(name: let name, type: _, message: let msg)):
                    print("⚠️ Guardrail triggered: \(name) — \(msg ?? "")")
                case .observation(.memoryAccessed(operation: let op, count: let count)):
                    print("Memory \(op): \(count) items")
                case .observation(.llmStarted), .observation(.llmCompleted):
                    break
                }
            }
        } catch {
            print("Error: \(error)")
        }
    }
}

// Proper InferenceProvider conformance for LanguageModelSession
#if canImport(AnyLanguageModel) && SWARM_DEMO_ANYLANGUAGEMODEL
extension LanguageModelSession: InferenceProvider {
    public func generate(prompt: String, options _: InferenceOptions) async throws -> String {
        let response = try await respond(to: prompt)
        return response.content
    }

    public func stream(prompt: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await respond(to: prompt)
                    continuation.yield(response.content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateWithToolCalls(
        prompt: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        let response = try await respond(to: prompt)
        return InferenceResponse(
            content: response.content,
            toolCalls: [],
            finishReason: .completed
        )
    }
}
#endif
