import Foundation
@testable import Swarm
import Testing

struct StdioMCPServerPlatformTests {
    @Test func initializeMissingExecutableDoesNotClaimMobileUnavailability() async {
        let server = StdioMCPServer(
            command: "/this/path/does/not/exist/swarm-mcp-fixture",
            name: "missing-stdio"
        )
        do {
            _ = try await server.initialize()
            Issue.record("Expected initialize() to throw for a missing executable.")
        } catch let error as MCPError {
            #expect(
                error.message.contains("unavailable on this platform") == false,
                "macOS/Linux should still use Process, not the mobile stdio stub"
            )
        } catch {
            Issue.record("Expected MCPError, got \(error)")
        }
        try? await server.close()
    }

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        @Test func initializeThrowsOnAppleMobilePlatforms() async throws {
            let server = StdioMCPServer(command: "/usr/bin/true", name: "ios-stdio")
            do {
                _ = try await server.initialize()
                Issue.record("Expected initialize() to throw on this platform.")
            } catch let error as MCPError {
                #expect(error.message.contains("unavailable on this platform"))
                #expect(error.message.contains("HTTP"))
            } catch {
                Issue.record("Expected MCPError, got \(error)")
            }
            try? await server.close()
        }
    #endif
}
