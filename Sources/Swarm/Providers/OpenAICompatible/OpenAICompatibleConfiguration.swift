// OpenAICompatibleConfiguration.swift
// Swarm Framework
//
// Configuration for the OpenAI-compatible remote inference provider.

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How ``OpenAICompatibleProvider`` produces structured JSON.
///
/// Matches the Chunk I honesty rule: only claim
/// ``StructuredOutputResult/Source/providerNative`` when the request actually
/// used a provider constraint (`response_format`).
public enum OpenAICompatibleStructuredOutputMode: String, Sendable, Equatable, Codable {
    /// Send `response_format` (`json_schema` or `json_object`) and label the
    /// result ``StructuredOutputResult/Source/providerNative``.
    ///
    /// Use for OpenAI, Azure OpenAI, and OpenRouter. Local servers that ignore
    /// `response_format` should use ``promptFallback`` instead.
    case nativeJSONSchema

    /// Append JSON instructions and parse the reply. Label
    /// ``StructuredOutputResult/Source/promptFallback``.
    ///
    /// Default for Ollama and LM Studio, which do not reliably constrain
    /// generation via `response_format`.
    case promptFallback
}

/// Configuration for ``OpenAICompatibleProvider``.
///
/// Every supported host is `baseURL` + optional `apiKey` + `model` + extra
/// headers. Convenience factories fill those fields for OpenAI, Azure OpenAI,
/// OpenRouter, Ollama, and LM Studio.
///
/// ## Privacy
///
/// Prompt content, tool schemas, and tool results are sent to `baseURL`.
/// Contrast with ``FoundationModelsInferenceProvider``, which stays on-device.
///
/// ```swift
/// let cloud = OpenAICompatibleProviderConfiguration.openAI(
///     apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
///     model: "gpt-4o"
/// )
/// let local = OpenAICompatibleProviderConfiguration.ollama(model: "llama3.2")
/// ```
public struct OpenAICompatibleProviderConfiguration: Sendable, Equatable {
    /// API root. `/chat/completions` is appended unless `baseURL` already ends
    /// with that path.
    public var baseURL: URL

    /// Bearer token. Omit for local servers that do not require auth.
    ///
    /// Not sent when `httpHeaders` already contains `Authorization` or `api-key`
    /// (Azure).
    public var apiKey: String?

    /// Keychain (or other ``SecretStore``) pointer for the Bearer token
    ///
    /// Resolved at request time when ``apiKey`` is `nil` or empty. The
    /// provider must be given a store via
    /// `OpenAICompatibleProvider(configuration:secretStore:)`; without one
    /// the reference cannot resolve and no `Authorization` header is sent.
    /// Prefer this over embedding the raw key when the configuration is
    /// persisted or logged.
    public var apiKeyReference: SecretReference?

    /// Model or deployment identifier placed in the request `model` field.
    public var model: String

    /// Extra headers merged onto every request (for example Azure `api-key`,
    /// OpenRouter `HTTP-Referer`).
    public var httpHeaders: [String: String]

    /// Query items appended to the chat-completions URL (Azure `api-version`).
    public var queryItems: [String: String]

    /// Whether structured outputs use native `response_format` or prompt-parse.
    public var structuredOutputMode: OpenAICompatibleStructuredOutputMode

    /// Stable provider name for ``InferenceProviderMetadata`` (`openai`,
    /// `ollama`, `azure-openai`, …).
    public var providerName: String

    /// When `true`, advertise ``InferenceProviderCapabilities/multimodalAudio``
    /// and emit input-audio parts. Defaults to `false` (fail closed).
    public var supportsMultimodalAudio: Bool

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - baseURL: API root. `/chat/completions` is appended when missing.
    ///   - apiKey: Optional Bearer token. Default: `nil`.
    ///   - apiKeyReference: Optional ``SecretStore`` pointer used when
    ///     `apiKey` is `nil` or empty. Default: `nil`.
    ///   - model: Model or deployment identifier.
    ///   - httpHeaders: Extra headers. Default: `[:]`.
    ///   - queryItems: Extra query items. Default: `[:]`.
    ///   - structuredOutputMode: Native `response_format` vs prompt-parse.
    ///     Default: ``OpenAICompatibleStructuredOutputMode/nativeJSONSchema``.
    ///   - providerName: Metadata name. Default: `openai-compatible`.
    ///   - supportsMultimodalAudio: Advertise audio attachments. Default: `false`.
    public init(
        baseURL: URL,
        apiKey: String? = nil,
        apiKeyReference: SecretReference? = nil,
        model: String,
        httpHeaders: [String: String] = [:],
        queryItems: [String: String] = [:],
        structuredOutputMode: OpenAICompatibleStructuredOutputMode = .nativeJSONSchema,
        providerName: String = "openai-compatible",
        supportsMultimodalAudio: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.apiKeyReference = apiKeyReference
        self.model = model
        self.httpHeaders = httpHeaders
        self.queryItems = queryItems
        self.structuredOutputMode = structuredOutputMode
        self.providerName = providerName
        self.supportsMultimodalAudio = supportsMultimodalAudio
    }

    /// Resolves the effective API key.
    ///
    /// The inline ``apiKey`` wins when non-empty; otherwise the reference is
    /// loaded from `store`. Returns `nil` when neither is available — for
    /// example a reference with no store, or a store with no matching secret.
    ///
    /// - Parameters:
    ///   - store: Backend holding the referenced secret, if any.
    ///   - reference: Pointer to resolve. Defaults to ``apiKeyReference``.
    /// - Returns: The effective key, or `nil` when unavailable.
    public func resolveAPIKey(
        using store: (any SecretStore)?,
        reference: SecretReference? = nil
    ) async throws -> String? {
        let inline = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inline, !inline.isEmpty {
            return inline
        }
        let pointer = reference ?? apiKeyReference
        guard let pointer, let store else { return nil }
        return try await store.secret(for: pointer)
    }

    /// OpenAI Chat Completions (`https://api.openai.com/v1`).
    public static func openAI(
        apiKey: String,
        model: String = "gpt-4o"
    ) -> OpenAICompatibleProviderConfiguration {
        OpenAICompatibleProviderConfiguration(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: apiKey,
            model: model,
            structuredOutputMode: .nativeJSONSchema,
            providerName: "openai"
        )
    }

    /// Azure OpenAI chat completions.
    ///
    /// Uses `api-key` auth and `api-version` on
    /// `https://{resource}.openai.azure.com/openai/deployments/{deployment}`.
    public static func azureOpenAI(
        resource: String,
        deployment: String,
        apiKey: String,
        apiVersion: String = "2024-10-21",
        model: String? = nil
    ) -> OpenAICompatibleProviderConfiguration {
        let url = URL(
            string: "https://\(resource).openai.azure.com/openai/deployments/\(deployment)"
        )!
        return OpenAICompatibleProviderConfiguration(
            baseURL: url,
            apiKey: nil,
            model: model ?? deployment,
            httpHeaders: ["api-key": apiKey],
            queryItems: ["api-version": apiVersion],
            structuredOutputMode: .nativeJSONSchema,
            providerName: "azure-openai"
        )
    }

    /// OpenRouter (`https://openrouter.ai/api/v1`).
    public static func openRouter(
        apiKey: String,
        model: String,
        httpHeaders: [String: String] = [:]
    ) -> OpenAICompatibleProviderConfiguration {
        OpenAICompatibleProviderConfiguration(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            apiKey: apiKey,
            model: model,
            httpHeaders: httpHeaders,
            structuredOutputMode: .nativeJSONSchema,
            providerName: "openrouter"
        )
    }

    /// Ollama's OpenAI-compatible endpoint (default `http://127.0.0.1:11434/v1`).
    ///
    /// Structured outputs use prompt-parse fallback — Ollama does not reliably
    /// honor `response_format.json_schema`.
    public static func ollama(
        model: String,
        baseURL: URL = URL(string: "http://127.0.0.1:11434/v1")!
    ) -> OpenAICompatibleProviderConfiguration {
        OpenAICompatibleProviderConfiguration(
            baseURL: baseURL,
            apiKey: nil,
            model: model,
            structuredOutputMode: .promptFallback,
            providerName: "ollama"
        )
    }

    /// LM Studio's OpenAI-compatible endpoint (default `http://127.0.0.1:1234/v1`).
    ///
    /// Structured outputs use prompt-parse fallback unless you opt into
    /// ``OpenAICompatibleStructuredOutputMode/nativeJSONSchema``.
    public static func lmStudio(
        model: String,
        baseURL: URL = URL(string: "http://127.0.0.1:1234/v1")!,
        apiKey: String? = nil
    ) -> OpenAICompatibleProviderConfiguration {
        OpenAICompatibleProviderConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            structuredOutputMode: .promptFallback,
            providerName: "lmstudio"
        )
    }
}

extension OpenAICompatibleProviderConfiguration: CustomDebugStringConvertible {
    /// Debug description with the API key and sensitive headers redacted.
    ///
    /// The key renders as `"[redacted]"` when set so `print` and log SDKs
    /// never capture it; use ``resolveAPIKey(using:reference:)`` to read it.
    public var debugDescription: String {
        let key = apiKey == nil ? "nil" : "\"\(SecretRedaction.placeholder)\""
        return "OpenAICompatibleProviderConfiguration(baseURL: \(baseURL), apiKey: \(key), apiKeyReference: \(String(describing: apiKeyReference)), model: \"\(model)\", httpHeaders: \(SecretRedaction.redactedSensitiveValues(httpHeaders)), queryItems: \(SecretRedaction.redactedSensitiveValues(queryItems)), structuredOutputMode: \(structuredOutputMode), providerName: \"\(providerName)\")"
    }
}
