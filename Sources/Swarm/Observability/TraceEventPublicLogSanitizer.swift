// TraceEventPublicLogSanitizer.swift
// Swarm Framework
//
// Redacts trace event payloads before they are written to public logs.

import Foundation

enum TraceEventPublicLogSanitizer {
    private static let redacted = SendableValue.string("[redacted]")
    private static let sensitiveMetadataTokens = [
        "argument",
        "args",
        "content",
        "decision",
        "error",
        "input",
        "message",
        "option",
        "output",
        "plan",
        "prompt",
        "reasoning",
        "result",
        "thought",
    ]
    private static let sensitiveSecretTokens = [
        "secret",
        "password",
        "passwd",
        "credential",
        "authorization",
        "bearer",
        "cookie",
        "api_key",
        "apikey",
        "api-key",
        "private_key",
        "privatekey",
        "private-key",
        "session_id",
        "sessionid",
        "session-id",
        "access_token",
        "accesstoken",
        "refresh_token",
        "refreshtoken",
        "id_token",
        "auth_token",
        "auth-token",
        "authtoken",
        "client_secret",
        "clientsecret",
    ]
    private static let sensitiveSecretKeys: Set<String> = [
        "token",
        "secret",
        "password",
        "passwd",
        "credential",
        "credentials",
        "authorization",
        "cookie",
        "bearer",
        "apikey",
        "api_key",
        "api-key",
        "sessionid",
        "session_id",
        "mcp-session-id",
        "privatekey",
        "private_key",
    ]

    static func message(for event: TraceEvent) -> String {
        switch event.kind {
        case .agentStart:
            "Agent started"
        case .agentComplete:
            "Agent completed"
        case .agentCancelled:
            "Agent cancelled"
        case .agentError:
            "Agent error recorded"
        case .toolCall:
            "Tool call recorded"
        case .toolResult:
            "Tool result recorded"
        case .toolError:
            "Tool error recorded"
        case .thought:
            "Thought recorded"
        case .decision:
            "Decision recorded"
        case .plan:
            "Plan recorded"
        case .memoryRead:
            "Memory read recorded"
        case .memoryWrite:
            "Memory write recorded"
        case .checkpoint:
            "Checkpoint recorded"
        case .metric:
            "Metric recorded"
        case .custom:
            "Custom event recorded"
        }
    }

    static func metadata(for event: TraceEvent) -> [String: SendableValue] {
        event.metadata.mapValues { value in
            value
        }
        .reduce(into: [:]) { sanitized, element in
            let key = element.key
            sanitized[key] = isSensitiveMetadataKey(key) ? redacted : element.value
        }
    }

    static func errorSummary(for error: ErrorInfo?) -> String {
        guard let error else { return "" }
        return "\(error.type): [redacted]"
    }

    private static func isSensitiveMetadataKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        if sensitiveSecretKeys.contains(lowercased) {
            return true
        }
        if sensitiveSecretTokens.contains(where: { lowercased.contains($0) }) {
            return true
        }
        return sensitiveMetadataTokens.contains { lowercased.contains($0) }
    }
}
