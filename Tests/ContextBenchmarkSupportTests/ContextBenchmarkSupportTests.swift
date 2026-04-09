@testable import ContextBenchmarkSupport
import Testing

@Suite("Context Benchmark Support")
struct ContextBenchmarkSupportTests {
    @Test("PromptAnalysis detects truncation and pointers")
    func promptAnalysisDetectsMarkers() {
        let prompt = """
        [User]: benchmark

        [Tool Result - websearch]: [POINTER id=ptr_123 tool=websearch bytes=2048] summary text
        Use resolve_pointer(pointer_id: "ptr_123") to access the full payload.

        [... context truncated for strict4k budget ...]
        """

        #expect(PromptAnalysis.hasTruncationMarker(prompt))
        #expect(PromptAnalysis.countPointers(in: prompt) == 1)
        #expect(PromptAnalysis.lastRenderedToolResult(in: prompt)?.contains("ptr_123") == true)
    }

    @Test("Markdown writer includes scenario rows")
    func markdownWriterRendersRows() {
        let metrics = BenchmarkRunMetrics(
            scenario: "Compact websearch trace",
            mode: "Baseline",
            completed: true,
            iterations: 4,
            toolCalls: 3,
            runDurationMs: 12.5,
            averagePromptTokens: 456.7,
            maxPromptTokens: 789,
            averageVisibleToolCount: 5,
            rawToolPayloadBytes: 2048,
            finalPointerCount: 1,
            firstTruncationAfterToolCall: 2,
            medianRenderedToolResultTokens: 44,
            finalOutputLength: 120,
            promptSnapshots: []
        )

        let markdown = BenchmarkMarkdownWriter.render(results: [metrics])

        #expect(markdown.contains("Deterministic Context Benchmark"))
        #expect(markdown.contains("Compact websearch trace"))
        #expect(markdown.contains("| Baseline |"))
        #expect(markdown.contains("| 2 | 1 | 44 | 2048 | 12.5 |"))
    }

    @Test("Quality markdown writer includes score rows")
    func qualityMarkdownWriterRendersRows() {
        let metrics = BenchmarkQualityMetrics(
            scenario: "Deep research websearch quality trace",
            mode: "Membrane only",
            toolCalls: 32,
            foundFacts: ["F1", "F2", "F3"],
            missingFacts: ["F4", "F5"],
            score: 0.6,
            passed: false,
            firstTruncationAfterToolCall: nil,
            finalPointers: 12,
            avgPromptTokens: 1234.5,
            maxPromptTokens: 2345
        )

        let markdown = BenchmarkMarkdownWriter.renderQuality(results: [metrics])

        #expect(markdown.contains("Context Quality Benchmark"))
        #expect(markdown.contains("Deep research websearch quality trace"))
        #expect(markdown.contains("| Membrane only | 32 | 60.0% | no |"))
    }
}
