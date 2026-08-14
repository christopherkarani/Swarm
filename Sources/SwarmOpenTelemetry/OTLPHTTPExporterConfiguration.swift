// OTLPHTTPExporterConfiguration.swift
// SwarmOpenTelemetry

import Foundation

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
    public init(
        endpoint: URL = defaultEndpoint,
        headers: [String: String] = [:],
        resourceAttributes: [String: String] = ["service.name": "swarm"],
        maxBatchSize: Int = 64,
        scheduleDelay: Duration = .seconds(5),
        maxRetries: Int = 1,
        retryBackoff: Duration = .milliseconds(200)
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.resourceAttributes = resourceAttributes
        self.maxBatchSize = max(1, maxBatchSize)
        self.scheduleDelay = scheduleDelay > .zero ? scheduleDelay : .seconds(5)
        self.maxRetries = max(0, maxRetries)
        self.retryBackoff = retryBackoff >= .zero ? retryBackoff : .milliseconds(200)
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

    /// Sets the size-based flush threshold.
    @discardableResult
    public func maxBatchSize(_ value: Int) -> OTLPHTTPExporterConfiguration {
        var copy = self
        copy.maxBatchSize = max(1, value)
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
