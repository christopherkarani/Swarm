/// Build-time availability of Swarm's OpenTelemetry SwiftPM trait.
///
/// OpenTelemetry wrappers and OTLP/HTTP export in this product compile only
/// when the trait is enabled.
public enum OpenTelemetryTrait: Sendable {
    /// Whether this process was compiled with the `OpenTelemetry` SwiftPM trait.
    public static var isEnabled: Bool {
        #if SWARM_OTEL
        true
        #else
        false
        #endif
    }

    /// User-facing message naming the missing trait and the rebuild remedy.
    ///
    /// - Parameter feature: Short name of the gated capability.
    /// - Returns: A message that names the OpenTelemetry trait and how to enable it.
    public static func requirementMessage(for feature: String = "SwarmOpenTelemetry") -> String {
        "\(feature) requires the OpenTelemetry trait. Rebuild with `--traits OpenTelemetry`, or add `traits: [\"OpenTelemetry\"]` to the Swarm package dependency."
    }
}
