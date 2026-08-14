// TraceContextHeaders.swift
// Swarm Framework
//
// W3C Trace Context headers for outbound HTTP requests.

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// W3C Trace Context headers (`traceparent` and optional `tracestate`).
///
/// Use ``current`` / ``httpHeaders`` to inject the active span into outbound
/// HTTP requests. Swarm's OpenTelemetry wrappers populate the current value
/// for the duration of each agent and LLM span. Built-in Web tool requests
/// apply these headers automatically. Custom providers should call
/// ``applyCurrent(to:)`` before sending a request.
///
/// The `traceparent` format matches the W3C Trace Context spec exactly:
/// `version-traceid-parentid-flags` (lowercase hex).
///
/// ```swift
/// var request = URLRequest(url: endpoint)
/// TraceContextHeaders.applyCurrent(to: &request)
/// ```
public struct TraceContextHeaders: Sendable, Hashable {
    /// W3C `traceparent` header name.
    public static let traceparentHeaderName = "traceparent"

    /// W3C `tracestate` header name.
    public static let tracestateHeaderName = "tracestate"

    /// Regex for a valid W3C `traceparent` (`version-traceid-parentid-flags`).
    public static let traceparentPattern = "^[0-9a-f]{2}-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$"

    /// The current headers for this task, if a span is active.
    public static var current: TraceContextHeaders? {
        TraceContextHeadersStorage.current
    }

    /// W3C `traceparent` value (`00-{trace-id}-{span-id}-{flags}`).
    public let traceparent: String

    /// W3C `tracestate` value, when vendors have propagated extra state.
    public let tracestate: String?

    /// 32-character lowercase hex trace id parsed from ``traceparent``.
    public var traceId: String {
        components.traceId
    }

    /// 16-character lowercase hex span id parsed from ``traceparent``.
    public var spanId: String {
        components.spanId
    }

    /// 2-character lowercase hex flags parsed from ``traceparent``.
    public var flags: String {
        components.flags
    }

    /// Header name/value pairs suitable for an outbound `URLRequest`.
    public var httpHeaders: [String: String] {
        var headers = [Self.traceparentHeaderName: traceparent]
        if let tracestate, !tracestate.isEmpty {
            headers[Self.tracestateHeaderName] = tracestate
        }
        return headers
    }

    /// Creates headers from a fully formed W3C `traceparent` string.
    ///
    /// - Parameters:
    ///   - traceparent: A `version-traceid-parentid-flags` value.
    ///   - tracestate: Optional vendor `tracestate`.
    /// - Returns: `nil` when `traceparent` is not a valid W3C value.
    public init?(traceparent: String, tracestate: String? = nil) {
        guard Self.isValidTraceparent(traceparent) else { return nil }
        self.traceparent = traceparent
        self.tracestate = tracestate.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Builds a W3C `traceparent` from hex identifiers.
    ///
    /// - Parameters:
    ///   - traceId: 32-character hex trace id (case-insensitive; stored lowercase).
    ///   - spanId: 16-character hex span id (case-insensitive; stored lowercase).
    ///   - sampled: When `true`, flags are `01`; otherwise `00`.
    ///   - tracestate: Optional vendor `tracestate`.
    /// - Returns: `nil` when either identifier is the wrong length or not hex.
    public init?(
        traceId: String,
        spanId: String,
        sampled: Bool = true,
        tracestate: String? = nil
    ) {
        let normalizedTraceId = traceId.lowercased()
        let normalizedSpanId = spanId.lowercased()
        guard Self.isHex(normalizedTraceId, count: 32),
              Self.isHex(normalizedSpanId, count: 16)
        else {
            return nil
        }
        let flags = sampled ? "01" : "00"
        self.traceparent = "00-\(normalizedTraceId)-\(normalizedSpanId)-\(flags)"
        self.tracestate = tracestate.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Runs `operation` with ``current`` set to `headers`.
    ///
    /// OpenTelemetry wrappers use this so built-in HTTP clients and custom
    /// providers see the active span. Prefer ``applyCurrent(to:)`` at call sites.
    public static func withCurrent<T: Sendable>(
        _ headers: TraceContextHeaders?,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await TraceContextHeadersStorage.$current.withValue(headers) {
            try await operation()
        }
    }

    /// Applies ``current`` headers onto `request`. No-op when no span is active.
    public static func applyCurrent(to request: inout URLRequest) {
        current?.apply(to: &request)
    }

    /// Applies these headers onto `request`, overwriting any existing values.
    public func apply(to request: inout URLRequest) {
        request.setValue(traceparent, forHTTPHeaderField: Self.traceparentHeaderName)
        if let tracestate {
            request.setValue(tracestate, forHTTPHeaderField: Self.tracestateHeaderName)
        }
    }

    /// Returns whether `value` is a spec-valid W3C `traceparent`.
    public static func isValidTraceparent(_ value: String) -> Bool {
        guard value.count == 55 else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return isHex(String(parts[0]), count: 2)
            && isHex(String(parts[1]), count: 32)
            && isHex(String(parts[2]), count: 16)
            && isHex(String(parts[3]), count: 2)
    }

    private var components: (traceId: String, spanId: String, flags: String) {
        let parts = traceparent.split(separator: "-")
        return (String(parts[1]), String(parts[2]), String(parts[3]))
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.unicodeScalars.allSatisfy { scalar in
            (48 ... 57).contains(scalar.value) || (97 ... 102).contains(scalar.value)
        }
    }
}

private enum TraceContextHeadersStorage {
    @TaskLocal
    static var current: TraceContextHeaders?
}
