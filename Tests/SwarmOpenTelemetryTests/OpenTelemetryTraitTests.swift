import SwarmOpenTelemetry
import Testing

@Suite("OpenTelemetryTrait")
struct OpenTelemetryTraitTests {
    @Test("OpenTelemetryTrait.isEnabled matches the SWARM_OTEL compilation flag")
    func isEnabledMatchesCompilationFlag() {
        #if SWARM_OTEL
        #expect(OpenTelemetryTrait.isEnabled)
        #else
        #expect(!OpenTelemetryTrait.isEnabled)
        #endif
    }
}
