#if SWARM_INTEGRATIONS
import Wax

/// Lightweight helpers for the Wax embedding adapter.
public struct WaxIntegration {
    public init() {}

    /// Indicates whether the Wax integration is available for the current build.
    public var isEnabled: Bool { true }
}

public extension WaxIntegration {
    /// Returns a debug string that demonstrates the adapter is compiled.
    static var debugDescription: String { "Wax integration is enabled" }
}
#endif
