// Agent+ToolLoopInference.swift
// Swarm Framework
//
// Provider response generation for the tool-calling turn: plain, tool-calling,
// and streaming tool-calling generation behind the runner's seam.

import Foundation

extension AgentTurnRunner {
    // MARK: - Response Generation

    /// Generates a response without tool calling.
    static func generateWithoutTools(
        agent: Agent,
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        systemPrompt: String,
        inferenceOptions: InferenceOptions,
        enableStreaming: Bool = false,
        observer: (any AgentObserver)?
    ) async throws -> Agent.FinalAssistantResponse {
        await observer?.notifyLLMStart(context: nil, agent: agent, systemPrompt: systemPrompt, inputMessages: messages)

        let options = inferenceOptions
        let content: String
        let structuredOutput: StructuredOutputResult?
        if let request = options.structuredOutput {
            let result = try await provider.generateStructured(
                messages: messages,
                request: request,
                options: options
            )
            content = result.rawJSON
            structuredOutput = result
        } else if enableStreaming {
            var streamedContent = ""
            streamedContent.reserveCapacity(1024)
            let stream = provider.stream(messages: messages, options: options)
            for try await token in stream {
                if !token.isEmpty {
                    streamedContent += token
                }
                await observer?.onOutputToken(context: nil, agent: agent, token: token)
            }
            content = streamedContent
            structuredOutput = nil
        } else {
            content = try await provider.generate(messages: messages, options: options)
            structuredOutput = nil
        }

        await observer?.onLLMEnd(context: nil, agent: agent, response: content, usage: nil)
        return Agent.FinalAssistantResponse(content: content, structuredOutput: structuredOutput)
    }

    static func generateWithTools(
        agent: Agent,
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        emitOutputTokens: Bool = false,
        toolExecutor: ToolCallExecutor? = nil
    ) async throws -> InferenceResponse {
        let options = inferenceOptions

        // Notify observer of LLM start
        await observer?.notifyLLMStart(context: nil, agent: agent, systemPrompt: systemPrompt, inputMessages: messages)

        let response = try await provider.generateWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: toolExecutor
        )

        if emitOutputTokens, response.transcriptMessages.isEmpty, response.toolCalls.isEmpty,
           let content = response.content, !content.isEmpty
        {
            await observer?.onOutputToken(context: nil, agent: agent, token: content)
        }

        // Notify observer of LLM end
        let responseContent = response.content ?? ""
        await observer?.onLLMEnd(context: nil, agent: agent, response: responseContent, usage: response.usage)

        return response
    }

    static func generateWithToolsStreaming(
        agent: Agent,
        provider: any InferenceProvider,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        inferenceOptions: InferenceOptions,
        systemPrompt: String,
        observer: (any AgentObserver)? = nil,
        toolExecutor: ToolCallExecutor? = nil
    ) async throws -> InferenceResponse {
        let options = inferenceOptions

        await observer?.notifyLLMStart(context: nil, agent: agent, systemPrompt: systemPrompt, inputMessages: messages)

        var content = ""
        content.reserveCapacity(1024)
        var parsedToolCalls: [InferenceResponse.ParsedToolCall] = []
        var usage: TokenUsage?
        var stopStreaming = false
        var finishedTurn: InferenceResponse?

        let stream = provider.streamWithToolCalls(
            messages: messages,
            tools: tools,
            options: options,
            toolExecutor: toolExecutor
        )

        for try await update in stream {
            switch update {
            case let .outputChunk(chunk):
                if !chunk.isEmpty { content += chunk }
                await observer?.onOutputToken(context: nil, agent: agent, token: chunk)

            case let .toolCallPartial(partial):
                await observer?.onToolCallPartial(context: nil, agent: agent, update: partial)

            case let .toolCallsCompleted(calls):
                parsedToolCalls = calls
                // Capture stops here so Agent can run tools. An owned-loop adapter
                // still has a finished turn to yield; keep reading when we passed
                // an executor.
                if toolExecutor == nil {
                    stopStreaming = true
                }

            case let .usage(u):
                usage = u

            case let .finishedTurn(response):
                finishedTurn = response
            }

            if stopStreaming { break }
        }

        await observer?.onLLMEnd(context: nil, agent: agent, response: content, usage: usage)

        if let finishedTurn {
            return finishedTurn
        }

        return InferenceResponse(
            content: content.isEmpty ? nil : content,
            toolCalls: parsedToolCalls,
            finishReason: parsedToolCalls.isEmpty ? .completed : .toolCall,
            usage: usage
        )
    }
}
