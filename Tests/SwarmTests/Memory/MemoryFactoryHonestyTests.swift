// MemoryFactoryHonestyTests.swift
// SwarmTests
//
// Overload resolution and honest summarizer-default tests for Memory factories.

import Foundation
@testable import Swarm
import Testing

@Suite("Memory factory honesty")
struct MemoryFactoryHonestyTests {
    @Test(".persistent(backend:) resolves to PersistentMemory without the deprecated overload")
    func persistentExplicitBackendResolves() async {
        let backend = InMemoryBackend()
        let memory: PersistentMemory = .persistent(
            backend: backend,
            conversationId: "honesty-session",
            maxMessages: 7
        )
        #expect(await memory.conversationId == "honesty-session")
        #expect(await memory.maxMessages == 7)
        await memory.add(.user("hello"))
        #expect(await memory.allMessages().map(\.content) == ["hello"])
    }

    @Test(".persistent(backend:) works through some Memory / withMemory")
    func persistentExplicitBackendSatisfiesMemory() throws {
        func acceptsMemory(_ memory: some Memory) -> Bool { true }
        let memory: PersistentMemory = .persistent(backend: InMemoryBackend())
        #expect(acceptsMemory(memory))

        let agent = try Agent("test agent")
            .withMemory(.persistent(backend: InMemoryBackend()))
        #expect(agent.memory != nil)
    }

    @Test(".summary() default truncates instead of calling an LLM")
    func summaryDefaultTruncates() async {
        let memory: SummaryMemory = .summary(
            configuration: .init(
                recentMessageCount: 5,
                summarizationThreshold: 15,
                summaryTokenTarget: 200
            )
        )

        for index in 1...20 {
            await memory.add(.user("UNIQUE_TOKEN_ALPHA_\(index) " + String(repeating: "word ", count: 40)))
        }

        #expect(await memory.hasSummary)
        let summary = await memory.currentSummary
        #expect(summary.contains("UNIQUE_TOKEN_ALPHA") || summary.contains("word"))
        #expect(!summary.contains("LLM_SUMMARY_PAYLOAD"))
    }

    @Test(".hybrid() default truncates instead of calling an LLM")
    func hybridDefaultTruncates() async {
        let memory: HybridMemory = .hybrid(
            configuration: .init(
                shortTermMaxMessages: 10,
                longTermSummaryTokens: 200,
                summarizationThreshold: 20
            )
        )

        for index in 1...20 {
            await memory.add(.user("UNIQUE_TOKEN_BETA_\(index) " + String(repeating: "word ", count: 40)))
        }

        #expect(await memory.hasSummary)
        let summary = await memory.summary
        #expect(summary.contains("UNIQUE_TOKEN_BETA") || summary.contains("word"))
        #expect(!summary.contains("LLM_SUMMARY_PAYLOAD"))
    }

    @Test(".summary(summarizer: .inferenceProvider) calls the LLM")
    func summaryConfiguredSummarizerCallsLLM() async {
        let provider = MockInferenceProvider(responses: ["LLM_SUMMARY_PAYLOAD"])
        let memory: SummaryMemory = .summary(
            configuration: .init(
                recentMessageCount: 5,
                summarizationThreshold: 15,
                summaryTokenTarget: 200
            ),
            summarizer: .inferenceProvider(provider)
        )

        for index in 1...20 {
            await memory.add(.user("message \(index)"))
        }

        #expect(await memory.currentSummary == "LLM_SUMMARY_PAYLOAD")
        #expect(await provider.generateCallCount >= 1)
    }

    @Test(".hybrid(summarizer: .inferenceProvider) calls the LLM")
    func hybridConfiguredSummarizerCallsLLM() async {
        let provider = MockInferenceProvider(responses: ["LLM_HYBRID_PAYLOAD"])
        let memory: HybridMemory = .hybrid(
            configuration: .init(
                shortTermMaxMessages: 10,
                longTermSummaryTokens: 200,
                summarizationThreshold: 20
            ),
            summarizer: .inferenceProvider(provider)
        )

        for index in 1...20 {
            await memory.add(.user("message \(index)"))
        }

        #expect(await memory.summary == "LLM_HYBRID_PAYLOAD")
        #expect(await provider.generateCallCount >= 1)
    }

    @Test(".foundationModels summarizer preset matches platform availability")
    func foundationModelsPresetMatchesPlatform() {
        let preset = MemorySummarizer.foundationModels
        let foundationModelsAvailable =
            InferenceProviderSummarizer.foundationModelsIfAvailable() != nil

        if foundationModelsAvailable {
            #expect(preset.summarizer is InferenceProviderSummarizer)
        } else {
            #expect(preset.summarizer is TruncatingSummarizer)
        }
    }

    @Test(".summary(summarizer: .foundationModels) constructs SummaryMemory on every platform")
    func summaryFoundationModelsPresetConstructs() async {
        let memory: SummaryMemory = .summary(summarizer: .foundationModels)
        #expect(await memory.isEmpty)
    }
}
