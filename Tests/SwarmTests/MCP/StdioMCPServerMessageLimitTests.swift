import Foundation
@testable import Swarm
import Testing

@Suite("StdioMCPServer message size limit")
struct StdioMCPServerMessageLimitTests {
    @Test("Default message size limit is 16 MB")
    func defaultLimit() {
        #expect(StdioMCPServer.defaultMaxMessageSize == 16 * 1024 * 1024)
    }

    @Test("Non-positive message size limits are rejected")
    func rejectsNonPositiveLimit() {
        #expect(throws: MCPError.self) {
            _ = try StdioMCPServer(command: "/bin/sh", name: "zero-limit", maxMessageSize: 0)
        }
    }

    // Live stdio spawns hang on Linux CI runners; see StdioMCPServerSecurityTests.
    #if os(macOS)
    @Test("Output without a newline beyond the limit fails the connection")
    func oversizedUnterminatedOutputFailsConnection() async throws {
        let server = try StdioMCPServer(
            command: "/bin/sh",
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\000' a; sleep 30"],
            name: "flood",
            timeout: 20,
            maxMessageSize: 4096
        )
        defer { Task { try? await server.close() } }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await server.initialize()
            Issue.record("Expected initialize to fail once stdout exceeded the limit")
        } catch let error as MCPError {
            #expect(error.message.contains("4096"), "\(error.message)")
            #expect(error.message.contains("flood"), "\(error.message)")
        }
        // Fails on the limit, not on the 20 s request timeout.
        #expect(clock.now - start < .seconds(10))

        // The connection stays failed instead of buffering more output.
        await #expect(throws: MCPError.self) {
            _ = try await server.listTools()
        }
    }
    #endif
}
