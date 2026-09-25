import Foundation
@testable import Swarm
import Testing

@Suite("Public trace log secret redaction")
struct PublicLogSecretRedactionTests {
    @Test("secret-bearing metadata keys are redacted from public logs")
    func secretBearingKeysRedacted() {
        let event = TraceEvent(
            traceId: UUID(),
            spanId: UUID(),
            kind: .toolCall,
            level: .info,
            message: "tool call",
            metadata: [
                "api_key": .string("sk-live-value"),
                "Authorization": .string("credential-value"),
                "token": .string("session-secret"),
                "session_id": .string("session-secret"),
                "password": .string("hunter2"),
                "client_secret": .string("shh"),
                "safe_count": .int(2),
                "tokenUsage": .int(42),
                "tokenCount": .int(7),
            ],
            agentName: "Agent",
            toolName: "tool"
        )

        let metadata = TraceEventPublicLogSanitizer.metadata(for: event)
        let rendered = metadata.description

        #expect(!rendered.contains("sk-live-value"))
        #expect(!rendered.contains("credential-value"))
        #expect(!rendered.contains("session-secret"))
        #expect(!rendered.contains("hunter2"))
        #expect(!rendered.contains("shh"))
        #expect(metadata["api_key"] == .string("[redacted]"))
        #expect(metadata["Authorization"] == .string("[redacted]"))
        #expect(metadata["token"] == .string("[redacted]"))
        #expect(metadata["session_id"] == .string("[redacted]"))

        // Benign keys pass through, including token-count telemetry whose
        // names merely contain "token" as a substring.
        #expect(metadata["safe_count"] == .int(2))
        #expect(metadata["tokenUsage"] == .int(42))
        #expect(metadata["tokenCount"] == .int(7))
    }
}
