#if SWARM_OTEL
import Foundation
import Swarm
import Testing
@testable import SwarmOpenTelemetry

@Suite("OTLP exporter configuration redaction")
struct OTLPExporterConfigurationRedactionTests {
    @Test("Debug description redacts sensitive header values")
    func debugDescriptionRedactsSensitiveHeaders() {
        let configuration = OTLPHTTPExporterConfiguration.default
            .headers(["Authorization": "collector-credential-123", "X-Tenant": "visible-tenant"])
        let description = String(reflecting: configuration)
        #expect(!description.contains("collector-credential-123"))
        #expect(description.contains(SecretRedaction.placeholder))
        #expect(description.contains("visible-tenant"))
    }
}
#endif
