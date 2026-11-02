import Foundation
@testable import Swarm
import Testing

@Suite("InferenceMessage.Body")
struct InferenceMessageBodyTests {
    private let call = InferenceMessage.ToolCall(id: "1", name: "calc", arguments: [:])

    @Test("Assistant body projects role, content, and tool calls")
    func assistantBodyProjectsAccessors() {
        let message = InferenceMessage(body: .assistant("ok", toolCalls: [call]))

        #expect(message.role == .assistant)
        #expect(message.content == "ok")
        #expect(message.toolCalls == [call])
        #expect(message.name == nil)
        #expect(message.toolCallID == nil)
    }

    @Test("Tool factory stores name and call id on body")
    func toolFactoryStoresNameAndCallID() {
        let message = InferenceMessage.tool(name: "calc", content: "4", toolCallID: "x")

        #expect(message.body == .tool(name: "calc", content: "4", toolCallID: "x"))
        #expect(message.role == .tool)
        #expect(message.content == "4")
        #expect(message.name == "calc")
        #expect(message.toolCallID == "x")
        #expect(message.toolCalls.isEmpty)
    }

    @Test("Factories construct through body")
    func factoriesConstructThroughBody() {
        #expect(InferenceMessage.system("s").body == .system("s"))
        #expect(InferenceMessage.user("u").body == .user("u"))
        #expect(InferenceMessage.assistant("a").body == .assistant("a", toolCalls: []))
        #expect(
            InferenceMessage.assistant("a", toolCalls: [call]).body
                == .assistant("a", toolCalls: [call])
        )
    }

    @Test("Replacing content on a user message keeps a user body")
    func envelopeReplaceKeepsUserBodyWithoutToolCalls() async {
        let last = InferenceMessage.user(String(repeating: "u", count: 40))
        let budget = 20

        let fitted = await ContextWindow.fit(
            messages: [last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: false,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted.count == 1)
        #expect(fitted[0].role == .user)
        guard case .user = fitted[0].body else {
            Issue.record("expected user body after replace, got \(fitted[0].body)")
            return
        }
        #expect(fitted[0].toolCalls.isEmpty)
        #expect(fitted[0].name == nil)
        #expect(fitted[0].toolCallID == nil)
        #expect(fitted[0].content.count < last.content.count)
    }

    @Test("Replacing content on a system message keeps a system body")
    func envelopeReplaceKeepsSystemBodyWithoutToolCalls() async {
        let last = InferenceMessage.system(String(repeating: "s", count: 40))
        let budget = 20

        let fitted = await ContextWindow.fit(
            messages: [last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: true,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted.count == 1)
        guard case .system = fitted[0].body else {
            Issue.record("expected system body after replace, got \(fitted[0].body)")
            return
        }
        #expect(fitted[0].toolCalls.isEmpty)
        #expect(fitted[0].name == nil)
        #expect(fitted[0].toolCallID == nil)
    }

    @Test("Stubbing older tool results keeps a tool body without toolCalls")
    func envelopeStubKeepsToolBodyWithoutToolCalls() async {
        let padding = String(repeating: "p", count: 800)
        let messages: [InferenceMessage] = [
            .system("Stay."),
            .tool(name: "websearch", content: "old-search \(padding)", toolCallID: "a"),
            .tool(name: "fetch_url", content: "old-page \(padding)", toolCallID: "b"),
            .tool(name: "calc", content: "old-calc \(padding)", toolCallID: "z"),
            .tool(name: "websearch", content: "recent-search", toolCallID: "c"),
            .tool(name: "fetch_url", content: "recent-page", toolCallID: "d"),
            .user("needle-latest"),
        ]

        let result = await PromptEnvelope.enforce(
            messages: messages,
            profile: .lite(maxContextTokens: 400)
        )
        let stubbed = result.filter { $0.content == PromptEnvelope.omittedToolResult }

        #expect(!stubbed.isEmpty)
        for message in stubbed {
            guard case let .tool(name, content, toolCallID) = message.body else {
                Issue.record("expected tool body after stub, got \(message.body)")
                return
            }
            #expect(content == PromptEnvelope.omittedToolResult)
            #expect(message.toolCalls.isEmpty)
            #expect(name == "websearch" || name == "fetch_url" || name == "calc")
            #expect(toolCallID == "a" || toolCallID == "b" || toolCallID == "z")
        }
    }

    @Test("Replacing assistant content keeps the legal toolCalls payload")
    func envelopeReplaceKeepsAssistantToolCalls() async {
        let last = InferenceMessage(
            body: .assistant(String(repeating: "a", count: 40), toolCalls: [call])
        )
        let budget = 20

        let fitted = await ContextWindow.fit(
            messages: [last],
            policy: ContextWindow.Policy(
                maxTokens: budget,
                protectLeadingSystem: false,
                alwaysKeepLast: true
            ),
            countTokens: characterCount
        )

        #expect(fitted.count == 1)
        guard case let .assistant(_, toolCalls) = fitted[0].body else {
            Issue.record("expected assistant body after replace, got \(fitted[0].body)")
            return
        }
        #expect(toolCalls == [call])
        #expect(fitted[0].content.count < last.content.count)
    }

    @Test("Transcript init switches on body")
    func transcriptInitSwitchesOnBody() {
        let userMessage = AgentTurnTranscript.Message(.user("hi"))
        #expect(userMessage.inferenceMessage.body == .user("hi"))
        #expect(userMessage.inferenceMessage.toolCalls.isEmpty)

        let assistant = InferenceMessage(body: .assistant("ok", toolCalls: [call]))
        let assistantMessage = AgentTurnTranscript.Message(assistant)
        #expect(assistantMessage.inferenceMessage.toolCalls == [call])
        #expect(assistantMessage.inferenceMessage.role == .assistant)

        let tool = InferenceMessage.tool(name: "calc", content: "4", toolCallID: "x")
        let toolMessage = AgentTurnTranscript.Message(tool)
        #expect(toolMessage.inferenceMessage.body == .tool(name: "calc", content: "4", toolCallID: "x"))
    }
}

private func characterCount(_ text: String) async -> Int {
    do {
        return try await CharacterCountTokenCounter().countTokens(in: text)
    } catch {
        Issue.record("CharacterCountTokenCounter is not expected to throw")
        return text.count
    }
}

/// Deterministic fake ``PromptTokenCounter``: one token per character.
private struct CharacterCountTokenCounter: PromptTokenCounter {
    func countTokens(in text: String) async throws -> Int {
        text.count
    }
}
