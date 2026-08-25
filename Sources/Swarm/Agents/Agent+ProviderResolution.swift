// Agent+ProviderResolution.swift
// Swarm Framework
//
// Extracted from Agent.swift. Effects stay on Agent behind AgentTurnKernel;
// collaborators come from the once-per-turn AgentTurnDependencies snapshot.

import Foundation

extension Agent {
    func resolvedInferenceOptions(
        session: (any Session)?,
        provider: any InferenceProvider
    ) async -> InferenceOptions {
        await AgentDependencyResolver.inferenceOptions(
            configuration: configuration,
            capabilities: providerCapabilities(for: provider),
            sessionID: session?.sessionId,
            responseTracker: runEnvironment.responseTracker
        )
    }

    func providerCapabilities(for provider: any InferenceProvider) -> InferenceProviderCapabilities {
        AgentDependencyResolver.providerCapabilities(for: provider)
    }

    func responseID(from result: AgentResult) -> String {
        if case let .string(value)? = result.metadata[Self.responseIDMetadataKey], !value.isEmpty {
            return value
        }
        return UUID().uuidString
    }

    func recordUsage(_ usage: TokenUsage?, on resultBuilder: AgentResult.Builder) {
        guard let usage else { return }
        _ = resultBuilder.addTokenUsage(usage)
    }

    func makeResponse(from result: AgentResult, responseID: String) -> AgentResponse {
        let toolCallsById = Dictionary(uniqueKeysWithValues: result.toolCalls.map { ($0.id, $0) })
        let toolCallRecords: [ToolCallRecord] = result.toolResults.compactMap { toolResult in
            guard let toolCall = toolCallsById[toolResult.callId] else {
                Log.agents.warning("Tool result missing matching call: \(toolResult.callId)")
                return nil
            }

            return ToolCallRecord(
                toolName: toolCall.toolName,
                arguments: toolCall.arguments,
                duration: toolResult.duration,
                timestamp: toolCall.timestamp,
                outcome: ToolCallRecord.Outcome(toolResult.outcome)
            )
        }

        return AgentResponse(
            responseId: responseID,
            output: result.output,
            agentName: configuration.name,
            metadata: result.metadata,
            toolCalls: toolCallRecords,
            usage: result.tokenUsage,
            iterationCount: result.iterationCount
        )
    }

    func finalizeAssistantResponse(
        content: String,
        request: StructuredOutputRequest?,
        provider _: any InferenceProvider
    ) throws -> FinalAssistantResponse {
        guard let request else {
            return FinalAssistantResponse(content: content, structuredOutput: nil)
        }

        // Text remaining after a tool loop (or native session) was produced
        // without `respond(to:schema:)`. Label it prompt-fallback even when the
        // provider advertises `.structuredOutputs` — native guided generation
        // reports `.providerNative` from `generateStructured` itself.
        let structuredOutput = try StructuredOutputParser.parse(
            content,
            request: request,
            source: .promptFallback
        )
        return FinalAssistantResponse(content: structuredOutput.rawJSON, structuredOutput: structuredOutput)
    }

    static func structuredOutputFormatDescription(_ format: StructuredOutputFormat) -> String {
        switch format {
        case .jsonObject:
            return "json_object"
        case .jsonSchema(let name, _):
            return "json_schema:\(name)"
        }
    }

    func optionsWithMembraneRuntimeSettings(
        _ base: InferenceOptions,
        membrane: MembraneEnvironment?
    ) -> InferenceOptions {
        guard let membrane, membrane.isEnabled else {
            return base
        }

        let flags = membrane.configuration.runtimeFeatureFlags
        let allowlist = membrane.configuration.runtimeModelAllowlist

        if flags.isEmpty, allowlist.isEmpty {
            return base
        }

        var updated = base
        var settings = updated.providerSettings ?? [:]

        for (key, isEnabled) in flags {
            let prefix = "conduit.runtime."
            guard key.hasPrefix(prefix) else { continue }
            let feature = String(key.dropFirst(prefix.count))
            settings["conduit.runtime.policy.\(feature).enabled"] = .bool(isEnabled)
        }

        if !allowlist.isEmpty {
            let uniqueSorted = Array(Set(allowlist)).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            settings["conduit.runtime.policy.model_allowlist"] = .array(uniqueSorted.map { .string($0) })
        }

        updated.providerSettings = settings.isEmpty ? nil : settings
        return updated
    }
}
