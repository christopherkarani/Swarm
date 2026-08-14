import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("OpenAI-compatible Linux agent loop")
struct OpenAICompatibleAgentLoopTests {
    @Test("Agent run executes tools against an OpenAI-compatible fixture")
    func agentRunExecutesTools() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }

        OpenAICompatibleURLProtocol.handle { _, body in
            let object = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let messages = object["messages"] as? [[String: Any]] ?? []
            let hasToolResult = messages.contains { ($0["role"] as? String) == "tool" }
            if hasToolResult {
                return .init(
                    status: 200,
                    headers: ["Content-Type": "application/json"],
                    body: Data(Self.finalJSON.utf8)
                )
            }
            return .init(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(Self.toolCallJSON.utf8)
            )
        }

        let provider = OpenAICompatibleProvider(
            configuration: .init(
                baseURL: URL(string: "https://api.example.test/v1")!,
                model: "fixture-model"
            ),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        let agent = try Agent(
            "Use the add tool.",
            inferenceProvider: provider
        ) {
            FunctionTool(
                name: "add",
                description: "Adds two integers",
                parameters: [
                    ToolParameter(name: "a", description: "First addend", type: .int),
                    ToolParameter(name: "b", description: "Second addend", type: .int),
                ]
            ) { args in
                let a = try args.require("a", as: Int.self)
                let b = try args.require("b", as: Int.self)
                return .int(a + b)
            }
        }

        let result = try await agent.run("What is 2+3?")
        #expect(result.output.contains("5"))
        #expect(result.tokenUsage == TokenUsage(inputTokens: 20, outputTokens: 8))
        #expect(OpenAICompatibleURLProtocol.requests.count == 2)
    }

    @Test("Agent stream assembles tool-call deltas then final tokens")
    func agentStreamAssemblesToolCallsAndTokens() async throws {
        OpenAICompatibleURLProtocol.reset()
        defer { OpenAICompatibleURLProtocol.reset() }

        OpenAICompatibleURLProtocol.handle { _, body in
            let object = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            let messages = object["messages"] as? [[String: Any]] ?? []
            let hasToolResult = messages.contains { ($0["role"] as? String) == "tool" }
            let sse = hasToolResult ? Self.finalSSE : Self.toolCallSSE
            return .init(
                status: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(sse.utf8)
            )
        }

        let provider = OpenAICompatibleProvider(
            configuration: .init(
                baseURL: URL(string: "https://api.example.test/v1")!,
                model: "fixture-model"
            ),
            session: OpenAICompatibleURLProtocol.makeSession()
        )
        let agent = try Agent(
            "Use the add tool.",
            inferenceProvider: provider
        ) {
            FunctionTool(
                name: "add",
                description: "Adds two integers",
                parameters: [
                    ToolParameter(name: "a", description: "First addend", type: .int),
                    ToolParameter(name: "b", description: "Second addend", type: .int),
                ]
            ) { args in
                let a = try args.require("a", as: Int.self)
                let b = try args.require("b", as: Int.self)
                return .int(a + b)
            }
        }

        var tokens: [String] = []
        var sawTool = false
        for try await event in agent.stream("What is 2+3?") {
            switch event {
            case let .output(.token(token)):
                tokens.append(token)
            case .tool(.completed):
                sawTool = true
            default:
                break
            }
        }

        #expect(sawTool)
        #expect(tokens.joined().contains("5"))
        #expect(OpenAICompatibleURLProtocol.requests.count >= 2)
        let firstBody = try OpenAICompatibleJSON.object(
            from: OpenAICompatibleURLProtocol.requests[0].body
        )
        #expect(firstBody["stream"] as? Bool == true)
    }

    private static let toolCallJSON = """
    {
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "id": "call_add",
                "type": "function",
                "function": { "name": "add", "arguments": "{\\"a\\":2,\\"b\\":3}" }
              }
            ]
          },
          "finish_reason": "tool_calls"
        }
      ],
      "usage": { "prompt_tokens": 12, "completion_tokens": 4 }
    }
    """

    private static let finalJSON = """
    {
      "choices": [
        {
          "index": 0,
          "message": { "role": "assistant", "content": "The sum is 5." },
          "finish_reason": "stop"
        }
      ],
      "usage": { "prompt_tokens": 8, "completion_tokens": 4 }
    }
    """

    private static let toolCallSSE = """
    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_add","function":{"name":"add","arguments":""}}]}}]}

    data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"a\\":2,\\"b\\":3}"}}]}}]}

    data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

    data: [DONE]

    """

    private static let finalSSE = """
    data: {"choices":[{"delta":{"content":"The sum is "}}]}

    data: {"choices":[{"delta":{"content":"5."}}]}

    data: {"choices":[{"delta":{}}],"usage":{"prompt_tokens":8,"completion_tokens":4}}

    data: [DONE]

    """
}
