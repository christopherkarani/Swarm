import Foundation
@testable import Swarm
import Testing

@Suite("Observability Privacy Tests")
struct ObservabilityPrivacyTests {
    @Test("public trace log sanitizer removes sensitive content from messages metadata and errors")
    func publicTraceLogSanitizerRedactsSensitiveContent() {
        let traceId = UUID()
        let spanId = UUID()
        let secret = "sk-live-secret raw thought plan tool args"
        let event = TraceEvent(
            traceId: traceId,
            spanId: spanId,
            kind: .toolError,
            level: .error,
            message: "Tool failed with \(secret)",
            metadata: [
                "thought": .string(secret),
                "plan": .string(secret),
                "arguments": .dictionary(["api_key": .string(secret)]),
                "error_message": .string(secret),
                "safe_count": .int(2)
            ],
            agentName: "ResearchAgent",
            toolName: "websearch",
            error: ErrorInfo(
                type: "FetchError",
                message: secret,
                stackTrace: ["frame with \(secret)"],
                underlyingError: secret
            )
        )

        let message = TraceEventPublicLogSanitizer.message(for: event)
        let metadata = TraceEventPublicLogSanitizer.metadata(for: event)
        let error = TraceEventPublicLogSanitizer.errorSummary(for: event.error)

        #expect(message.contains(secret) == false)
        #expect(metadata.description.contains(secret) == false)
        #expect(error.contains(secret) == false)
        #expect(metadata["safe_count"] == .int(2))
        #expect(metadata["arguments"] == .string("[redacted]"))
        #expect(metadata["thought"] == .string("[redacted]"))
        #expect(error == "FetchError: [redacted]")
    }

    @Test("public trace log sanitizer redacts credential-bearing metadata keys")
    func publicTraceLogSanitizerRedactsCredentialKeys() {
        let secret = "[REDACTED] credential value"
        let event = TraceEvent(
            traceId: UUID(),
            spanId: UUID(),
            kind: .toolCall,
            level: .info,
            message: "Tool call",
            metadata: [
                "api_key": .string(secret),
                "apiKey": .string(secret),
                "Authorization": .string("Bearer \(secret)"),
                "token": .string(secret),
                "mcp-session-id": .string(secret),
                "cookie": .string(secret),
                "client_secret": .string(secret),
                "safe_count": .int(2),
                "input_tokens": .int(11),
                "output_tokens": .int(7),
                "total_tokens": .int(18)
            ],
            agentName: "ResearchAgent",
            toolName: "websearch",
            error: nil
        )

        let metadata = TraceEventPublicLogSanitizer.metadata(for: event)

        #expect(metadata.description.contains(secret) == false)
        #expect(metadata["api_key"] == .string("[redacted]"))
        #expect(metadata["apiKey"] == .string("[redacted]"))
        #expect(metadata["Authorization"] == .string("[redacted]"))
        #expect(metadata["token"] == .string("[redacted]"))
        #expect(metadata["mcp-session-id"] == .string("[redacted]"))
        #expect(metadata["cookie"] == .string("[redacted]"))
        #expect(metadata["client_secret"] == .string("[redacted]"))
        #expect(metadata["safe_count"] == .int(2))
        #expect(metadata["total_tokens"] == .int(18))
        // `input_tokens` / `output_tokens` match the long-standing
        // `input` / `output` content tokens, so they stay redacted.
        #expect(metadata["input_tokens"] == .string("[redacted]"))
        #expect(metadata["output_tokens"] == .string("[redacted]"))
    }
}
