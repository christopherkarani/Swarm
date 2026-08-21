import Testing
import Swarm
import SwarmOpenTelemetry

private struct PublicAPIPromptOnlyProvider: InferenceProvider {
    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        messages.map(\.content).joined(separator: "\n")
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return InferenceResponse(content: try await generate(messages: messages, options: options))
    }
}

@Test("Raw provider OpenTelemetry instrumentation is available through public import")
func rawProviderOpenTelemetryInstrumentationIsAvailableThroughPublicImport() async throws {
    let provider = PublicAPIPromptOnlyProvider().instrumentedWithOpenTelemetry()

    let output = try await provider.generate(prompt: "hello", options: .default)

    #expect(output == "hello")
}
