import Foundation
import Swarm

public struct BenchmarkScenario: Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let toolCalls: Int
    public let rawToolOutput: String
    public let finalAnswer: String

    public init(
        id: String,
        title: String,
        detail: String,
        toolCalls: Int,
        rawToolOutput: String,
        finalAnswer: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.toolCalls = max(1, toolCalls)
        self.rawToolOutput = rawToolOutput
        self.finalAnswer = finalAnswer
    }

    public func withToolCalls(_ toolCalls: Int) -> BenchmarkScenario {
        BenchmarkScenario(
            id: id,
            title: title,
            detail: detail,
            toolCalls: toolCalls,
            rawToolOutput: rawToolOutput,
            finalAnswer: finalAnswer
        )
    }

    public static func compactWebSearch(toolCalls: Int = 12) -> BenchmarkScenario {
        BenchmarkScenario(
            id: "compact",
            title: "Compact websearch trace",
            detail: "compact",
            toolCalls: toolCalls,
            rawToolOutput: SyntheticWebSearchPayload.compact,
            finalAnswer: "Compact benchmark finished."
        )
    }

    public static func groundedWebSearch(toolCalls: Int = 12) -> BenchmarkScenario {
        BenchmarkScenario(
            id: "grounded",
            title: "Grounded websearch trace",
            detail: "ground",
            toolCalls: toolCalls,
            rawToolOutput: SyntheticWebSearchPayload.grounded,
            finalAnswer: "Grounded benchmark finished."
        )
    }
}

public struct BenchmarkMode: Sendable {
    public enum MemoryMode: String, Sendable {
        case baselineConversation
        case contextCore
        case defaultComposite
    }

    public let id: String
    public let title: String
    public let memoryMode: MemoryMode
    public let membrane: MembraneEnvironment

    public init(
        id: String,
        title: String,
        memoryMode: MemoryMode,
        membrane: MembraneEnvironment
    ) {
        self.id = id
        self.title = title
        self.memoryMode = memoryMode
        self.membrane = membrane
    }

    public static let baseline = BenchmarkMode(
        id: "baseline",
        title: "Baseline",
        memoryMode: .baselineConversation,
        membrane: .disabled
    )

    public static let contextCoreOnly = BenchmarkMode(
        id: "contextcore",
        title: "ContextCore only",
        memoryMode: .contextCore,
        membrane: .disabled
    )

    public static let membraneOnly = BenchmarkMode(
        id: "membrane",
        title: "Membrane only",
        memoryMode: .baselineConversation,
        membrane: .enabled
    )

    public static let combined = BenchmarkMode(
        id: "combined",
        title: "ContextCore + Membrane",
        memoryMode: .defaultComposite,
        membrane: .enabled
    )

    public static let all: [BenchmarkMode] = [
        .baseline,
        .contextCoreOnly,
        .membraneOnly,
        .combined,
    ]
}

public struct PromptSnapshot: Sendable, Equatable {
    public let callIndex: Int
    public let prompt: String
    public let promptTokens: Int
    public let visibleToolCount: Int
    public let pointerCount: Int
    public let hasTruncationMarker: Bool
    public let lastRenderedToolResultTokens: Int
}

public struct BenchmarkRunMetrics: Sendable, Equatable {
    public let scenario: String
    public let mode: String
    public let completed: Bool
    public let iterations: Int
    public let toolCalls: Int
    public let runDurationMs: Double
    public let averagePromptTokens: Double
    public let maxPromptTokens: Int
    public let averageVisibleToolCount: Double
    public let rawToolPayloadBytes: Int
    public let finalPointerCount: Int
    public let firstTruncationAfterToolCall: Int?
    public let medianRenderedToolResultTokens: Int
    public let finalOutputLength: Int
    public let promptSnapshots: [PromptSnapshot]
}

public struct QualityFact: Sendable, Equatable {
    public let id: String
    public let expectedText: String

    public init(id: String, expectedText: String) {
        self.id = id
        self.expectedText = expectedText
    }
}

public struct BenchmarkQualityScenario: Sendable, Equatable {
    public let id: String
    public let title: String
    public let toolCalls: Int
    public let goldFacts: [QualityFact]

    public init(
        id: String,
        title: String,
        toolCalls: Int,
        goldFacts: [QualityFact]
    ) {
        self.id = id
        self.title = title
        self.toolCalls = max(1, toolCalls)
        self.goldFacts = goldFacts
    }

    public func withToolCalls(_ toolCalls: Int) -> BenchmarkQualityScenario {
        BenchmarkQualityScenario(
            id: id,
            title: title,
            toolCalls: toolCalls,
            goldFacts: goldFacts
        )
    }

    public static func deepResearch(toolCalls: Int = 32) -> BenchmarkQualityScenario {
        BenchmarkQualityScenario(
            id: "deep_research",
            title: "Deep research websearch quality trace",
            toolCalls: toolCalls,
            goldFacts: [
                QualityFact(id: "F1", expectedText: "FACT F1: enterprise users get a 200 req/min override."),
                QualityFact(id: "F2", expectedText: "FACT F2: Swarm should default to MembraneSession for strict4k."),
                QualityFact(id: "F3", expectedText: "FACT F3: pointer payloads must be durable, not only pointer IDs."),
                QualityFact(id: "F4", expectedText: "FACT F4: ContextCore is best at repacking retrieved evidence, not raw transcript growth."),
                QualityFact(id: "F5", expectedText: "FACT F5: strict4k quality improves when retrieved context and live conversation are not duplicated."),
            ]
        )
    }
}

public struct BenchmarkDepthMetrics: Sendable, Equatable {
    public let scenario: String
    public let mode: String
    public let highestSafeToolCalls: Int
    public let firstTruncatingToolCalls: Int?
    public let maxPromptTokensAtSafeDepth: Int
    public let avgPromptTokensAtSafeDepth: Double
    public let finalPointersAtSafeDepth: Int
}

public struct BenchmarkQualityMetrics: Sendable, Equatable {
    public let scenario: String
    public let mode: String
    public let toolCalls: Int
    public let foundFacts: [String]
    public let missingFacts: [String]
    public let score: Double
    public let passed: Bool
    public let firstTruncationAfterToolCall: Int?
    public let finalPointers: Int
    public let avgPromptTokens: Double
    public let maxPromptTokens: Int
}

public enum PromptAnalysis {
    public static let truncationMarker = "[... context truncated for strict4k budget ...]"
    public static let pointerMarker = "[POINTER id="
    private static let toolResultPrefix = "[Tool Result - websearch]: "

    public static func countPointers(in prompt: String) -> Int {
        Set(pointerIDs(in: prompt)).count
    }

    public static func hasTruncationMarker(_ prompt: String) -> Bool {
        prompt.contains(truncationMarker)
    }

    public static func lastRenderedToolResult(in prompt: String) -> String? {
        guard let range = prompt.range(of: toolResultPrefix, options: .backwards) else {
            return nil
        }

        let remainder = prompt[range.upperBound...]
        if let nextDelimiter = remainder.range(of: "\n\n[") {
            return String(remainder[..<nextDelimiter.lowerBound])
        }

        return String(remainder)
    }

    private static func pointerIDs(in prompt: String) -> [String] {
        let segments = prompt.components(separatedBy: pointerMarker).dropFirst()
        return segments.compactMap { segment in
            guard let end = segment.firstIndex(of: " ") else {
                return nil
            }
            return String(segment[..<end])
        }
    }
}

public enum BenchmarkMarkdownWriter {
    public static func render(results: [BenchmarkRunMetrics]) -> String {
        var lines: [String] = []
        lines.append("# Deterministic Context Benchmark")
        lines.append("")
        lines.append("| Scenario | Mode | Tool calls | Avg prompt tokens | Max prompt tokens | Avg visible tools | First truncation after tool call | Final pointers | Median rendered tool result tokens | Raw tool payload bytes | Run ms |")
        lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

        for result in results {
            let truncation = result.firstTruncationAfterToolCall.map(String.init) ?? "none"
            lines.append(
                "| \(result.scenario) | \(result.mode) | \(result.toolCalls) | \(format(result.averagePromptTokens)) | \(result.maxPromptTokens) | \(format(result.averageVisibleToolCount)) | \(truncation) | \(result.finalPointerCount) | \(result.medianRenderedToolResultTokens) | \(result.rawToolPayloadBytes) | \(format(result.runDurationMs)) |"
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    public static func renderDepthSweep(results: [BenchmarkDepthMetrics], maxExploredToolCalls: Int) -> String {
        var lines: [String] = []
        lines.append("# Context Depth Sweep")
        lines.append("")
        lines.append("| Scenario | Mode | Highest safe tool calls | First truncating tool calls | Safe avg prompt tokens | Safe max prompt tokens | Safe final pointers |")
        lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: |")

        for result in results {
            let truncating = result.firstTruncatingToolCalls.map(String.init) ?? ">\(maxExploredToolCalls)"
            lines.append(
                "| \(result.scenario) | \(result.mode) | \(result.highestSafeToolCalls) | \(truncating) | \(format(result.avgPromptTokensAtSafeDepth)) | \(result.maxPromptTokensAtSafeDepth) | \(result.finalPointersAtSafeDepth) |"
            )
        }

        return lines.joined(separator: "\n")
    }

    public static func renderQuality(results: [BenchmarkQualityMetrics]) -> String {
        var lines: [String] = []
        lines.append("# Context Quality Benchmark")
        lines.append("")
        lines.append("| Scenario | Mode | Tool calls | Score | Passed | Found facts | Missing facts | First truncation after tool call | Final pointers | Avg prompt tokens | Max prompt tokens |")
        lines.append("| --- | --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |")

        for result in results {
            let truncation = result.firstTruncationAfterToolCall.map(String.init) ?? "none"
            let found = result.foundFacts.isEmpty ? "-" : result.foundFacts.joined(separator: ",")
            let missing = result.missingFacts.isEmpty ? "-" : result.missingFacts.joined(separator: ",")
            lines.append(
                "| \(result.scenario) | \(result.mode) | \(result.toolCalls) | \(format(result.score * 100))% | \(result.passed ? "yes" : "no") | \(found) | \(missing) | \(truncation) | \(result.finalPointers) | \(format(result.avgPromptTokens)) | \(result.maxPromptTokens) |"
            )
        }

        return lines.joined(separator: "\n")
    }
}

public actor ContextBenchmarkHarness {
    public init() {}

    public func run(scenarios: [BenchmarkScenario], modes: [BenchmarkMode] = BenchmarkMode.all) async throws -> [BenchmarkRunMetrics] {
        var results: [BenchmarkRunMetrics] = []
        for scenario in scenarios {
            for mode in modes {
                results.append(try await runScenario(scenario, mode: mode))
            }
        }
        return results
    }

    public func runDepthSweep(
        scenarios: [BenchmarkScenario],
        modes: [BenchmarkMode] = BenchmarkMode.all,
        startToolCalls: Int = 12,
        maxToolCalls: Int = 256
    ) async throws -> [BenchmarkDepthMetrics] {
        var results: [BenchmarkDepthMetrics] = []
        for scenario in scenarios {
            for mode in modes {
                results.append(
                    try await measureDepthCeiling(
                        scenario: scenario,
                        mode: mode,
                        startToolCalls: startToolCalls,
                        maxToolCalls: maxToolCalls
                    )
                )
            }
        }
        return results
    }

    public func runQuality(
        scenarios: [BenchmarkQualityScenario],
        modes: [BenchmarkMode] = BenchmarkMode.all
    ) async throws -> [BenchmarkQualityMetrics] {
        var results: [BenchmarkQualityMetrics] = []
        for scenario in scenarios {
            for mode in modes {
                results.append(try await runQualityScenario(scenario, mode: mode))
            }
        }
        return results
    }

    private func runScenario(_ scenario: BenchmarkScenario, mode: BenchmarkMode) async throws -> BenchmarkRunMetrics {
        let provider = ReplayBenchmarkProvider(scenario: scenario)
        let tools = makeTools(for: scenario)
        let memory = try makeMemory(for: mode)

        var environment = AgentEnvironmentValues.current
        environment.membrane = mode.membrane

        let start = ContinuousClock.now
        let result = try await AgentEnvironmentValues.$current.withValue(environment) {
            let agent = try Agent(
                tools: tools,
                instructions: """
                You are a deterministic benchmark agent.
                Use the websearch tool until enough evidence is available, then return the final answer.
                """,
                configuration: AgentConfiguration.default
                    .contextMode(.strict4k)
                    .defaultTracingEnabled(false)
                    .maxIterations(scenario.toolCalls + 2),
                memory: memory,
                inferenceProvider: provider
            )

            return try await agent.run("Benchmark scenario: \(scenario.title)")
        }

        let elapsed = ContinuousClock.now - start
        let snapshots = await provider.snapshots()
        let averagePromptTokens = snapshots.isEmpty ? 0 : Double(snapshots.map(\.promptTokens).reduce(0, +)) / Double(snapshots.count)
        let averageVisibleToolCount = snapshots.isEmpty ? 0 : Double(snapshots.map(\.visibleToolCount).reduce(0, +)) / Double(snapshots.count)
        let maxPromptTokens = snapshots.map(\.promptTokens).max() ?? 0
        let firstTruncationAfterToolCall = snapshots.first(where: \.hasTruncationMarker)?.callIndex
        let finalPointerCount = snapshots.last?.pointerCount ?? 0
        let renderedToolResultTokens = snapshots.map(\.lastRenderedToolResultTokens).filter { $0 > 0 }.sorted()
        let medianRenderedToolResultTokens = if renderedToolResultTokens.isEmpty {
            0
        } else {
            renderedToolResultTokens[renderedToolResultTokens.count / 2]
        }

        return BenchmarkRunMetrics(
            scenario: scenario.title,
            mode: mode.title,
            completed: true,
            iterations: result.iterationCount,
            toolCalls: result.toolCalls.count,
            runDurationMs: Self.milliseconds(elapsed),
            averagePromptTokens: averagePromptTokens,
            maxPromptTokens: maxPromptTokens,
            averageVisibleToolCount: averageVisibleToolCount,
            rawToolPayloadBytes: scenario.rawToolOutput.lengthOfBytes(using: .utf8) * scenario.toolCalls,
            finalPointerCount: finalPointerCount,
            firstTruncationAfterToolCall: firstTruncationAfterToolCall,
            medianRenderedToolResultTokens: medianRenderedToolResultTokens,
            finalOutputLength: result.output.count,
            promptSnapshots: snapshots
        )
    }

    private func makeTools(for scenario: BenchmarkScenario) -> [any AnyJSONTool] {
        let websearch = SyntheticWebSearchTool(scenario: scenario)
        let fillers = (0..<20).map { index in
            SyntheticFillerTool(name: "filler_\(index)")
        }
        return [websearch] + fillers
    }

    private func makeMemory(for mode: BenchmarkMode) throws -> any Memory {
        switch mode.memoryMode {
        case .baselineConversation:
            return ConversationMemory(maxMessages: 10_000)
        case .contextCore:
            return try ContextCoreMemory()
        case .defaultComposite:
            let storeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("context-benchmark-\(UUID().uuidString)", isDirectory: false)
            return try DefaultAgentMemory(
                configuration: .init(
                    waxStoreURL: storeURL
                )
            )
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func measureDepthCeiling(
        scenario: BenchmarkScenario,
        mode: BenchmarkMode,
        startToolCalls: Int,
        maxToolCalls: Int
    ) async throws -> BenchmarkDepthMetrics {
        let initialDepth = max(1, startToolCalls)
        let cap = max(initialDepth, maxToolCalls)

        var safeMetrics = try await runScenario(scenario.withToolCalls(initialDepth), mode: mode)
        if safeMetrics.firstTruncationAfterToolCall != nil {
            return BenchmarkDepthMetrics(
                scenario: scenario.title,
                mode: mode.title,
                highestSafeToolCalls: 0,
                firstTruncatingToolCalls: initialDepth,
                maxPromptTokensAtSafeDepth: 0,
                avgPromptTokensAtSafeDepth: 0,
                finalPointersAtSafeDepth: 0
            )
        }

        var safeDepth = initialDepth
        var truncatingDepth: Int?
        var probeDepth = initialDepth

        while probeDepth < cap {
            probeDepth = min(probeDepth * 2, cap)
            let candidate = try await runScenario(scenario.withToolCalls(probeDepth), mode: mode)
            if candidate.firstTruncationAfterToolCall == nil {
                safeDepth = probeDepth
                safeMetrics = candidate
            } else {
                truncatingDepth = probeDepth
                break
            }
        }

        if truncatingDepth == nil {
            return BenchmarkDepthMetrics(
                scenario: scenario.title,
                mode: mode.title,
                highestSafeToolCalls: safeDepth,
                firstTruncatingToolCalls: nil,
                maxPromptTokensAtSafeDepth: safeMetrics.maxPromptTokens,
                avgPromptTokensAtSafeDepth: safeMetrics.averagePromptTokens,
                finalPointersAtSafeDepth: safeMetrics.finalPointerCount
            )
        }

        var low = safeDepth + 1
        var high = truncatingDepth!
        while low < high {
            let mid = (low + high) / 2
            let candidate = try await runScenario(scenario.withToolCalls(mid), mode: mode)
            if candidate.firstTruncationAfterToolCall == nil {
                safeDepth = mid
                safeMetrics = candidate
                low = mid + 1
            } else {
                high = mid
            }
        }

        return BenchmarkDepthMetrics(
            scenario: scenario.title,
            mode: mode.title,
            highestSafeToolCalls: safeDepth,
            firstTruncatingToolCalls: truncatingDepth,
            maxPromptTokensAtSafeDepth: safeMetrics.maxPromptTokens,
            avgPromptTokensAtSafeDepth: safeMetrics.averagePromptTokens,
            finalPointersAtSafeDepth: safeMetrics.finalPointerCount
        )
    }

    private func runQualityScenario(
        _ scenario: BenchmarkQualityScenario,
        mode: BenchmarkMode
    ) async throws -> BenchmarkQualityMetrics {
        let provider = QualityBenchmarkProvider(scenario: scenario)
        let tools = makeQualityTools(for: scenario)
        let memory = try makeMemory(for: mode)

        var environment = AgentEnvironmentValues.current
        environment.membrane = mode.membrane

        let result = try await AgentEnvironmentValues.$current.withValue(environment) {
            let agent = try Agent(
                tools: tools,
                instructions: """
                You are a deterministic quality benchmark research agent.
                Use websearch to gather evidence, resolve pointers if needed, and then return the exact QUALITY_REPORT format.
                """,
                configuration: AgentConfiguration.default
                    .contextMode(.strict4k)
                    .defaultTracingEnabled(false)
                    .maxIterations(scenario.toolCalls + scenario.goldFacts.count + 24),
                memory: memory,
                inferenceProvider: provider
            )

            return try await agent.run("Research the topic and preserve all benchmark facts.")
        }

        let foundFacts = parseFoundFacts(from: result.output)
        let expected = Set(scenario.goldFacts.map(\.id))
        let found = Set(foundFacts)
        let missingFacts = Array(expected.subtracting(found)).sorted()
        let score = expected.isEmpty ? 1.0 : Double(found.count) / Double(expected.count)
        let snapshots = await provider.snapshots()
        let averagePromptTokens = snapshots.isEmpty ? 0 : Double(snapshots.map(\.promptTokens).reduce(0, +)) / Double(snapshots.count)
        let maxPromptTokens = snapshots.map(\.promptTokens).max() ?? 0

        return BenchmarkQualityMetrics(
            scenario: scenario.title,
            mode: mode.title,
            toolCalls: scenario.toolCalls,
            foundFacts: Array(found).sorted(),
            missingFacts: missingFacts,
            score: score,
            passed: missingFacts.isEmpty,
            firstTruncationAfterToolCall: snapshots.first(where: \.hasTruncationMarker)?.callIndex,
            finalPointers: snapshots.last?.pointerCount ?? 0,
            avgPromptTokens: averagePromptTokens,
            maxPromptTokens: maxPromptTokens
        )
    }

    private func makeQualityTools(for scenario: BenchmarkQualityScenario) -> [any AnyJSONTool] {
        let websearch = QualityWebSearchTool(scenario: scenario)
        let fillers = (0..<20).map { index in
            SyntheticFillerTool(name: "quality_filler_\(index)")
        }
        return [websearch] + fillers
    }

    private func parseFoundFacts(from output: String) -> [String] {
        guard let range = output.range(of: "found=") else {
            return []
        }
        let suffix = output[range.upperBound...]
        let payload = suffix
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? String(suffix)

        return payload
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public enum SyntheticWebSearchPayload {
    public static let compact = """
    SUMMARY:
    Metal 4 improves shader compilation, resource binding, and frame pacing.
    MLX focuses on Apple Silicon-native tensor execution and local model workflows.

    RESULTS:
    1. WWDC session: Explore Metal shader optimization and timeline instrumentation.
    2. Apple docs: Metal resource heaps, argument buffers, dynamic libraries.
    3. GitHub: MLX examples for transformer inference and quantization.
    4. Blog: Attention KV-cache layout on Apple Silicon.
    5. Docs: GPU counters and command buffer debug workflow.

    EVIDENCE:
    - Metal docs emphasize argument buffers and modern pipeline specialization.
    - MLX repos highlight unified memory and direct Apple GPU execution paths.
    - Research notes show prompt-window pressure shifts bottlenecks from compute to context management.
    """

    public static let grounded = """
    GROUNDED ANSWER:
    Metal 4 and MLX complement each other for Apple Silicon on-device AI. Metal 4 gives you low-level GPU control, profiling, and resource-management primitives, while MLX gives you a high-level tensor stack and model code designed specifically for Apple Silicon. The practical pattern is to use MLX for model authoring and iteration, then drop into Metal for kernels, scheduling, memory layout, and latency-sensitive execution paths.

    EVIDENCE SECTION 1:
    WWDC guidance emphasizes command-buffer efficiency, pipeline reuse, argument buffers, and GPU counters for diagnosing underutilization. When context windows get tight, the important observation is that latency is not just model compute: prompt construction and memory movement become visible parts of end-to-end runtime.

    EVIDENCE SECTION 2:
    Apple documentation highlights resource heaps, indirect command buffers, and function specialization as the right building blocks for repeated inference workloads. Those same primitives matter when repeatedly resolving tool outputs or repacking retrieved context because memory churn can dominate if payloads are inlined every turn.

    EVIDENCE SECTION 3:
    MLX examples and community repos focus on unified-memory execution, transformer inference, quantization, and streaming decode on Apple Silicon. The most relevant integration point here is that model-side optimizations only pay off if the context path stops flooding the prompt with large tool payloads.

    EVIDENCE SECTION 4:
    Additional benchmark notes show that grounded web results often carry long evidence sections, multiple citations, and repetitive snippets. Without pointerization or compact retrieval windows, a single grounded search can consume a disproportionate share of a 4K prompt budget.

    EVIDENCE SECTION 5:
    The recommended stack for local agents is: compact live transcript, durable pointer store, retrieval-time reranking, and a measured split between working context and recalled evidence. That lets the model keep acting on relevant evidence without continuously paying to inline entire artifacts.
    """
}

struct SyntheticWebSearchTool: AnyJSONTool, Sendable {
    let scenario: BenchmarkScenario

    var name: String { "websearch" }
    var description: String { "Deterministic synthetic websearch benchmark tool." }
    var parameters: [ToolParameter] {
        [
            ToolParameter(name: "mode", description: "Synthetic mode", type: .string, isRequired: false),
            ToolParameter(name: "query", description: "Synthetic query", type: .string, isRequired: false),
            ToolParameter(name: "detail", description: "Synthetic detail", type: .string, isRequired: false),
        ]
    }

    func execute(arguments: [String : SendableValue]) async throws -> SendableValue {
        let mode = arguments["mode"]?.stringValue ?? scenario.detail
        let query = arguments["query"]?.stringValue ?? "benchmark"
        return .string("""
        [Synthetic Websearch]
        mode=\(mode)
        query=\(query)
        \(scenario.rawToolOutput)
        """)
    }
}

struct SyntheticFillerTool: AnyJSONTool, Sendable {
    let name: String
    var description: String { "Filler schema for benchmark planning pressure." }
    let parameters: [ToolParameter] = []

    func execute(arguments _: [String : SendableValue]) async throws -> SendableValue {
        .string("unused")
    }
}

struct QualityWebSearchTool: AnyJSONTool, Sendable {
    let scenario: BenchmarkQualityScenario

    var name: String { "websearch" }
    var description: String { "Deterministic deep research benchmark websearch tool." }
    var parameters: [ToolParameter] {
        [
            ToolParameter(name: "query", description: "Indexed research query", type: .string, isRequired: false),
            ToolParameter(name: "mode", description: "Synthetic mode", type: .string, isRequired: false),
        ]
    }

    func execute(arguments: [String : SendableValue]) async throws -> SendableValue {
        let query = arguments["query"]?.stringValue ?? "research-0"
        let index = QualityBenchmarkProvider.extractCallIndex(from: query)
        return .string(Self.payload(for: index, scenario: scenario))
    }

    private static func payload(for index: Int, scenario: BenchmarkQualityScenario) -> String {
        let scheduledFacts = scheduledFactIndices(for: scenario)
        let keyFact = scheduledFacts.first { $0.offset == index }?.fact

        let distractor = """
        DISTRACTOR \(index):
        - benchmark note \(index): optimize prompt budget before kernel micro-tuning
        - benchmark note \(index): evidence bundles should stay searchable
        - benchmark note \(index): long tool chains need measurable recall quality
        """

        if let keyFact {
            return """
            [Synthetic Websearch Research]
            call=\(index)
            \(distractor)

            \(keyFact.expectedText)
            """
        }

        return """
        [Synthetic Websearch Research]
        call=\(index)
        \(distractor)
        """
    }

    private static func scheduledFactIndices(for scenario: BenchmarkQualityScenario) -> [(offset: Int, fact: QualityFact)] {
        let last = max(0, scenario.toolCalls - 1)
        let schedule = [
            0,
            max(1, scenario.toolCalls / 4),
            max(2, scenario.toolCalls / 2),
            max(3, (scenario.toolCalls * 3) / 4),
            last,
        ]

        return zip(schedule, scenario.goldFacts).map { ($0.0, $0.1) }
    }
}

actor QualityBenchmarkProvider: PromptTokenCountingInferenceProvider {
    private let scenario: BenchmarkQualityScenario
    private var nextCallIndex = 0
    private var storedSnapshots: [PromptSnapshot] = []
    private var requestedPointers: Set<String> = []
    private let estimator = CharacterBasedTokenEstimator.shared

    init(scenario: BenchmarkQualityScenario) {
        self.scenario = scenario
    }

    func snapshots() -> [PromptSnapshot] {
        storedSnapshots
    }

    func generate(prompt: String, options _: InferenceOptions) async throws -> String {
        try await recordSnapshot(prompt: prompt, visibleToolCount: 0)
        return qualityReport(from: prompt)
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.generate(prompt: prompt, options: options)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try await recordSnapshot(prompt: prompt, visibleToolCount: tools.count)

        if nextCallIndex < scenario.toolCalls {
            let toolCall = InferenceResponse.ParsedToolCall(
                id: "research_call_\(nextCallIndex)",
                name: "websearch",
                arguments: [
                    "mode": .string("research"),
                    "query": .string("research-\(nextCallIndex)"),
                ]
            )
            nextCallIndex += 1
            return InferenceResponse(content: nil, toolCalls: [toolCall], finishReason: .toolCall)
        }

        let visibleFacts = Set(findVisibleFacts(in: prompt).map(\.id))
        if visibleFacts.count < scenario.goldFacts.count,
           requestedPointers.count < maxPointerResolutions,
           let pointerID = nextResolvablePointer(from: prompt),
           tools.contains(where: { $0.name == "resolve_pointer" })
        {
            requestedPointers.insert(pointerID)
            return InferenceResponse(
                content: nil,
                toolCalls: [
                    InferenceResponse.ParsedToolCall(
                        id: "resolve_\(pointerID)",
                        name: "resolve_pointer",
                        arguments: ["pointer_id": .string(pointerID)]
                    )
                ],
                finishReason: .toolCall
            )
        }

        return InferenceResponse(content: qualityReport(from: prompt), finishReason: .completed)
    }

    func countTokens(in text: String) async throws -> Int {
        estimator.estimateTokens(for: text)
    }

    private func recordSnapshot(prompt: String, visibleToolCount: Int) async throws {
        let callIndex = storedSnapshots.count + 1
        let promptTokens = estimator.estimateTokens(for: prompt)
        let lastToolTokens = PromptAnalysis.lastRenderedToolResult(in: prompt).map(estimator.estimateTokens(for:)) ?? 0

        storedSnapshots.append(
            PromptSnapshot(
                callIndex: callIndex,
                prompt: prompt,
                promptTokens: promptTokens,
                visibleToolCount: visibleToolCount,
                pointerCount: PromptAnalysis.countPointers(in: prompt),
                hasTruncationMarker: PromptAnalysis.hasTruncationMarker(prompt),
                lastRenderedToolResultTokens: lastToolTokens
            )
        )
    }

    private func qualityReport(from prompt: String) -> String {
        let found = findVisibleFacts(in: prompt).map(\.id).sorted()
        let missing = Set(scenario.goldFacts.map(\.id)).subtracting(found).sorted()
        return """
        QUALITY_REPORT
        found=\(found.joined(separator: ","))
        missing=\(missing.joined(separator: ","))
        """
    }

    private func findVisibleFacts(in prompt: String) -> [QualityFact] {
        scenario.goldFacts.filter { prompt.contains($0.expectedText) }
    }

    private var maxPointerResolutions: Int {
        max(scenario.goldFacts.count * 4, 24)
    }

    private func nextResolvablePointer(from prompt: String) -> String? {
        let pointerIDs = Self.pointerIDs(in: prompt)
        return pointerIDs.first(where: { !requestedPointers.contains($0) })
    }

    static func extractCallIndex(from query: String) -> Int {
        let digits = query.split(separator: "-").last.flatMap { Int($0) }
        return digits ?? 0
    }

    private static func pointerIDs(in prompt: String) -> [String] {
        let segments = prompt.components(separatedBy: PromptAnalysis.pointerMarker).dropFirst()
        return segments.compactMap { segment in
            guard let end = segment.firstIndex(of: " ") else { return nil }
            return String(segment[..<end])
        }
    }
}

actor ReplayBenchmarkProvider: PromptTokenCountingInferenceProvider {
    private let scenario: BenchmarkScenario
    private var nextCallIndex = 0
    private var storedSnapshots: [PromptSnapshot] = []
    private let estimator = CharacterBasedTokenEstimator.shared

    init(scenario: BenchmarkScenario) {
        self.scenario = scenario
    }

    func snapshots() -> [PromptSnapshot] {
        storedSnapshots
    }

    func generate(prompt: String, options _: InferenceOptions) async throws -> String {
        try await recordSnapshot(prompt: prompt, visibleToolCount: 0)
        return scenario.finalAnswer
    }

    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.generate(prompt: prompt, options: options)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        try await recordSnapshot(prompt: prompt, visibleToolCount: tools.count)

        if nextCallIndex < scenario.toolCalls {
            let toolCall = InferenceResponse.ParsedToolCall(
                id: "call_\(nextCallIndex)",
                name: "websearch",
                arguments: [
                    "mode": .string(nextCallIndex.isMultiple(of: 2) ? "ground" : "search"),
                    "query": .string("metal mlx apple silicon benchmark trace \(nextCallIndex)"),
                    "detail": .string(scenario.detail),
                ]
            )
            nextCallIndex += 1
            return InferenceResponse(content: nil, toolCalls: [toolCall], finishReason: .toolCall)
        }

        return InferenceResponse(content: scenario.finalAnswer, finishReason: .completed)
    }

    func countTokens(in text: String) async throws -> Int {
        estimator.estimateTokens(for: text)
    }

    private func recordSnapshot(prompt: String, visibleToolCount: Int) async throws {
        let callIndex = storedSnapshots.count + 1
        let promptTokens = estimator.estimateTokens(for: prompt)
        let lastToolTokens = PromptAnalysis.lastRenderedToolResult(in: prompt).map(estimator.estimateTokens(for:)) ?? 0

        storedSnapshots.append(
            PromptSnapshot(
                callIndex: callIndex,
                prompt: prompt,
                promptTokens: promptTokens,
                visibleToolCount: visibleToolCount,
                pointerCount: PromptAnalysis.countPointers(in: prompt),
                hasTruncationMarker: PromptAnalysis.hasTruncationMarker(prompt),
                lastRenderedToolResultTokens: lastToolTokens
            )
        )
    }
}
