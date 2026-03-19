#if canImport(FoundationModels)
    import Foundation
    import FoundationModels
    @testable import Swarm
    import Testing

    @Suite("FoundationModels Tool Calling Tests")
    struct FoundationModelsToolCallingTests {
        @Test("LanguageModelSession no longer rejects tool requests outright")
        func languageModelSessionAcceptsToolRequests() async throws {
            guard #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) else {
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
                )
            ]

            let response = try await session.generateWithToolCalls(
                prompt: "Use the lookup tool to search for Swift concurrency. If you call a tool, reply with JSON only.",
                tools: tools,
                options: .default
            )

            #expect(response.finishReason == .toolCall || response.finishReason == .completed)
            #expect(!response.toolCalls.isEmpty || response.content != nil)
        }
    }
#endif
