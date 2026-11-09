import Foundation
import Testing
@testable import Swarm

/// `prompt_tokens_details.cached_tokens` and
/// `completion_tokens_details.reasoning_tokens` reach ``TokenUsage`` on every
/// chunk decoding path.
@Suite("OpenAI-compatible usage details")
struct OpenAICompatibleUsageDetailsTests {
    private static let detailedUsage = """
    {"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":50,\
    "prompt_tokens_details":{"cached_tokens":96},\
    "completion_tokens_details":{"reasoning_tokens":32}}}
    """

    private static let expected = TokenUsage(
        inputTokens: 120,
        outputTokens: 50,
        cachedInputTokens: 96,
        reasoningTokens: 32
    )

    @Test("Fail-closed stream decoding reads cached and reasoning tokens")
    func streamDecodingReadsDetails() throws {
        let chunk = try OpenAICompatibleChatChunk(jsonData: Data(Self.detailedUsage.utf8))
        #expect(chunk.usage == Self.expected)
    }

    @Test("Typed wire decoding reads cached and reasoning tokens")
    func wireDecodingReadsDetails() throws {
        let wire = try JSONDecoder().decode(OpenAICompatibleWire.Chunk.self, from: Data(Self.detailedUsage.utf8))
        #expect(wire.usage?.cachedTokens == 96)
        #expect(wire.usage?.reasoningTokens == 32)
        #expect(OpenAICompatibleChatChunk(wire: wire).usage == Self.expected)
    }

    @Test("Lenient fallback decoding reads cached and reasoning tokens")
    func lenientDecodingReadsDetails() {
        // A numeric `id` fails typed decoding and forces the lenient parse.
        let chunk = OpenAICompatibleChatChunk(json: [
            "id": 5,
            "choices": [] as [Any],
            "usage": [
                "prompt_tokens": 120,
                "completion_tokens": 50,
                "prompt_tokens_details": ["cached_tokens": 96],
                "completion_tokens_details": ["reasoning_tokens": 32],
            ] as [String: Any],
        ])
        #expect(chunk.usage == Self.expected)
    }

    @Test("Missing or mistyped details leave the breakdowns nil")
    func missingOrMistypedDetails() throws {
        let plain = try OpenAICompatibleChatChunk(jsonData: Data(
            #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":6}}"#.utf8
        ))
        #expect(plain.usage == TokenUsage(inputTokens: 3, outputTokens: 6))

        let mistyped = try OpenAICompatibleChatChunk(jsonData: Data(
            #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":6,"prompt_tokens_details":"n/a","completion_tokens_details":{"reasoning_tokens":"x"}}}"#.utf8
        ))
        #expect(mistyped.usage == TokenUsage(inputTokens: 3, outputTokens: 6))
    }
}
