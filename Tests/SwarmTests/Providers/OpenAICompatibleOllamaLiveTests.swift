import Foundation
import Testing
@testable import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum OpenAICompatibleOllamaLiveGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SWARM_OLLAMA_LIVE_TESTS"] == "1"
    }

    static var baseURL: URL {
        let raw = ProcessInfo.processInfo.environment["SWARM_OLLAMA_BASE_URL"]
            ?? "http://127.0.0.1:11434/v1"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:11434/v1")!
    }

    static var model: String {
        ProcessInfo.processInfo.environment["SWARM_OLLAMA_MODEL"] ?? "llama3.2"
    }
}

@Suite("OpenAI-compatible Ollama live tests")
struct OpenAICompatibleOllamaLiveTests {
    @Test(
        "Live Ollama generate returns text",
        .enabled(if: OpenAICompatibleOllamaLiveGate.isEnabled)
    )
    func liveOllamaGenerateReturnsText() async throws {
        let provider = OpenAICompatibleProvider(
            configuration: .ollama(
                model: OpenAICompatibleOllamaLiveGate.model,
                baseURL: OpenAICompatibleOllamaLiveGate.baseURL
            )
        )
        let text = try await provider.generate(
            messages: [.user("Reply with the single word pong.")],
            options: .precise.maxTokens(32)
        )
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test(
        "Live Ollama streaming yields at least one chunk",
        .enabled(if: OpenAICompatibleOllamaLiveGate.isEnabled)
    )
    func liveOllamaStreamingYieldsChunks() async throws {
        let provider = OpenAICompatibleProvider(
            configuration: .ollama(
                model: OpenAICompatibleOllamaLiveGate.model,
                baseURL: OpenAICompatibleOllamaLiveGate.baseURL
            )
        )
        var chunks: [String] = []
        for try await chunk in provider.stream(
            messages: [.user("Reply with the single word pong.")],
            options: .precise.maxTokens(32)
        ) {
            chunks.append(chunk)
        }
        #expect(!chunks.isEmpty)
        #expect(!chunks.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
