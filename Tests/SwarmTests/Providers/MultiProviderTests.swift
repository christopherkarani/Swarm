// MultiProviderTests.swift
// SwarmTests
//
// Comprehensive tests for MultiProvider routing and registration functionality.

import Foundation
@testable import Swarm
import Testing

// MARK: - SimpleMockProvider

/// A simple mock provider for testing routing logic.
actor SimpleMockProvider: InferenceProvider {
    let name: String
    private(set) var generateCalls: [String] = []

    init(name: String) {
        self.name = name
    }

    func generate(prompt: String, options _: InferenceOptions) async throws -> String {
        generateCalls.append(prompt)
        return "Response from \(name)"
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        try await generate(prompt: InferenceMessage.flattenPrompt(messages), options: options)
    }

    nonisolated func stream(prompt _: String, options _: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        let providerName = name
        return AsyncThrowingStream { continuation in
            for char in "Response from \(providerName)" {
                continuation.yield(String(char))
            }
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools _: [ToolSchema],
        options _: InferenceOptions
    ) async throws -> InferenceResponse {
        generateCalls.append(prompt)
        return InferenceResponse(content: "Tool response from \(name)", finishReason: .completed)
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        toolExecutor: ToolCallExecutor?
    ) async throws -> InferenceResponse {
        _ = toolExecutor
        return try await generateWithToolCalls(
            prompt: InferenceMessage.flattenPrompt(messages),
            tools: tools,
            options: options
        )
    }
}

// MARK: - MultiProviderRegistrationTests

@Suite("MultiProvider Registration Tests")
struct MultiProviderRegistrationTests {
    @Test("register adds provider for prefix")
    func registerAddsProvider() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let anthropicProvider = SimpleMockProvider(name: "anthropic")
        try await multiProvider.register(prefix: "anthropic", provider: anthropicProvider)

        let hasProvider = await multiProvider.hasProvider(for: "anthropic")
        #expect(hasProvider == true)
    }

    @Test("unregister removes provider for prefix")
    func unregisterRemovesProvider() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let provider = SimpleMockProvider(name: "openai")
        try await multiProvider.register(prefix: "openai", provider: provider)

        #expect(await multiProvider.hasProvider(for: "openai") == true)

        await multiProvider.unregister(prefix: "openai")

        #expect(await multiProvider.hasProvider(for: "openai") == false)
    }

    @Test("registeredPrefixes returns sorted list")
    func registeredPrefixesReturnsSortedList() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        try await multiProvider.register(prefix: "openai", provider: SimpleMockProvider(name: "openai"))
        try await multiProvider.register(prefix: "anthropic", provider: SimpleMockProvider(name: "anthropic"))
        try await multiProvider.register(prefix: "google", provider: SimpleMockProvider(name: "google"))

        let prefixes = await multiProvider.registeredPrefixes

        #expect(prefixes == ["anthropic", "google", "openai"])
    }

    @Test("providerCount returns correct count")
    func providerCountReturnsCorrectCount() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        #expect(await multiProvider.providerCount == 0)

        try await multiProvider.register(prefix: "anthropic", provider: SimpleMockProvider(name: "anthropic"))
        #expect(await multiProvider.providerCount == 1)

        try await multiProvider.register(prefix: "openai", provider: SimpleMockProvider(name: "openai"))
        #expect(await multiProvider.providerCount == 2)

        await multiProvider.unregister(prefix: "anthropic")
        #expect(await multiProvider.providerCount == 1)
    }

    @Test("register empty prefix throws")
    func registerEmptyPrefixThrows() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await #expect(throws: MultiProviderError.emptyPrefix) {
            try await multiProvider.register(prefix: "", provider: SimpleMockProvider(name: "test"))
        }
    }

    @Test("register whitespace prefix throws")
    func registerWhitespacePrefixThrows() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await #expect(throws: MultiProviderError.emptyPrefix) {
            try await multiProvider.register(prefix: "   ", provider: SimpleMockProvider(name: "test"))
        }
    }
}

// MARK: - MultiProviderModelParsingTests

@Suite("MultiProvider Model Parsing Tests")
struct MultiProviderModelParsingTests {
    @Test("parses anthropic prefix correctly")
    func parsesAnthropicPrefix() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let anthropicProvider = SimpleMockProvider(name: "anthropic")
        try await multiProvider.register(prefix: "anthropic", provider: anthropicProvider)

        await multiProvider.setModel("anthropic/claude-3")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from anthropic")
    }

    @Test("no prefix uses default provider")
    func noPrefixUsesDefault() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        try await multiProvider.register(prefix: "anthropic", provider: SimpleMockProvider(name: "anthropic"))

        await multiProvider.setModel("gpt-4")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from default")
    }

    @Test("empty prefix in model uses default")
    func emptyPrefixInModelUsesDefault() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await multiProvider.setModel("/model")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from default")
    }

    @Test("empty model name uses default")
    func emptyModelNameUsesDefault() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await multiProvider.setModel("prefix/")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from default")
    }

    @Test("case insensitive prefix")
    func caseInsensitivePrefix() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let anthropicProvider = SimpleMockProvider(name: "anthropic")
        try await multiProvider.register(prefix: "anthropic", provider: anthropicProvider)

        await multiProvider.setModel("ANTHROPIC/model")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from anthropic")
    }

    @Test("trims whitespace around prefix and model name")
    func trimsWhitespaceAroundPrefixAndModel() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let openaiProvider = SimpleMockProvider(name: "openai")
        try await multiProvider.register(prefix: "openai", provider: openaiProvider)

        await multiProvider.setModel("  OpenAI / gpt-4o  ")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from openai")
    }
}

// MARK: - MultiProviderRoutingTests

@Suite("MultiProvider Routing Tests")
struct MultiProviderRoutingTests {
    @Test("routes to registered provider")
    func routesToRegisteredProvider() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let openaiProvider = SimpleMockProvider(name: "openai")
        try await multiProvider.register(prefix: "openai", provider: openaiProvider)

        await multiProvider.setModel("openai/gpt-4")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from openai")
    }

    @Test("falls back for unregistered prefix")
    func fallsBackForUnregisteredPrefix() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await multiProvider.setModel("unknown/model")
        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from default")
    }

    @Test("falls back when no model set")
    func fallsBackWhenNoModelSet() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let response = try await multiProvider.generate(prompt: "Test", options: .default)

        #expect(response == "Response from default")
    }
}

// MARK: - MultiProviderModelSelectionTests

@Suite("MultiProvider Model Selection Tests")
struct MultiProviderModelSelectionTests {
    @Test("setModel sets current model")
    func setModelSetsCurrentModel() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await multiProvider.setModel("anthropic/claude-3")

        let model = await multiProvider.model
        #expect(model == "anthropic/claude-3")
    }

    @Test("model property returns nil initially")
    func modelPropertyReturnsNilInitially() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let model = await multiProvider.model
        #expect(model == nil)
    }

    @Test("clearModel clears current model")
    func clearModelClearsCurrentModel() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        await multiProvider.setModel("test/model")
        #expect(await multiProvider.model != nil)

        await multiProvider.clearModel()
        #expect(await multiProvider.model == nil)
    }
}

// MARK: - MultiProviderUtilityTests

@Suite("MultiProvider Utility Tests")
struct MultiProviderUtilityTests {
    @Test("hasProvider returns true for registered")
    func hasProviderReturnsTrueForRegistered() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        try await multiProvider.register(prefix: "test", provider: SimpleMockProvider(name: "test"))

        #expect(await multiProvider.hasProvider(for: "test") == true)
    }

    @Test("hasProvider returns false for unregistered")
    func hasProviderReturnsFalseForUnregistered() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        #expect(await multiProvider.hasProvider(for: "unknown") == false)
    }

    @Test("provider(for:) returns registered provider")
    func providerForReturnsRegisteredProvider() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let testProvider = SimpleMockProvider(name: "test")
        try await multiProvider.register(prefix: "test", provider: testProvider)

        let retrieved = await multiProvider.provider(for: "test")
        #expect(retrieved != nil)
    }

    @Test("provider(for:) returns nil for unregistered")
    func providerForReturnsNilForUnregistered() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let retrieved = await multiProvider.provider(for: "unknown")
        #expect(retrieved == nil)
    }

    @Test("description contains MultiProvider")
    func descriptionContainsExpectedInfo() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let description = multiProvider.description
        #expect(description.contains("MultiProvider"))
    }
}

// MARK: - MultiProviderErrorTests

@Suite("MultiProviderError Tests")
struct MultiProviderErrorTests {
    @Test("emptyPrefix error description")
    func emptyPrefixErrorDescription() {
        let error = MultiProviderError.emptyPrefix
        #expect(error.errorDescription?.contains("empty") == true)
    }

    @Test("providerNotFound error description")
    func providerNotFoundErrorDescription() {
        let error = MultiProviderError.providerNotFound(prefix: "unknown")
        #expect(error.errorDescription?.contains("unknown") == true)
    }

    @Test("invalidModelFormat error description")
    func invalidModelFormatErrorDescription() {
        let error = MultiProviderError.invalidModelFormat(model: "bad-format")
        #expect(error.errorDescription?.contains("bad-format") == true)
    }
}

// MARK: - MultiProviderInferenceProviderTests

@Suite("MultiProvider InferenceProvider Tests")
struct MultiProviderInferenceProviderTests {
    @Test("generate delegates to correct provider")
    func generateDelegatesToCorrectProvider() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let anthropicProvider = SimpleMockProvider(name: "anthropic")
        try await multiProvider.register(prefix: "anthropic", provider: anthropicProvider)

        await multiProvider.setModel("anthropic/claude-3")
        let response = try await multiProvider.generate(prompt: "Hello", options: .default)

        #expect(response == "Response from anthropic")
        let calls = await anthropicProvider.generateCalls
        #expect(calls.contains("Hello"))
    }

    @Test("generateWithToolCalls delegates to correct provider")
    func generateWithToolCallsDelegatesToCorrectProvider() async throws {
        let defaultProvider = SimpleMockProvider(name: "default")
        let multiProvider = MultiProvider(defaultProvider: defaultProvider)

        let openaiProvider = SimpleMockProvider(name: "openai")
        try await multiProvider.register(prefix: "openai", provider: openaiProvider)

        await multiProvider.setModel("openai/gpt-4")
        let response = try await multiProvider.generateWithToolCalls(
            prompt: "Test",
            tools: [],
            options: .default
        )

        #expect(response.content == "Tool response from openai")
    }
}
