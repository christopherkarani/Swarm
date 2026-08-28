import Foundation
import MCP
import Swarm

enum SwarmMCPCallToolOutcome {
    case success(CallTool.Result)
    case failure(CallTool.Result)
    case protocolError(MCP.MCPError)
}

enum SwarmMCPErrorMapper {
    static func mapCallToolError(_ error: Error, toolName: String) -> SwarmMCPCallToolOutcome {
        if let mcpError = error as? MCP.MCPError {
            return .protocolError(mcpError)
        }

        if error is CancellationError {
            return .failure(
                callToolErrorResult(
                    code: "cancelled",
                    action: "retry_if_needed",
                    toolName: toolName,
                    message: "Tool execution was cancelled."
                )
            )
        }

        if let typedError = error as? SwarmMCPToolExecutionError {
            return mapTypedError(typedError, toolName: toolName)
        }

        if let workflowError = error as? WorkflowError {
            return mapWorkflowError(workflowError, toolName: toolName)
        }

        if let guardrailError = error as? GuardrailError {
            return .failure(
                callToolErrorResult(
                    code: "guardrail_blocked",
                    action: "revise_input_or_policy",
                    toolName: toolName,
                    message: guardrailError.localizedDescription
                )
            )
        }

        if let agentError = error as? AgentError {
            return mapAgentError(agentError, toolName: toolName)
        }

        return .failure(
            callToolErrorResult(
                code: "execution_failed",
                action: "inspect_error_and_retry",
                toolName: toolName,
                message: error.localizedDescription
            )
        )
    }

    static func mapToolResult(_ value: SendableValue) -> CallTool.Result {
        switch value {
        case let .string(stringValue):
            return CallTool.Result(content: [textContent(stringValue)], isError: false)
        case .null:
            return CallTool.Result(content: [textContent("null")], isError: false)
        case let .bool(boolValue):
            return CallTool.Result(content: [textContent(boolValue.description)], isError: false)
        case let .int(intValue):
            return CallTool.Result(content: [textContent(intValue.description)], isError: false)
        case let .double(doubleValue):
            return CallTool.Result(content: [textContent(doubleValue.description)], isError: false)
        case .array, .dictionary:
            let resultValue = SwarmMCPValueMapper.mcpValue(from: value)
            let jsonText = jsonText(from: resultValue) ?? "{}"
            let content: [MCP.Tool.Content] = [
                textContent(jsonText),
                .resource(
                    resource: .text(
                        jsonText,
                        uri: "swarm://mcp/tool-result",
                        mimeType: "application/json"
                    )
                ),
            ]
            return CallTool.Result(
                content: content,
                isError: false
            )
        }
    }

    private static func mapTypedError(
        _ error: SwarmMCPToolExecutionError,
        toolName: String
    ) -> SwarmMCPCallToolOutcome {
        switch error {
        case let .approvalRequired(prompt, reason, metadata):
            var details = SwarmMCPValueMapper.mcpValue(from: .dictionary(metadata)).objectValue ?? [:]
            details["prompt"] = .string(prompt)
            if let reason {
                details["reason"] = .string(reason)
            }
            return .failure(
                callToolErrorResult(
                    code: "approval_required",
                    action: "request_human_approval",
                    toolName: toolName,
                    message: "Tool execution requires approval.",
                    details: details
                )
            )
        case let .permissionDenied(reason, metadata):
            let details = SwarmMCPValueMapper.mcpValue(from: .dictionary(metadata)).objectValue ?? [:]
            return .failure(
                callToolErrorResult(
                    code: "permission_denied",
                    action: "adjust_permissions_or_policy",
                    toolName: toolName,
                    message: reason,
                    details: details
                )
            )
        }
    }

    private static func mapWorkflowError(
        _ error: WorkflowError,
        toolName: String
    ) -> SwarmMCPCallToolOutcome {
        switch error {
        case let .humanApprovalRejected(prompt, reason):
            return .failure(
                callToolErrorResult(
                    code: "approval_rejected",
                    action: "request_human_approval",
                    toolName: toolName,
                    message: "Human approval rejected tool execution.",
                    details: [
                        "prompt": .string(prompt),
                        "reason": .string(reason),
                    ]
                )
            )
        case let .humanApprovalTimeout(prompt):
            return .failure(
                callToolErrorResult(
                    code: "approval_timeout",
                    action: "request_human_approval",
                    toolName: toolName,
                    message: "Human approval timed out.",
                    details: ["prompt": .string(prompt)]
                )
            )
        case let .workflowInterrupted(reason):
            return .failure(
                callToolErrorResult(
                    code: "interrupted",
                    action: "resume_or_retry_workflow",
                    toolName: toolName,
                    message: "Workflow was interrupted.",
                    details: ["reason": .string(reason)]
                )
            )
        default:
            return .failure(
                callToolErrorResult(
                    code: "execution_failed",
                    action: "inspect_error_and_retry",
                    toolName: toolName,
                    message: error.localizedDescription
                )
            )
        }
    }

    private static func mapAgentError(
        _ error: AgentError,
        toolName: String
    ) -> SwarmMCPCallToolOutcome {
        switch error {
        case let .toolNotFound(name):
            return .protocolError(.methodNotFound("Unknown tool: \(name)"))
        case let .invalidToolArguments(_, reason):
            return .protocolError(.invalidParams(reason))
        case let .timeout(duration):
            let seconds = Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
            return .failure(
                callToolErrorResult(
                    code: "timeout",
                    action: "retry_or_increase_timeout",
                    toolName: toolName,
                    message: "Tool execution timed out.",
                    details: ["seconds": .double(seconds)]
                )
            )
        case .cancelled:
            return .failure(
                callToolErrorResult(
                    code: "cancelled",
                    action: "retry_if_needed",
                    toolName: toolName,
                    message: "Tool execution was cancelled."
                )
            )
        case let .toolFailure(_, message, cause):
            return .failure(
                callToolErrorResult(
                    code: "execution_failed",
                    action: "inspect_error_and_retry",
                    toolName: toolName,
                    message: message ?? cause.map(String.init(describing:)) ?? "Tool execution failed."
                )
            )
        default:
            return .failure(
                callToolErrorResult(
                    code: "execution_failed",
                    action: "inspect_error_and_retry",
                    toolName: toolName,
                    message: error.localizedDescription
                )
            )
        }
    }

    private static func callToolErrorResult(
        code: String,
        action: String,
        toolName: String,
        message: String,
        details: [String: Value] = [:]
    ) -> CallTool.Result {
        var metadata: [String: Value] = [
            "code": .string(code),
            "action": .string(action),
            "tool": .string(toolName),
            "message": .string(message),
        ]
        if !details.isEmpty {
            metadata["details"] = .object(details)
        }

        let metadataValue = Value.object(metadata)
        let metadataText = jsonText(from: metadataValue) ?? "{}"
        let content: [MCP.Tool.Content] = [
            textContent(message),
            .resource(
                resource: .text(
                    metadataText,
                    uri: "swarm://mcp/errors/\(code)",
                    mimeType: "application/json"
                )
            ),
        ]

        return CallTool.Result(
            content: content,
            isError: true
        )
    }

    private static func jsonText(from value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func textContent(_ text: String) -> MCP.Tool.Content {
        .text(text: text, annotations: nil, _meta: nil)
    }
}
