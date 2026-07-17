#if canImport(FoundationModels)
import Foundation
import FoundationModels
@testable import Swarm
import Testing

@Suite("FoundationModels Tool Calling Tests")
struct FoundationModelsToolCallingTests {
    @Test("LanguageModelSession delegates tool requests to native bridge")
    func languageModelSessionAcceptsToolRequests() async throws {
        guard ProcessInfo.processInfo.environment["SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS"] == "1" else {
            return
        }
        guard #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) else {
            return
        }

        guard SystemLanguageModel.default.availability == .available else {
            return
        }

        let session = LanguageModelSession()
        let tools = [
            ToolSchema(
                name: "lookup",
                description: "Look up information",
                parameters: [
                    ToolParameter(name: "query", description: "Search query", type: .string),
                ]
            ),
        ]

        let response = try await session.generateWithToolCalls(
            prompt: "Use the lookup tool to search for Swift concurrency right now.",
            tools: tools,
            options: InferenceOptions(toolChoice: .required)
        )

        #expect(response.finishReason == .toolCall || response.finishReason == .completed)
        #expect(!response.toolCalls.isEmpty || response.content != nil)
        if response.finishReason == .toolCall {
            #expect(response.toolCalls.first?.name == "lookup")
            #expect(response.toolCalls.first?.arguments["query"] != nil)
        }
    }
}
#endif
