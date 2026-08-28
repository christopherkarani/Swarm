#if SWARM_INTEGRATIONS
import Wax

/// Deprecated compatibility marker for callers that used the original Wax integration surface.
///
/// Use ``IntegrationsTrait/isEnabled`` to inspect trait availability and use
/// ``WaxMemory`` or ``WaxEmbeddingProviderAdapter`` for Wax-backed behavior.
@available(*, deprecated, message: "Use IntegrationsTrait.isEnabled, WaxMemory, or WaxEmbeddingProviderAdapter instead.")
public struct WaxIntegration {
    @available(*, deprecated, message: "WaxIntegration is retained only for source compatibility.")
    public init() {}

    /// Indicates whether the Wax integration is available for the current build.
    @available(*, deprecated, message: "Use IntegrationsTrait.isEnabled instead.")
    public var isEnabled: Bool { true }
}

public extension WaxIntegration {
    /// Returns a debug string that demonstrates the adapter is compiled.
    @available(*, deprecated, message: "WaxIntegration.debugDescription is retained only for source compatibility.")
    static var debugDescription: String { "Wax integration is enabled" }
}
#endif
