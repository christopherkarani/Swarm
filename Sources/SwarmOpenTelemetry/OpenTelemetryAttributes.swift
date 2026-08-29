#if SWARM_OTEL
// OpenTelemetryAttributes.swift
// SwarmOpenTelemetry

import Foundation
import OpenTelemetryApi
import Swarm

enum OpenTelemetryAttributes {
    static func applyMetadata(_ metadata: InferenceProviderMetadata?, to span: any SpanBase) {
        guard let metadata else { return }
        if let providerName = metadata.providerName {
            span.setAttribute(key: "gen_ai.provider.name", value: providerName)
        }
        if let modelName = metadata.modelName {
            span.setAttribute(key: "gen_ai.request.model", value: modelName)
        }
        if let endpointURL = metadata.endpointURL {
            if let host = endpointURL.host {
                span.setAttribute(key: "server.address", value: host)
            }
            if let port = endpointURL.port {
                span.setAttribute(key: "server.port", value: port)
            }
            span.setAttribute(key: "url.full", value: endpointURL.absoluteString)
        }
    }

    static func applyUsage(_ usage: TokenUsage?, to span: any SpanBase) {
        guard let usage else { return }
        span.setAttribute(key: "gen_ai.usage.input_tokens", value: usage.inputTokens)
        span.setAttribute(key: "gen_ai.usage.output_tokens", value: usage.outputTokens)
    }

    static func recordError(_ error: Error, on span: any SpanBase) {
        let errorType = String(reflecting: Swift.type(of: error))
        span.status = .error(description: error.localizedDescription)
        span.setAttribute(key: "error.type", value: errorType)
        if let recordingSpan = span as? any Span {
            recordingSpan.recordException(error, attributes: [
                "error.type": .string(errorType)
            ])
        }
    }
}
#endif
