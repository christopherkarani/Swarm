#if SWARM_OTEL
// OTLPJSON.swift
// SwarmOpenTelemetry

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

enum OTLPJSON {
    static func payload(
        spans: [SpanData],
        resourceAttributes: [String: String]
    ) throws -> Data {
        let request = ExportRequest(
            resourceSpans: group(spans: spans, resourceAttributes: resourceAttributes)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(request)
    }

    private static func group(
        spans: [SpanData],
        resourceAttributes: [String: String]
    ) -> [ResourceSpans] {
        var buckets: [GroupKey: [SpanData]] = [:]
        for span in spans {
            let key = GroupKey(
                resource: encodeAttributes(
                    span.resource.attributes,
                    overlay: resourceAttributes
                ),
                scopeName: span.instrumentationScope.name,
                scopeVersion: span.instrumentationScope.version ?? ""
            )
            buckets[key, default: []].append(span)
        }

        return buckets.map { key, grouped in
            ResourceSpans(
                resource: Resource(attributes: key.resource),
                scopeSpans: [
                    ScopeSpans(
                        scope: InstrumentationScope(
                            name: key.scopeName,
                            version: key.scopeVersion.isEmpty ? nil : key.scopeVersion
                        ),
                        spans: grouped.map(encodeSpan)
                    )
                ]
            )
        }
    }

    private static func encodeSpan(_ span: SpanData) -> Span {
        Span(
            traceId: span.traceId.hexString,
            spanId: span.spanId.hexString,
            parentSpanId: span.parentSpanId?.hexString,
            name: span.name,
            kind: otlpKind(span.kind),
            startTimeUnixNano: unixNano(span.startTime),
            endTimeUnixNano: unixNano(span.endTime),
            attributes: encodeAttributes(span.attributes, overlay: [:]),
            status: SpanStatus(
                code: otlpStatus(span.status),
                message: statusMessage(span.status)
            )
        )
    }

    private static func encodeAttributes(
        _ attributes: [String: AttributeValue],
        overlay: [String: String]
    ) -> [KeyValue] {
        var merged: [String: AnyValue] = [:]
        for (key, value) in attributes {
            merged[key] = anyValue(value)
        }
        for (key, value) in overlay {
            merged[key] = AnyValue(stringValue: value)
        }
        return merged.keys.sorted().map { KeyValue(key: $0, value: merged[$0]!) }
    }

    private static func anyValue(_ value: AttributeValue) -> AnyValue {
        switch value {
        case let .string(string):
            return AnyValue(stringValue: string)
        case let .bool(bool):
            return AnyValue(boolValue: bool)
        case let .int(int):
            return AnyValue(intValue: String(int))
        case let .double(double):
            return AnyValue(doubleValue: double)
        case let .stringArray(values):
            return AnyValue(stringValue: values.joined(separator: ","))
        case let .boolArray(values):
            return AnyValue(stringValue: values.map { $0 ? "true" : "false" }.joined(separator: ","))
        case let .intArray(values):
            return AnyValue(stringValue: values.map(String.init).joined(separator: ","))
        case let .doubleArray(values):
            return AnyValue(stringValue: values.map { String($0) }.joined(separator: ","))
        case let .array(array):
            return AnyValue(stringValue: array.description)
        case let .set(set):
            return AnyValue(stringValue: set.labels.description)
        }
    }

    private static func otlpKind(_ kind: SpanKind) -> Int {
        switch kind {
        case .internal: return 1
        case .server: return 2
        case .client: return 3
        case .producer: return 4
        case .consumer: return 5
        }
    }

    /// OTLP status codes (not the Swift SDK's `Status.code`, which swaps OK/UNSET).
    private static func otlpStatus(_ status: OpenTelemetryApi.Status) -> Int {
        switch status {
        case .unset: return 0
        case .ok: return 1
        case .error: return 2
        }
    }

    private static func statusMessage(_ status: OpenTelemetryApi.Status) -> String? {
        if case let .error(description) = status, !description.isEmpty {
            return description
        }
        return nil
    }

    private static func unixNano(_ date: Date) -> String {
        let nanos = (date.timeIntervalSince1970 * 1_000_000_000).rounded()
        return String(UInt64(max(0, nanos)))
    }

    private struct GroupKey: Hashable {
        let resource: [KeyValue]
        let scopeName: String
        let scopeVersion: String
    }

    struct ExportRequest: Encodable {
        var resourceSpans: [ResourceSpans]
    }

    struct ResourceSpans: Encodable {
        var resource: Resource
        var scopeSpans: [ScopeSpans]
    }

    struct Resource: Encodable {
        var attributes: [KeyValue]
    }

    struct ScopeSpans: Encodable {
        var scope: InstrumentationScope
        var spans: [Span]
    }

    struct InstrumentationScope: Encodable {
        var name: String
        var version: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            if let version {
                try container.encode(version, forKey: .version)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case version
        }
    }

    struct Span: Encodable {
        var traceId: String
        var spanId: String
        var parentSpanId: String?
        var name: String
        var kind: Int
        var startTimeUnixNano: String
        var endTimeUnixNano: String
        var attributes: [KeyValue]
        var status: SpanStatus

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(traceId, forKey: .traceId)
            try container.encode(spanId, forKey: .spanId)
            if let parentSpanId {
                try container.encode(parentSpanId, forKey: .parentSpanId)
            }
            try container.encode(name, forKey: .name)
            try container.encode(kind, forKey: .kind)
            try container.encode(startTimeUnixNano, forKey: .startTimeUnixNano)
            try container.encode(endTimeUnixNano, forKey: .endTimeUnixNano)
            try container.encode(attributes, forKey: .attributes)
            try container.encode(status, forKey: .status)
        }

        private enum CodingKeys: String, CodingKey {
            case traceId
            case spanId
            case parentSpanId
            case name
            case kind
            case startTimeUnixNano
            case endTimeUnixNano
            case attributes
            case status
        }
    }

    struct SpanStatus: Encodable {
        var code: Int
        var message: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(code, forKey: .code)
            if let message {
                try container.encode(message, forKey: .message)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case code
            case message
        }
    }

    struct KeyValue: Encodable, Hashable {
        var key: String
        var value: AnyValue
    }

    struct AnyValue: Encodable, Hashable {
        var stringValue: String?
        var boolValue: Bool?
        var intValue: String?
        var doubleValue: Double?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let stringValue {
                try container.encode(stringValue, forKey: .stringValue)
            }
            if let boolValue {
                try container.encode(boolValue, forKey: .boolValue)
            }
            if let intValue {
                try container.encode(intValue, forKey: .intValue)
            }
            if let doubleValue {
                try container.encode(doubleValue, forKey: .doubleValue)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case stringValue
            case boolValue
            case intValue
            case doubleValue
        }
    }
}
#endif
