/// Typed identity for ``MembraneContextBackend`` implementations.
///
/// The raw value is what ``MembraneContextBackend/backendID`` and
/// `ContextSnapshot.backendID` carry; the wrapper keeps backend IDs distinct
/// from pointer IDs, tool names, and other strings at call sites.
public struct MembraneBackendID: Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    /// Raw backend identifier.
    public let rawValue: String

    /// Creates an ID from a raw identifier.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Pass-through backend. Portable; the `MembraneSession` default.
    public static let passthrough = MembraneBackendID("passthrough")
    /// Bounded in-memory backend. Portable; inject explicitly on any platform.
    public static let inMemory = MembraneBackendID("in-memory")
    /// ContextCore-backed backend. Portable with Integrations (CPU/hash
    /// backends on Linux, Metal acceleration on Apple).
    public static let contextCore = MembraneBackendID("contextcore")

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}
