// InferenceProviderMetadata.swift
// Swarm Framework
//
// Optional metadata for observability integrations.

import Foundation

/// Optional provider metadata used by observability integrations.
///
/// Observability integrations read ``InferenceProvider/metadata``, not
/// conformance to this protocol. Return a snapshot from that property, or
/// conform here and rely on the constrained
/// `InferenceProvider where Self: InferenceProviderMetadata` bridge, which
/// supplies `{ self }`. Providers that expose neither still work; integrations
/// omit the unavailable attributes.
public protocol InferenceProviderMetadata: Sendable {
    /// Best-known provider name, for example `openai`, `anthropic`, or `ollama`.
    var providerName: String? { get }

    /// The requested model identifier, when known.
    var modelName: String? { get }

    /// The API endpoint or base URL, when known.
    var endpointURL: URL? { get }
}

/// Immutable metadata value used by provider adapters.
public struct InferenceProviderMetadataSnapshot: InferenceProviderMetadata, Equatable {
    public let providerName: String?
    public let modelName: String?
    public let endpointURL: URL?

    public init(providerName: String? = nil, modelName: String? = nil, endpointURL: URL? = nil) {
        self.providerName = providerName
        self.modelName = modelName
        self.endpointURL = endpointURL
    }
}

public extension InferenceProvider where Self: InferenceProviderMetadata {
    /// Bridges leftover ``InferenceProviderMetadata`` conformances onto the
    /// defaulted ``InferenceProvider/metadata`` requirement so existing
    /// conformers keep their observability attributes without source changes.
    var metadata: (any InferenceProviderMetadata)? { self }
}
