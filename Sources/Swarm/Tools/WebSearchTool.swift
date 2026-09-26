// WebSearchTool.swift
// Swarm Framework
//
// A multi-resolution web search, fetch, and grounding tool for strict-context agents.

import Foundation

public struct WebSearchTool: AnyJSONTool, Sendable {
    public enum Mode: String, Codable, Sendable, Equatable, CaseIterable {
        case search
        case fetch
        case ground
        case recall
        case expand
        case refresh
    }

    public enum Detail: String, Codable, Sendable, Equatable, CaseIterable {
        case compact
        case standard
        case deep
        case raw

        var includesDocument: Bool {
            switch self {
            case .compact, .standard:
                false
            case .deep, .raw:
                true
            }
        }
    }

    public enum SummaryMode: String, Codable, Sendable, Equatable, CaseIterable {
        case extractiveOnly
        case contextCoreThenFoundationModels
        case foundationModelsPreferred
    }

    public struct Configuration: Sendable, Equatable {
        public static let defaultStoreURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
        .appendingPathComponent("Swarm", isDirectory: true)
        .appendingPathComponent("WebMemoryPlane", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("SwarmWebMemoryPlane", isDirectory: true)

        public var apiKey: String?

        /// Keychain (or other ``SecretStore``) pointer for the search API key.
        ///
        /// Resolved at request time when ``apiKey`` is `nil` or empty. Pass a
        /// store via `WebSearchTool(configuration:secretStore:)`; without one
        /// the reference cannot resolve and live search returns no hits.
        /// Prefer this over embedding the raw key when the configuration is
        /// persisted or logged.
        public var apiKeyReference: SecretReference?

        public var contextProfile: ContextProfile
        public var summaryMode: SummaryMode
        public var fetchTimeout: TimeInterval
        public var maxBodyBytes: Int
        public var persistFetchedArtifacts: Bool
        public var localRecallSimilarityThreshold: Double
        public var maxGroundedFetches: Int
        public var maxEvidenceSections: Int
        public var storeURL: URL
        public var storageQuotaBytes: Int
        public var enabled: Bool
        public var userAgent: String
        public var maxConcurrentFetches: Int
        public var hostPolitenessDelay: TimeInterval
        public var persistEvidenceBundles: Bool

        public init(
            apiKey: String? = nil,
            apiKeyReference: SecretReference? = nil,
            contextProfile: ContextProfile = .strict4k,
            summaryMode: SummaryMode = .contextCoreThenFoundationModels,
            fetchTimeout: TimeInterval = 20,
            maxBodyBytes: Int = 1_500_000,
            persistFetchedArtifacts: Bool = true,
            localRecallSimilarityThreshold: Double = 0.82,
            maxGroundedFetches: Int = 3,
            maxEvidenceSections: Int = 6,
            storeURL: URL = Configuration.defaultStoreURL,
            storageQuotaBytes: Int = 64 * 1024 * 1024,
            enabled: Bool = true,
            userAgent: String = "SwarmWebMemoryPlane/1.0",
            maxConcurrentFetches: Int = 2,
            hostPolitenessDelay: TimeInterval = 0.2,
            persistEvidenceBundles: Bool = true
        ) {
            self.apiKey = apiKey
            self.apiKeyReference = apiKeyReference
            self.contextProfile = contextProfile
            self.summaryMode = summaryMode
            self.fetchTimeout = fetchTimeout
            self.maxBodyBytes = max(64_000, maxBodyBytes)
            self.persistFetchedArtifacts = persistFetchedArtifacts
            self.localRecallSimilarityThreshold = min(max(localRecallSimilarityThreshold, 0), 1)
            self.maxGroundedFetches = max(1, maxGroundedFetches)
            self.maxEvidenceSections = max(1, maxEvidenceSections)
            self.storeURL = storeURL
            self.storageQuotaBytes = max(1_024_000, storageQuotaBytes)
            self.enabled = enabled
            self.userAgent = userAgent
            self.maxConcurrentFetches = max(1, maxConcurrentFetches)
            self.hostPolitenessDelay = max(0, hostPolitenessDelay)
            self.persistEvidenceBundles = persistEvidenceBundles
        }

        public var hasLiveSearchBackend: Bool {
            if !(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                return true
            }
            return apiKeyReference != nil
        }

        /// Resolves the effective search API key.
        ///
        /// The inline ``apiKey`` wins when non-empty; otherwise
        /// ``apiKeyReference`` is loaded from `store`. Returns `nil` when
        /// neither is available.
        ///
        /// - Parameter store: Backend holding the referenced secret, if any.
        /// - Returns: The effective key, or `nil` when unavailable.
        public func resolveAPIKey(using store: (any SecretStore)?) async throws -> String? {
            let inline = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let inline, !inline.isEmpty {
                return inline
            }
            guard let apiKeyReference, let store else { return nil }
            return try await store.secret(for: apiKeyReference)
        }
    }

    public let name = "websearch"
    public let description = """
    Searches the live web, fetches pages, grounds answers across sources, and reuses cached web evidence \
    without polluting small-context agent prompts.
    """

    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "mode",
            description: "Operation mode: search, fetch, ground, recall, expand, or refresh.",
            type: .oneOf(Mode.allCases.map(\.rawValue)),
            isRequired: false,
            defaultValue: .string(Mode.search.rawValue)
        ),
        ToolParameter(
            name: "query",
            description: "Query for search, ground, or recall.",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "url",
            description: "URL for fetch or refresh.",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "goal",
            description: "Task-specific extraction goal used for section ranking and grounding.",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "maxResults",
            description: "Maximum number of search hits to return.",
            type: .int,
            isRequired: false,
            defaultValue: .int(5)
        ),
        ToolParameter(
            name: "domains",
            description: "Optional domain allowlist.",
            type: .array(elementType: .string),
            isRequired: false
        ),
        ToolParameter(
            name: "recencyDays",
            description: "Optional recency filter in days for live search.",
            type: .int,
            isRequired: false
        ),
        ToolParameter(
            name: "detail",
            description: "How much context to inline: compact, standard, deep, or raw.",
            type: .oneOf(Detail.allCases.map(\.rawValue)),
            isRequired: false,
            defaultValue: .string(Detail.compact.rawValue)
        ),
        ToolParameter(
            name: "preferCached",
            description: "Prefer a close cached artifact before live fetch.",
            type: .bool,
            isRequired: false,
            defaultValue: .bool(true)
        ),
        ToolParameter(
            name: "persist",
            description: "Persist fetched artifacts and evidence bundles.",
            type: .bool,
            isRequired: false,
            defaultValue: .bool(true)
        ),
        ToolParameter(
            name: "artifact_id",
            description: "Artifact identifier for expand.",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "section_ids",
            description: "Section identifiers for expand.",
            type: .array(elementType: .string),
            isRequired: false
        ),
        ToolParameter(
            name: "bundle_id",
            description: "Evidence bundle identifier for expand.",
            type: .string,
            isRequired: false
        ),
        ToolParameter(
            name: "includeRawContent",
            description: "Legacy alias for detail=raw.",
            type: .bool,
            isRequired: false
        ),
    ]

    public var executionSemantics: ToolExecutionSemantics {
        ToolExecutionSemantics(
            sideEffectLevel: .readOnly,
            retryPolicy: .safe,
            approvalRequirement: .automatic,
            resultDurability: .artifactBacked
        )
    }

    public var isEnabled: Bool {
        resolvedConfiguration.enabled
    }

    /// Whether live web search, fetch, and grounding are linked in this build.
    ///
    /// Lean builds still type-check ``WebSearchTool`` so agent graphs compile, but
    /// ``execute()`` throws until you rebuild with `--traits Integrations` (or add
    /// `traits: ["Integrations"]` to the Swarm package dependency).
    public static var isAvailable: Bool {
        IntegrationsTrait.isEnabled
    }

    // Legacy mutable properties preserved for direct-call compatibility.
    public var mode: String
    public var query: String
    public var maxResults: Int
    public var includeRawContent: Bool
    public var url: String
    public var goal: String
    public var detail: String
    public var preferCached: Bool
    public var persist: Bool
    public var artifactID: String
    public var sectionIDs: [String]
    public var bundleID: String
    public var domains: [String]
    public var recencyDays: Int?

    private let configuration: Configuration?
    private let legacyAPIKey: String?
    private let secretStore: (any SecretStore)?

    public init(apiKey: String) {
        IntegrationsTrait.warnIfUnavailable(feature: "Web search")
        configuration = nil
        legacyAPIKey = apiKey
        secretStore = nil
        mode = Mode.search.rawValue
        query = ""
        maxResults = 5
        includeRawContent = false
        url = ""
        goal = ""
        detail = Detail.compact.rawValue
        preferCached = true
        persist = true
        artifactID = ""
        sectionIDs = []
        bundleID = ""
        domains = []
        recencyDays = nil
    }

    public init(configuration: Configuration) {
        IntegrationsTrait.warnIfUnavailable(feature: "Web search")
        self.configuration = configuration
        legacyAPIKey = configuration.apiKey
        secretStore = nil
        mode = Mode.search.rawValue
        query = ""
        maxResults = 5
        includeRawContent = false
        url = ""
        goal = ""
        detail = Detail.compact.rawValue
        preferCached = true
        persist = configuration.persistFetchedArtifacts
        artifactID = ""
        sectionIDs = []
        bundleID = ""
        domains = []
        recencyDays = nil
    }

    /// Creates a tool that resolves `configuration.apiKeyReference` from `secretStore`.
    ///
    /// When the configuration carries an inline key it is used as-is;
    /// otherwise the reference is loaded from the store on every live search.
    /// Use ``KeychainSecretStore`` on Apple platforms so the raw key never
    /// sits in persisted configuration.
    ///
    /// - Parameters:
    ///   - configuration: Search behavior, persistence, and auth pointer.
    ///   - secretStore: Backend holding the referenced secret.
    public init(configuration: Configuration, secretStore: any SecretStore) {
        IntegrationsTrait.warnIfUnavailable(feature: "Web search")
        self.configuration = configuration
        legacyAPIKey = configuration.apiKey
        self.secretStore = secretStore
        mode = Mode.search.rawValue
        query = ""
        maxResults = 5
        includeRawContent = false
        url = ""
        goal = ""
        detail = Detail.compact.rawValue
        preferCached = true
        persist = configuration.persistFetchedArtifacts
        artifactID = ""
        sectionIDs = []
        bundleID = ""
        domains = []
        recencyDays = nil
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        #if SWARM_INTEGRATIONS
        let request = try parseRequest(arguments: arguments)
        let envelope = try await WebToolRuntime.shared.execute(
            request: request,
            configuration: resolvedConfiguration,
            secretStore: secretStore
        )
        return .string(formatLegacy(envelope))
        #else
        throw AgentError.toolFailure(
            toolName: name,
            message: IntegrationsTrait.requirementMessage(for: "Web search"),
            cause: nil
        )
        #endif
    }

    public func execute() async throws -> String {
        #if SWARM_INTEGRATIONS
        let envelope = try await WebToolRuntime.shared.execute(
            request: try legacyRequest(),
            configuration: resolvedConfiguration,
            secretStore: secretStore
        )
        return formatLegacy(envelope)
        #else
        throw AgentError.toolFailure(
            toolName: name,
            message: IntegrationsTrait.requirementMessage(for: "Web search"),
            cause: nil
        )
        #endif
    }

    private var resolvedConfiguration: Configuration {
        if let configuration {
            return configuration
        }
        return Configuration(apiKey: legacyAPIKey)
    }

    #if SWARM_INTEGRATIONS
    private func parseRequest(arguments: [String: SendableValue]) throws -> WebToolRequest {
        let parsedMode = try parseMode(arguments["mode"], fallback: mode)
        let parsedDetail: Detail
        if arguments["includeRawContent"]?.boolValue == true {
            parsedDetail = .raw
        } else {
            parsedDetail = try parseDetail(
                arguments["detail"],
                fallback: includeRawContent ? Detail.raw.rawValue : detail
            )
        }

        return WebToolRequest(
            mode: parsedMode,
            query: arguments["query"]?.stringValue ?? nonEmpty(query),
            url: arguments["url"]?.stringValue ?? nonEmpty(url),
            goal: arguments["goal"]?.stringValue ?? nonEmpty(goal),
            maxResults: max(1, arguments["maxResults"]?.intValue ?? maxResults),
            domains: arguments["domains"]?.arrayValue?.compactMap(\.stringValue) ?? domains,
            recencyDays: arguments["recencyDays"]?.intValue ?? recencyDays,
            detail: parsedDetail,
            preferCached: arguments["preferCached"]?.boolValue ?? preferCached,
            persist: arguments["persist"]?.boolValue ?? persist,
            artifactID: arguments["artifact_id"]?.stringValue ?? nonEmpty(artifactID),
            sectionIDs: arguments["section_ids"]?.arrayValue?.compactMap(\.stringValue) ?? sectionIDs,
            bundleID: arguments["bundle_id"]?.stringValue ?? nonEmpty(bundleID)
        )
    }

    private func legacyRequest() throws -> WebToolRequest {
        let parsedMode = try resolveMode(mode)
        let parsedDetail = try includeRawContent ? Detail.raw : resolveDetail(detail)

        return WebToolRequest(
            mode: parsedMode,
            query: nonEmpty(query),
            url: nonEmpty(url),
            goal: nonEmpty(goal),
            maxResults: max(1, maxResults),
            domains: domains,
            recencyDays: recencyDays,
            detail: parsedDetail,
            preferCached: preferCached,
            persist: persist,
            artifactID: nonEmpty(artifactID),
            sectionIDs: sectionIDs,
            bundleID: nonEmpty(bundleID)
        )
    }

    /// Resolves `mode` from an explicit argument or the legacy property.
    ///
    /// Absent (or blank) values take the documented default; unknown values
    /// throw before any network call is made.
    private func parseMode(_ value: SendableValue?, fallback: String) throws -> Mode {
        guard let value else {
            return try resolveMode(fallback)
        }
        guard let raw = value.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "websearch 'mode' must be a string"
            )
        }
        return try resolveMode(raw)
    }

    private func resolveMode(_ raw: String) throws -> Mode {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .search
        }
        guard let mode = Mode(rawValue: trimmed.lowercased()) else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "unknown websearch mode '\(trimmed)'; expected one of: \(Mode.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return mode
    }

    /// Resolves `detail` from an explicit argument or the legacy property.
    ///
    /// Absent (or blank) values take the documented default; unknown values
    /// throw before any network call is made.
    private func parseDetail(_ value: SendableValue?, fallback: String) throws -> Detail {
        guard let value else {
            return try resolveDetail(fallback)
        }
        guard let raw = value.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "websearch 'detail' must be a string"
            )
        }
        return try resolveDetail(raw)
    }

    private func resolveDetail(_ raw: String) throws -> Detail {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .compact
        }
        guard let detail = Detail(rawValue: trimmed.lowercased()) else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "unknown websearch detail '\(trimmed)'; expected one of: \(Detail.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return detail
    }

    private func formatLegacy(_ envelope: WebSearchEnvelope) -> String {
        var lines: [String] = []
        lines.append(envelope.summary)

        if !envelope.hits.isEmpty {
            lines.append("")
            for (index, hit) in envelope.hits.enumerated() {
                lines.append("\(index + 1). [\(hit.title)](\(hit.url))")
                lines.append("   \(hit.snippet)")
            }
        }

        if !envelope.sectionChunks.isEmpty {
            lines.append("")
            for section in envelope.sectionChunks.prefix(3) {
                lines.append("## \(section.heading)")
                lines.append(section.text)
            }
        }

        return lines.joined(separator: "\n")
    }
    #endif
}

extension WebSearchTool.Configuration: CustomStringConvertible {
    /// Renders the configuration without the API key value.
    ///
    /// Only key presence (already exposed by ``hasLiveSearchBackend``) is
    /// shown, so logging or debugging a configuration cannot leak the key.
    public var description: String {
        "Configuration(apiKey: \(hasLiveSearchBackend ? "<configured>" : "<absent>"), contextProfile: \(contextProfile), summaryMode: \(summaryMode), enabled: \(enabled), storeURL: \(storeURL.path))"
    }
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

extension WebSearchTool.Configuration: CustomDebugStringConvertible {
    /// Debug description with the API key value redacted.
    ///
    /// Reports only key presence plus the non-secret ``SecretReference``
    /// pointer, so debugging a configuration cannot leak the key.
    public var debugDescription: String {
        let key = hasLiveSearchBackend ? "\"\(SecretRedaction.placeholder)\"" : "nil"
        let presence = hasLiveSearchBackend ? "<configured>" : "<absent>"
        return "WebSearchTool.Configuration(apiKey: \(key), presence: \(presence), apiKeyReference: \(String(describing: apiKeyReference)), storeURL: \(storeURL), enabled: \(enabled))"
    }
}

extension WebSearchTool: CustomDebugStringConvertible {
    /// Debug description with API key material redacted.
    public var debugDescription: String {
        let key = legacyAPIKey == nil ? "nil" : "\"\(SecretRedaction.placeholder)\""
        return "WebSearchTool(name: \"\(name)\", mode: \"\(mode)\", maxResults: \(maxResults), legacyAPIKey: \(key), configuration: \(String(reflecting: resolvedConfiguration)))"
    }
}
