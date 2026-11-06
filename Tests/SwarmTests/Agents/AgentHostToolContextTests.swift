import Foundation
@testable import Swarm
import Testing

@Suite("Host tool loop context", .ephemeralDefaultStores)
struct AgentHostToolContextTests {

    @Test("Host-loop tools receive the run's execution context")
    func hostLoopToolsReceiveExecutionContext() async throws {
        let recorder = ToolContextRecorder()
        let guardrail = ClosureToolInputGuardrail(name: "record_context") { data in
            await recorder.record(data.context?.originalInput)
            return .passed()
        }
        let provider = MockInferenceProvider()
        await provider.setToolCallResponses([
            InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(id: "call_1", name: "lookup", arguments: [:]),
                ],
                finishReason: .toolCall,
                usage: nil
            ),
            InferenceResponse(content: "done", finishReason: .completed),
        ])
        let agent = try Agent(
            tools: [MockTool(name: "lookup", inputGuardrails: [guardrail])],
            instructions: "Use the tool.",
            configuration: AgentConfiguration(name: "agent", defaultTracingEnabled: false),
            inferenceProvider: provider
        )

        _ = try await agent.run("find it")

        #expect(await recorder.inputs == ["find it"])
    }
}

private actor ToolContextRecorder {
    private(set) var inputs: [String?] = []

    func record(_ input: String?) {
        inputs.append(input)
    }
}
