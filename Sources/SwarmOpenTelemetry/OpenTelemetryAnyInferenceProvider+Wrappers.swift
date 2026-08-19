// OpenTelemetryAnyInferenceProvider+Wrappers.swift
// SwarmOpenTelemetry
//
// Capability-combination type erasers. Tool-executor overloads live on
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

struct OpenTelemetryAnyStructuredInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    StructuredOutputInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

    func generateStructured(
        prompt: String,
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(prompt: prompt, request: request, options: options)
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

struct OpenTelemetryAnyConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

}

struct OpenTelemetryAnyStreamingConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

}

struct OpenTelemetryAnyStructuredConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await core.generateWithToolCalls(messages: messages, tools: tools, options: options)
    }


    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

struct OpenTelemetryAnyStreamingStructuredConversationInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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


    func generateStructured(
        messages: [InferenceMessage],
        request: StructuredOutputRequest,
        options: InferenceOptions
    ) async throws -> StructuredOutputResult {
        try await core.generateStructured(messages: messages, request: request, options: options)
    }
}

struct OpenTelemetryAnyPromptToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ToolCallStreamingInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

    func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
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

struct OpenTelemetryAnyConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    func streamWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        core.streamWithToolCalls(messages: messages, tools: tools, options: options)
    }

}

struct OpenTelemetryAnyStreamingConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

}

struct OpenTelemetryAnyStructuredConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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

struct OpenTelemetryAnyFullConversationToolStreamingInferenceProvider: @unchecked Sendable,
    InferenceProvider,
    OpenTelemetryAnyForwarding,
    CapabilityReportingInferenceProvider,
    InferenceProviderMetadata,
    ConversationInferenceProvider,
    StreamingConversationInferenceProvider,
    ToolCallStreamingConversationInferenceProvider,
    StructuredOutputConversationInferenceProvider,
    OpenTelemetryInstrumentedInferenceProvider
{
    let core: OpenTelemetryAnyInferenceProviderCore

    var capabilities: InferenceProviderCapabilities { core.capabilities }
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
