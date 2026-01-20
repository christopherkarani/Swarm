// PlanAndExecuteAgent+Planning.swift
// SwiftAgents Framework
//
// Planning logic for Plan-and-Execute agent.

import Foundation
import Logging

// MARK: - PlanAndExecuteAgent Planning

extension PlanAndExecuteAgent {
    // MARK: - Plan Generation

    /// Generates an execution plan for the given input.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - sessionHistory: Previous conversation messages.
    ///   - hooks: Optional hooks for lifecycle callbacks.
    /// - Returns: An execution plan to achieve the goal.
    /// - Throws: `AgentError` if plan generation fails.
    func generatePlan(
        for input: String,
        sessionHistory: [MemoryMessage] = [],
        hooks: (any RunHooks)? = nil
    ) async throws -> ExecutionPlan {
        let prompt = buildPlanningPrompt(for: input, sessionHistory: sessionHistory)
        await hooks?.onLLMStart(context: nil, agent: self, systemPrompt: instructions, inputMessages: [MemoryMessage.user(prompt)])
        let response = try await generateResponse(prompt: prompt)
        await hooks?.onLLMEnd(context: nil, agent: self, response: response, usage: nil)
        return parsePlan(from: response, goal: input)
    }

    /// Builds the prompt for plan generation.
    /// - Parameters:
    ///   - input: The user's input/query.
    ///   - sessionHistory: Previous conversation messages.
    /// - Returns: The formatted prompt string.
    func buildPlanningPrompt(for input: String, sessionHistory: [MemoryMessage] = []) -> String {
        let toolDescriptions = buildToolDescriptions()
        let conversationContext = buildConversationContext(from: sessionHistory)

        return """
        \(instructions.isEmpty ? "You are a helpful AI assistant that creates structured plans." : instructions)

        You are a planning agent. Your task is to create a step-by-step plan to accomplish the user's goal.

        \(toolDescriptions.isEmpty ? "No tools are available." : "Available Tools:\n\(toolDescriptions)")

        Create a plan with numbered steps. For each step, provide:
        1. A clear description of what the step accomplishes
        2. If a tool is needed, specify the tool name and arguments
        3. If the step depends on previous steps, specify their step numbers

        Format your response as a JSON object with the following structure:
        {
          "steps": [
            {
              "stepNumber": 1,
              "description": "Clear description of the step",
              "toolName": "tool_name",
              "toolArguments": {"arg1": "value1", "arg2": 42},
              "dependsOn": []
            },
            {
              "stepNumber": 2,
              "description": "Another step description",
              "toolName": null,
              "toolArguments": {},
              "dependsOn": [1]
            }
          ]
        }

        Rules:
        1. Be specific and actionable in each step.
        2. Only use tools that are available.
        3. Keep the plan concise but complete.
        4. Specify dependencies as an array of step numbers.
        5. If a step has no tool, set toolName to null and toolArguments to {}.
        6. Respond ONLY with valid JSON - no additional text before or after.
        \(conversationContext.isEmpty ? "" : "\nConversation History:\n\(conversationContext)")

        User Goal: \(input)

        Create your plan in JSON format:
        """
    }

    /// Parses a JSON-formatted plan response.
    /// - Parameters:
    ///   - response: The LLM response containing JSON.
    ///   - goal: The goal being planned for.
    /// - Returns: An ExecutionPlan if parsing succeeds, nil otherwise.
    func parseJSONPlan(from response: String, goal: String) -> ExecutionPlan? {
        // Extract JSON from response (handle cases where LLM adds extra text)
        let jsonString = extractJSON(from: response)
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        // Decode the plan
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let planResponse: PlanResponse
        do {
            planResponse = try decoder.decode(PlanResponse.self, from: jsonData)
        } catch {
            Log.agents.error("JSON plan decoding failed: \(error.localizedDescription)")
            Log.agents.debug("Invalid JSON content: \(jsonString)")
            return nil
        }

        // Convert PlanResponse to ExecutionPlan
        var steps: [PlanStep] = []
        var stepNumberToId: [Int: UUID] = [:]

        // First pass: Create all steps with UUIDs
        for stepData in planResponse.steps {
            let stepId = UUID()
            stepNumberToId[stepData.stepNumber] = stepId
        }

        // Second pass: Build PlanSteps with resolved dependencies
        for stepData in planResponse.steps {
            guard let stepId = stepNumberToId[stepData.stepNumber] else { continue }

            // Resolve dependencies from step numbers to UUIDs
            let dependencyIds = stepData.dependsOn.compactMap { stepNumberToId[$0] }

            let step = PlanStep(
                id: stepId,
                stepNumber: stepData.stepNumber,
                stepDescription: stepData.description,
                toolName: stepData.toolName,
                toolArguments: stepData.toolArguments ?? [:],
                dependsOn: dependencyIds
            )
            steps.append(step)
        }

        // If no steps were parsed, return nil to trigger fallback
        guard !steps.isEmpty else {
            return nil
        }

        return ExecutionPlan(steps: steps, goal: goal)
    }

    /// Extracts JSON content from a response that may contain additional text.
    /// - Parameter response: The raw response string.
    /// - Returns: The extracted JSON string.
    func extractJSON(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // If response starts with {, try to find the matching closing brace
        if let firstBrace = trimmed.firstIndex(of: "{") {
            var depth = 0
            var inString = false
            var escapeNext = false

            for (index, char) in trimmed[firstBrace...].enumerated() {
                if escapeNext {
                    escapeNext = false
                    continue
                }

                if char == "\\" {
                    escapeNext = true
                    continue
                }

                if char == "\"", !escapeNext {
                    inString.toggle()
                    continue
                }

                if !inString {
                    if char == "{" {
                        depth += 1
                    } else if char == "}" {
                        depth -= 1
                        if depth == 0 {
                            let endIndex = trimmed.index(firstBrace, offsetBy: index + 1)
                            return String(trimmed[firstBrace..<endIndex])
                        }
                    }
                }
            }
        }

        // If extraction failed, return original (might still be valid JSON)
        return trimmed
    }
}
