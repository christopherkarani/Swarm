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
            !(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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

    public init(apiKey: String) {
        IntegrationsTrait.warnIfUnavailable(feature: "Web search")
        configuration = nil
        legacyAPIKey = apiKey
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
            configuration: resolvedConfiguration
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
            request: legacyRequest(),
            configuration: resolvedConfiguration
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
        let rawMode = arguments["mode"]?.stringValue ?? mode
        let parsedMode = Mode(rawValue: rawMode.lowercased()) ?? .search
        let rawDetail: String
        if arguments["includeRawContent"]?.boolValue == true {
            rawDetail = Detail.raw.rawValue
        } else {
            rawDetail = arguments["detail"]?.stringValue ?? (includeRawContent ? Detail.raw.rawValue : detail)
        }
        let parsedDetail = Detail(rawValue: rawDetail.lowercased()) ?? .compact

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

    private func legacyRequest() -> WebToolRequest {
        let parsedMode = Mode(rawValue: mode.lowercased()) ?? .search
        let parsedDetail = includeRawContent
            ? Detail.raw
            : (Detail(rawValue: detail.lowercased()) ?? .compact)

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

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
