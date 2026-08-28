#if SWARM_OTEL
// OpenTelemetryTracePropagation.swift
// SwarmOpenTelemetry

import Foundation
import OpenTelemetryApi
import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// W3C Trace Context helpers backed by the current OpenTelemetry span.
///
/// ``currentHeaders`` reads the active OTel span when one exists, otherwise
/// ``TraceContextHeaders/current``. Custom inference providers should inject
/// these headers on outbound HTTP:
///
/// ```swift
/// var request = URLRequest(url: endpoint)
/// OpenTelemetryTracePropagation.applyCurrent(to: &request)
/// ```
public enum OpenTelemetryTracePropagation {
    /// W3C `traceparent` / `tracestate` for the current span, or `[:]` if none.
    public static var currentHeaders: [String: String] {
        current?.httpHeaders ?? [:]
    }

    /// The current W3C headers, or `nil` when no valid span is active.
    public static var current: TraceContextHeaders? {
        if let span = OpenTelemetry.instance.contextProvider.activeSpan,
           span.context.isValid
        {
            return TraceContextHeaders(spanContext: span.context)
        }
        return TraceContextHeaders.current
    }

    /// Applies the current W3C headers onto `request`. No-op when no span is active.
    public static func applyCurrent(to request: inout URLRequest) {
        current?.apply(to: &request)
    }

    /// Runs `operation` with Swarm's ``TraceContextHeaders/current`` bound to `span`.
    static func withCurrentSpan<T: Sendable>(
        _ span: any SpanBase,
        _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let headers = TraceContextHeaders(spanContext: span.context)
        return try await TraceContextHeaders.withCurrent(headers, operation: operation)
    }
}

extension TraceContextHeaders {
    init?(spanContext: SpanContext) {
        guard spanContext.isValid else { return nil }
        let tracestate = spanContext.traceState.entries
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        self.init(
            traceId: spanContext.traceId.hexString,
            spanId: spanContext.spanId.hexString,
            sampled: spanContext.isSampled,
            tracestate: tracestate.isEmpty ? nil : tracestate
        )
    }
}
#endif
