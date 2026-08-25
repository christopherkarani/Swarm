// OpenTelemetryAnyInferenceProvider+Wrappers.swift
// SwarmOpenTelemetry
//
// Type eraser for `any InferenceProvider`. Tool-executor overloads live on
// OpenTelemetryAnyForwarding.

import Foundation
import Swarm

struct OpenTelemetryAnyBaseInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
    /// Type-level so this unambiguously beats the leftover
    /// ``InferenceProviderMetadata`` `{ self }` bridge.
    var metadata: (any InferenceProviderMetadata)? { core.metadata }
    var providerName: String? { core.metadata?.providerName }
    var modelName: String? { core.metadata?.modelName }
    var endpointURL: URL? { core.metadata?.endpointURL }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await core.generate(prompt: prompt, options: options)
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(prompt: prompt, options: options)
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await core.generate(messages: messages, options: options)
    }

    func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        core.stream(messages: messages, options: options)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}
