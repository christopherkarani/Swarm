#if SWARM_OTEL
// OTLPHTTPExporterConfiguration.swift
// SwarmOpenTelemetry

import Foundation
import Swarm

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for Swarm's in-house OTLP/HTTP JSON span exporter.
///
/// Posts completed spans to an OpenTelemetry Collector (or any OTLP/HTTP
/// receiver) as `application/json`. There is no gRPC dependency.
///
/// ## Defaults
///
/// - Endpoint: `http://localhost:4318/v1/traces`
/// - Batching: flush when ``maxBatchSize`` spans are queued, or every
///   ``scheduleDelay``, whichever comes first
/// - Retry: one retry with ``retryBackoff`` on 5xx and network failures;
///   4xx responses are not retried
/// - Queue: at most ``maxQueueSize`` spans; the oldest are dropped when full
/// - Requeue: a batch that still fails transiently is retried on up to
///   ``maxExportAttempts`` flushes before its spans are dropped
/// - Synchronous `flush`/`shutdown`: wait at most ``syncTimeout``
///
/// ```swift
/// let exporter = OTLPHTTPTraceExporter(
///     configuration: .default
///         .endpoint(URL(string: "http://localhost:4318/v1/traces")!)
///         .headers(["Authorization": "Bearer collector-token"])
/// )
/// ```
public struct OTLPHTTPExporterConfiguration: Sendable, Equatable {
    /// Default OTLP/HTTP traces path on a local collector.
    public static let defaultEndpoint = URL(string: "http://localhost:4318/v1/traces")!

    /// Configuration with collector defaults.
    public static let `default` = OTLPHTTPExporterConfiguration()

    /// OTLP/HTTP traces endpoint.
    public var endpoint: URL

    /// Extra headers sent with each export (collector auth, tenant keys).
    public var headers: [String: String]

    /// Resource attributes merged onto every exported batch.
    ///
    /// Default includes `service.name = swarm`. Span-level resource attributes
    /// from the SDK are preserved; these values win on key collision.
    public var resourceAttributes: [String: String]

    /// Flush immediately once this many spans are queued. Default: `64`.
    public var maxBatchSize: Int

    /// Flush remaining spans on this interval. Default: 5 seconds.
    public var scheduleDelay: Duration

    /// Extra attempts after the first POST. Default: `1` (retry once).
    public var maxRetries: Int

    /// Delay before a retry. Default: 200 milliseconds.
    public var retryBackoff: Duration

    /// Maximum spans held for export. When full, the oldest spans are dropped
    /// and counted in ``OTLPHTTPTraceExporter/droppedSpanCount``. Never less
    /// than ``maxBatchSize``, so a full batch can always trigger a flush.
    /// Default: `2048`.
    public var maxQueueSize: Int

    /// Flushes a span may take part in before it is dropped after transient
    /// failures (each flush already includes ``maxRetries`` POST retries).
    /// Default: `3`.
    public var maxExportAttempts: Int

    /// Longest the synchronous `flush`/`shutdown` wait for the POST when the
    /// caller passes no explicit timeout, in seconds. Default: `10`.
    public var syncTimeout: TimeInterval

    /// Creates an exporter configuration.
    ///
    /// - Parameters:
    ///   - endpoint: OTLP/HTTP traces URL. Default: ``defaultEndpoint``
    ///   - headers: Extra HTTP headers. Default: `[:]`
    ///   - resourceAttributes: Resource attributes to merge. Default:
    ///     `["service.name": "swarm"]`
    ///   - maxBatchSize: Size-based flush threshold. Default: `64`
    ///   - scheduleDelay: Timer-based flush interval. Default: 5 seconds
    ///   - maxRetries: Retry count after the first attempt. Default: `1`
    ///   - retryBackoff: Delay between retries. Default: 200 milliseconds
    ///   - maxQueueSize: Queue capacity before dropping oldest spans; raised to
    ///     `maxBatchSize` if smaller. Default: `2048`
    ///   - maxExportAttempts: Flushes per span before dropping it. Default: `3`
    ///   - syncTimeout: Default wait for synchronous flush, in seconds. Default: `10`
    public init(
        endpoint: URL = defaultEndpoint,
        headers: [String: String] = [:],
        resourceAttributes: [String: String] = ["service.name": "swarm"],
        maxBatchSize: Int = 64,
        scheduleDelay: Duration = .seconds(5),
        maxRetries: Int = 1,
        retryBackoff: Duration = .milliseconds(200),
        maxQueueSize: Int = 2048,
        maxExportAttempts: Int = 3,
        syncTimeout: TimeInterval = 10
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.resourceAttributes = resourceAttributes
        self.maxBatchSize = max(1, maxBatchSize)
        self.scheduleDelay = scheduleDelay > .zero ? scheduleDelay : .seconds(5)
        self.maxRetries = max(0, maxRetries)
        self.retryBackoff = retryBackoff >= .zero ? retryBackoff : .milliseconds(200)
        self.maxQueueSize = max(self.maxBatchSize, maxQueueSize)
        self.maxExportAttempts = max(1, maxExportAttempts)
        self.syncTimeout = Self.validSyncTimeout(syncTimeout)
    }

    /// Sets the OTLP/HTTP traces endpoint.
    @discardableResult
    public func endpoint(_ value: URL) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.endpoint = value
        return copy
    }

    /// Sets extra HTTP headers for collector authentication.
    @discardableResult
    public func headers(_ value: [String: String]) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.headers = value
        return copy
    }

    /// Sets resource attributes merged onto every batch.
    @discardableResult
    public func resourceAttributes(_ value: [String: String]) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.resourceAttributes = value
        return copy
    }

    /// Sets the size-based flush threshold, raising ``maxQueueSize`` to match
    /// if it is smaller.
    @discardableResult
    public func maxBatchSize(_ value: Int) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.maxBatchSize = max(1, value)
        copy.maxQueueSize = max(copy.maxQueueSize, copy.maxBatchSize)
        return copy
    }

    /// Sets the timer-based flush interval.
    @discardableResult
    public func scheduleDelay(_ value: Duration) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.scheduleDelay = value > .zero ? value : .seconds(5)
        return copy
    }

    /// Sets how many times a failed POST is retried.
    @discardableResult
    public func maxRetries(_ value: Int) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.maxRetries = max(0, value)
        return copy
    }

    /// Sets the delay before a retry.
    @discardableResult
    public func retryBackoff(_ value: Duration) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.retryBackoff = value >= .zero ? value : .milliseconds(200)
        return copy
    }
}

public extension OTLPHTTPExporterConfiguration {
    /// Sets the queue capacity; the oldest spans are dropped beyond it.
    /// Values below ``maxBatchSize`` are raised to it.
    @discardableResult
    func maxQueueSize(_ value: Int) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.maxQueueSize = max(copy.maxBatchSize, value)
        return copy
    }

    /// Sets how many flushes a span may take part in before it is dropped.
    @discardableResult
    func maxExportAttempts(_ value: Int) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.maxExportAttempts = max(1, value)
        return copy
    }

    /// Sets the default wait for synchronous `flush`/`shutdown`, in seconds.
    @discardableResult
    func syncTimeout(_ value: TimeInterval) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.syncTimeout = Self.validSyncTimeout(value)
        return copy
    }

    /// Finite, non-negative timeouts pass through; anything else uses the default.
    internal static func validSyncTimeout(_ value: TimeInterval) -> TimeInterval {
        value.isFinite && value >= 0 ? value : 10
    }
}

extension OTLPHTTPExporterConfiguration: CustomDebugStringConvertible {
    /// Debug description with sensitive header values (collector auth) redacted.
    public var debugDescription: String {
        "OTLPHTTPExporterConfiguration(endpoint: \(endpoint), headers: \(SecretRedaction.redactedSensitiveValues(headers)), resourceAttributes: \(resourceAttributes), maxBatchSize: \(maxBatchSize))"
    }
}
#endif
