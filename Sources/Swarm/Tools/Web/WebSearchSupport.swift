import Foundation
import Wax

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(SwiftSoup)
import SwiftSoup
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(PDFKit)
import PDFKit
#endif

public enum WebPageType: String, Codable, Sendable, Equatable {
    case docs
    case apiReference
    case blog
    case forum
    case pdf
    case tableHeavy
    case codeHeavy
    case generic
}

public enum WebHostTrustProfile: String, Codable, Sendable, Equatable {
    case officialDocs
    case officialProduct
    case reference
    case community
    case userGenerated
    case unknown
}

public struct WebSearchHit: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var url: String
    public var snippet: String
    public var score: Double
    public var source: String
    public var cached: Bool
    public var artifactID: String?

    public init(
        id: String,
        title: String,
        url: String,
        snippet: String,
        score: Double,
        source: String,
        cached: Bool,
        artifactID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.score = score
        self.source = source
        self.cached = cached
        self.artifactID = artifactID
    }
}

public struct CitationRecord: Codable, Sendable, Equatable {
    public var artifactID: String
    public var sectionID: String
    public var url: String
    public var title: String
    public var snippet: String

    public init(
        artifactID: String,
        sectionID: String,
        url: String,
        title: String,
        snippet: String
    ) {
        self.artifactID = artifactID
        self.sectionID = sectionID
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

public struct WebSectionChunk: Codable, Sendable, Equatable {
    public var id: String
    public var artifactID: String
    public var heading: String
    public var text: String
    public var index: Int
    public var pageType: WebPageType
    public var citations: [CitationRecord]

    public init(
        id: String,
        artifactID: String,
        heading: String,
        text: String,
        index: Int,
        pageType: WebPageType,
        citations: [CitationRecord] = []
    ) {
        self.id = id
        self.artifactID = artifactID
        self.heading = heading
        self.text = text
        self.index = index
        self.pageType = pageType
        self.citations = citations
    }
}

public struct WebArtifactRecord: Codable, Sendable, Equatable {
    public var artifactID: String
    public var canonicalURL: String
    public var title: String
    public var contentType: String
    public var fetchedAt: Date
    public var contentHash: String
    public var etag: String?
    public var lastModified: String?
    public var pageType: WebPageType
    public var hostTrust: WebHostTrustProfile
    public var freshnessScore: Double
    public var rawArtifactRef: String

    public init(
        artifactID: String,
        canonicalURL: String,
        title: String,
        contentType: String,
        fetchedAt: Date,
        contentHash: String,
        etag: String?,
        lastModified: String?,
        pageType: WebPageType,
        hostTrust: WebHostTrustProfile,
        freshnessScore: Double,
        rawArtifactRef: String
    ) {
        self.artifactID = artifactID
        self.canonicalURL = canonicalURL
        self.title = title
        self.contentType = contentType
        self.fetchedAt = fetchedAt
        self.contentHash = contentHash
        self.etag = etag
        self.lastModified = lastModified
        self.pageType = pageType
        self.hostTrust = hostTrust
        self.freshnessScore = freshnessScore
        self.rawArtifactRef = rawArtifactRef
    }
}

public struct NormalizedWebDocument: Codable, Sendable, Equatable {
    public var artifactID: String
    public var canonicalURL: String
    public var title: String
    public var summary: String
    public var pageType: WebPageType
    public var contentType: String
    public var fetchedAt: Date
    public var sections: [WebSectionChunk]

    public init(
        artifactID: String,
        canonicalURL: String,
        title: String,
        summary: String,
        pageType: WebPageType,
        contentType: String,
        fetchedAt: Date,
        sections: [WebSectionChunk]
    ) {
        self.artifactID = artifactID
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
        self.pageType = pageType
        self.contentType = contentType
        self.fetchedAt = fetchedAt
        self.sections = sections
    }
}

public struct GroundedEvidence: Codable, Sendable, Equatable {
    public var query: String
    public var answer: String
    public var evidenceSections: [WebSectionChunk]
    public var citations: [CitationRecord]
    public var bundleID: String?

    public init(
        query: String,
        answer: String,
        evidenceSections: [WebSectionChunk],
        citations: [CitationRecord],
        bundleID: String? = nil
    ) {
        self.query = query
        self.answer = answer
        self.evidenceSections = evidenceSections
        self.citations = citations
        self.bundleID = bundleID
    }
}

public struct EvidenceBundleRecord: Codable, Sendable, Equatable {
    public var bundleID: String
    public var query: String
    public var artifactIDs: [String]
    public var sectionIDs: [String]
    public var summary: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        bundleID: String,
        query: String,
        artifactIDs: [String],
        sectionIDs: [String],
        summary: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.bundleID = bundleID
        self.query = query
        self.artifactIDs = artifactIDs
        self.sectionIDs = sectionIDs
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WebSearchEnvelope: Codable, Sendable, Equatable {
    public var mode: String
    public var summary: String
    public var final4KAnswer: String
    public var semanticCore: String?
    public var hits: [WebSearchHit]
    public var artifact: WebArtifactRecord?
    public var normalizedDocument: NormalizedWebDocument?
    public var sectionChunks: [WebSectionChunk]
    public var groundedEvidence: GroundedEvidence?
    public var citations: [CitationRecord]
    public var artifactRefs: [String]
    public var bundle: EvidenceBundleRecord?
    public var cacheStatus: String
    public var rawArtifactRef: String?

    public init(
        mode: String,
        summary: String,
        final4KAnswer: String,
        semanticCore: String? = nil,
        hits: [WebSearchHit] = [],
        artifact: WebArtifactRecord? = nil,
        normalizedDocument: NormalizedWebDocument? = nil,
        sectionChunks: [WebSectionChunk] = [],
        groundedEvidence: GroundedEvidence? = nil,
        citations: [CitationRecord] = [],
        artifactRefs: [String] = [],
        bundle: EvidenceBundleRecord? = nil,
        cacheStatus: String = "none",
        rawArtifactRef: String? = nil
    ) {
        self.mode = mode
        self.summary = summary
        self.final4KAnswer = final4KAnswer
        self.semanticCore = semanticCore
        self.hits = hits
        self.artifact = artifact
        self.normalizedDocument = normalizedDocument
        self.sectionChunks = sectionChunks
        self.groundedEvidence = groundedEvidence
        self.citations = citations
        self.artifactRefs = artifactRefs
        self.bundle = bundle
        self.cacheStatus = cacheStatus
        self.rawArtifactRef = rawArtifactRef
    }
}

internal struct WebToolRequest: Sendable {
    var mode: WebSearchTool.Mode
    var query: String?
    var url: String?
    var goal: String?
    var maxResults: Int
    var domains: [String]
    var recencyDays: Int?
    var detail: WebSearchTool.Detail
    var preferCached: Bool
    var persist: Bool
    var artifactID: String?
    var sectionIDs: [String]
    var bundleID: String?

    var activeQuery: String {
        let candidates = [goal, query, url].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        return candidates.first ?? ""
    }
}

internal struct WebFetchPayload: Sendable {
    var requestedURL: URL
    var finalURL: URL
    var statusCode: Int
    var contentType: String
    var data: Data
    var etag: String?
    var lastModified: String?
    var notModified: Bool
}

internal struct StoredWebArtifact: Codable, Sendable {
    var artifact: WebArtifactRecord
    var document: NormalizedWebDocument
}

internal actor WebToolRuntime {
    static let shared = WebToolRuntime()

    private var stores: [String: WaxWebArtifactStore] = [:]

    func execute(
        request: WebToolRequest,
        configuration: WebSearchTool.Configuration
    ) async throws -> WebSearchEnvelope {
        let store = try await store(for: configuration)
        let engine = WebExecutionEngine(configuration: configuration, store: store)
        return try await engine.execute(request: request)
    }

    private func store(for configuration: WebSearchTool.Configuration) async throws -> WaxWebArtifactStore {
        let key = configuration.storeURL.path
        if let existing = stores[key] {
            return existing
        }

        let store = try await WaxWebArtifactStore(configuration: configuration)
        stores[key] = store
        return store
    }
}

internal struct WebExecutionEngine: Sendable {
    let configuration: WebSearchTool.Configuration
    let store: WaxWebArtifactStore

    func execute(request: WebToolRequest) async throws -> WebSearchEnvelope {
        switch request.mode {
        case .search:
            return try await search(request: request)
        case .fetch:
            return try await fetch(request: request, forceRefresh: false)
        case .ground:
            return try await ground(request: request)
        case .recall:
            return try await recall(request: request)
        case .expand:
            return try await expand(request: request)
        case .refresh:
            return try await fetch(request: request, forceRefresh: true)
        }
    }

    private func search(request: WebToolRequest) async throws -> WebSearchEnvelope {
        let query = try requireNonEmpty(request.query, field: "query", mode: request.mode)
        let localMatches = try await store.searchSections(
            query: query,
            topK: max(request.maxResults, configuration.maxEvidenceSections)
        )

        let localHits = deduplicateHits(localMatches.map(\.hit))
        let remoteHits: [WebSearchHit] = if await shouldPreferLocalRecall(matches: localMatches, query: query) {
            []
        } else {
            try await liveSearch(query: query, request: request)
        }
        let merged = mergeHits(
            localHits: localHits,
            remoteHits: remoteHits,
            maxResults: request.maxResults,
            query: query
        )
        let answer = merged.isEmpty ? "No web results found." : "Found \(merged.count) ranked results for '\(query)'."

        return boundedEnvelope(
            WebSearchEnvelope(
            mode: request.mode.rawValue,
            summary: answer,
            final4KAnswer: answer,
            semanticCore: merged.prefix(3).map(\.snippet).joined(separator: "\n"),
            hits: merged,
            artifactRefs: merged.compactMap(\.artifactID),
            cacheStatus: localHits.isEmpty ? "network_or_empty" : "mixed"
            ),
            detail: request.detail
        )
    }

    private func fetch(
        request: WebToolRequest,
        forceRefresh: Bool
    ) async throws -> WebSearchEnvelope {
        let urlString = try requireNonEmpty(request.url, field: "url", mode: request.mode)
        let envelope = try await materializeArtifact(
            urlString: urlString,
            goal: request.goal ?? request.query,
            preferCached: request.preferCached && !forceRefresh,
            persist: request.persist,
            forceRefresh: forceRefresh
        )

        return boundedEnvelope(
            shape(
            artifactEnvelope: envelope,
            mode: request.mode,
            detail: request.detail,
            bundle: nil,
            sectionsOverride: request.sectionIDs
            ),
            detail: request.detail
        )
    }

    private func recall(request: WebToolRequest) async throws -> WebSearchEnvelope {
        let query = try requireNonEmpty(request.query ?? request.goal, field: "query", mode: request.mode)
        let matches = try await store.searchSections(query: query, topK: configuration.maxEvidenceSections)
        let sections = matches.map(\.section)
        let citations = sections.flatMap(\.citations)
        let answer = shapeAnswer(for: query, sections: sections, maxSections: configuration.maxEvidenceSections)

        return boundedEnvelope(
            WebSearchEnvelope(
            mode: request.mode.rawValue,
            summary: "Recalled \(sections.count) cached sections for '\(query)'.",
            final4KAnswer: answer,
            semanticCore: sections.prefix(3).map(\.text).joined(separator: "\n"),
            hits: deduplicateHits(matches.map(\.hit)).prefix(request.maxResults).map { $0 },
            sectionChunks: sectionsForDetail(sections, detail: request.detail),
            citations: citations,
            artifactRefs: Array(Set(sections.map(\.artifactID))).sorted(),
            cacheStatus: sections.isEmpty ? "miss" : "hit"
            ),
            detail: request.detail
        )
    }

    private func expand(request: WebToolRequest) async throws -> WebSearchEnvelope {
        if let bundleID = request.bundleID,
           let bundle = try await store.loadBundle(id: bundleID)
        {
            let sections = try await store.sections(
                artifactIDs: bundle.artifactIDs,
                sectionIDs: request.sectionIDs.isEmpty ? bundle.sectionIDs : request.sectionIDs
            )
            let answer = shapeAnswer(for: bundle.query, sections: sections, maxSections: configuration.maxEvidenceSections)
            return boundedEnvelope(
                WebSearchEnvelope(
                mode: request.mode.rawValue,
                summary: "Expanded evidence bundle \(bundleID).",
                final4KAnswer: answer,
                semanticCore: bundle.summary,
                sectionChunks: sectionsForDetail(sections, detail: request.detail),
                citations: sections.flatMap(\.citations),
                artifactRefs: bundle.artifactIDs,
                bundle: bundle,
                cacheStatus: "bundle"
                ),
                detail: request.detail
            )
        }

        guard let artifactID = request.artifactID,
              let stored = try await store.loadArtifact(id: artifactID)
        else {
            throw AgentError.invalidToolArguments(
                toolName: "websearch",
                reason: "expand requires bundle_id or artifact_id"
            )
        }

        return boundedEnvelope(
            shape(
            artifactEnvelope: stored,
            mode: request.mode,
            detail: request.detail,
            bundle: nil,
            sectionsOverride: request.sectionIDs
            ),
            detail: request.detail
        )
    }

    private func ground(request: WebToolRequest) async throws -> WebSearchEnvelope {
        let query = try requireNonEmpty(request.query ?? request.goal, field: "query", mode: request.mode)
        let recallMatches = try await store.searchSections(query: query, topK: configuration.maxEvidenceSections)
        var candidates = deduplicateHits(recallMatches.map(\.hit))
        let preferLocalRecall = await shouldPreferLocalRecall(matches: recallMatches, query: query)

        if candidates.count < configuration.maxGroundedFetches || !preferLocalRecall {
            let live = try await liveSearch(query: query, request: request)
            candidates = mergeHits(
                localHits: candidates,
                remoteHits: live,
                maxResults: configuration.maxGroundedFetches,
                query: query
            )
        }

        var selectedArtifacts: [StoredWebArtifact] = []
        for hit in candidates.prefix(configuration.maxGroundedFetches) {
            if let artifactID = hit.artifactID,
               let cached = try await store.loadArtifact(id: artifactID)
            {
                selectedArtifacts.append(cached)
                continue
            }

            guard !hit.url.isEmpty else { continue }
            do {
                let fetched = try await materializeArtifact(
                    urlString: hit.url,
                    goal: request.goal ?? query,
                    preferCached: request.preferCached,
                    persist: request.persist,
                    forceRefresh: false
                )
                selectedArtifacts.append(fetched)
            } catch {
                Log.agents.debug("Web ground skipped candidate \(hit.url): \(error.localizedDescription)")
            }
        }

        let sections = deduplicateSections(
            selectedArtifacts.flatMap { scoredSections(in: $0.document, query: query, maxCount: 2) }
        )
        let limitedSections = Array(sections.prefix(configuration.maxEvidenceSections))
        let answer = shapeAnswer(for: query, sections: limitedSections, maxSections: configuration.maxEvidenceSections)
        let citations = limitedSections.flatMap(\.citations)

        let bundle: EvidenceBundleRecord? = if configuration.persistEvidenceBundles && request.persist {
            try await store.saveBundle(
                query: query,
                sections: limitedSections,
                summary: answer
            )
        } else {
            nil
        }

        let evidence = GroundedEvidence(
            query: query,
            answer: answer,
            evidenceSections: limitedSections,
            citations: citations,
            bundleID: bundle?.bundleID
        )

        return boundedEnvelope(
            WebSearchEnvelope(
            mode: request.mode.rawValue,
            summary: "Grounded \(limitedSections.count) evidence sections across \(selectedArtifacts.count) page(s).",
            final4KAnswer: answer,
            semanticCore: limitedSections.prefix(3).map { "\($0.heading): \($0.text)" }.joined(separator: "\n"),
            hits: candidates,
            sectionChunks: sectionsForDetail(limitedSections, detail: request.detail),
            groundedEvidence: evidence,
            citations: citations,
            artifactRefs: Array(Set(selectedArtifacts.map(\.artifact.artifactID))).sorted(),
            bundle: bundle,
            cacheStatus: selectedArtifacts.allSatisfy { $0.artifact.freshnessScore >= 0.5 } ? "cache_preferred" : "mixed"
            ),
            detail: request.detail
        )
    }

    private func liveSearch(query: String, request: WebToolRequest) async throws -> [WebSearchHit] {
        guard configuration.hasLiveSearchBackend else {
            Log.agents.warning("[WebSearchTool] liveSearch skipped: no API key configured (hasLiveSearchBackend=false)")
            return []
        }
        Log.agents.info("[WebSearchTool] liveSearch: query='\(query)', maxResults=\(request.maxResults), domains=\(request.domains), recencyDays=\(request.recencyDays ?? -1)")
        let backend = TavilySearchBackend(configuration: configuration)
        let hits = try await backend.search(
            query: query,
            maxResults: request.maxResults,
            domains: request.domains,
            recencyDays: request.recencyDays
        )
        if shouldRefineDocsSearch(query: query, hits: hits, request: request) {
            let refinementDomains = docsRefinementDomains(for: query)
            Log.agents.info("[WebSearchTool] liveSearch refinement: query='\(query)', domains=\(refinementDomains)")
            let refined = try await backend.search(
                query: query,
                maxResults: min(max(request.maxResults, 2), 3),
                domains: refinementDomains,
                recencyDays: request.recencyDays
            )
            let merged = mergeHits(
                localHits: refined,
                remoteHits: hits,
                maxResults: max(request.maxResults, 2),
                query: query
            )
            Log.agents.info("[WebSearchTool] liveSearch refinement returned \(merged.count) merged hits for query: '\(query)'")
            return merged
        }
        Log.agents.info("[WebSearchTool] liveSearch returned \(hits.count) hits for query: '\(query)'")
        return hits
    }

    private func materializeArtifact(
        urlString: String,
        goal: String?,
        preferCached: Bool,
        persist: Bool,
        forceRefresh: Bool
    ) async throws -> StoredWebArtifact {
        let canonicalURL = try canonicalizeURL(urlString)
        let cached = try await store.loadArtifact(canonicalURL: canonicalURL.absoluteString)
        if preferCached,
           let cached,
           !forceRefresh,
           cached.artifact.freshnessScore >= 0.5
        {
            return cached
        }

        let payload = try await SafeWebFetcher(configuration: configuration).fetch(
            url: canonicalURL,
            conditionalEtag: cached?.artifact.etag,
            conditionalLastModified: cached?.artifact.lastModified
        )

        if payload.notModified, let cached {
            let refreshed = try await store.refreshArtifactFreshness(
                artifactID: cached.artifact.artifactID,
                fetchedAt: Date()
            )
            return refreshed ?? cached
        }

        let extracted = try WebContentExtractor().extract(
            payload: payload,
            goal: goal,
            existingArtifactID: cached?.artifact.artifactID,
            rawRootURL: configuration.storeURL.appendingPathComponent("raw", isDirectory: true)
        )

        if !persist {
            return extracted
        }
        return try await store.save(extracted)
    }

    private func shape(
        artifactEnvelope: StoredWebArtifact,
        mode: WebSearchTool.Mode,
        detail: WebSearchTool.Detail,
        bundle: EvidenceBundleRecord?,
        sectionsOverride: [String]
    ) -> WebSearchEnvelope {
        let selectedSections = sectionsOverride.isEmpty
            ? artifactEnvelope.document.sections
            : artifactEnvelope.document.sections.filter { sectionsOverride.contains($0.id) }
        let topSections = Array(selectedSections.prefix(configuration.maxEvidenceSections))
        let answer = shapeAnswer(
            for: artifactEnvelope.document.title,
            sections: topSections,
            maxSections: configuration.maxEvidenceSections
        )

        return WebSearchEnvelope(
            mode: mode.rawValue,
            summary: artifactEnvelope.document.summary,
            final4KAnswer: answer,
            semanticCore: topSections.prefix(3).map(\.text).joined(separator: "\n"),
            hits: [
                WebSearchHit(
                    id: artifactEnvelope.artifact.artifactID,
                    title: artifactEnvelope.artifact.title,
                    url: artifactEnvelope.artifact.canonicalURL,
                    snippet: artifactEnvelope.document.summary,
                    score: artifactEnvelope.artifact.freshnessScore,
                    source: "artifact",
                    cached: true,
                    artifactID: artifactEnvelope.artifact.artifactID
                )
            ],
            artifact: artifactEnvelope.artifact,
            normalizedDocument: detail.includesDocument ? artifactEnvelope.document : nil,
            sectionChunks: sectionsForDetail(topSections, detail: detail),
            citations: topSections.flatMap(\.citations),
            artifactRefs: [artifactEnvelope.artifact.artifactID],
            bundle: bundle,
            cacheStatus: "artifact",
            rawArtifactRef: artifactEnvelope.artifact.rawArtifactRef
        )
    }

    private func sectionsForDetail(_ sections: [WebSectionChunk], detail: WebSearchTool.Detail) -> [WebSectionChunk] {
        switch detail {
        case .compact:
            []
        case .standard:
            Array(sections.prefix(3))
        case .deep, .raw:
            sections
        }
    }

    private func shouldPreferLocalRecall(
        matches: [SectionSearchMatch],
        query: String
    ) async -> Bool {
        guard let best = matches.max(by: { localRecallScore(for: $0, query: query) < localRecallScore(for: $1, query: query) }) else {
            return false
        }

        let representativeHit = best.hit
        let syntheticRequest = WebToolRequest(
            mode: .search,
            query: query,
            url: nil,
            goal: nil,
            maxResults: 1,
            domains: [],
            recencyDays: nil,
            detail: .compact,
            preferCached: true,
            persist: true,
            artifactID: nil,
            sectionIDs: [],
            bundleID: nil
        )
        if localHitNeedsLiveRefresh(representativeHit, query: query, request: syntheticRequest) {
            return false
        }

        guard localRecallScore(for: best, query: query) >= configuration.localRecallSimilarityThreshold else {
            return false
        }

        guard let artifactID = best.hit.artifactID else {
            return false
        }

        return (try? await store.loadArtifact(id: artifactID)?.artifact.freshnessScore) ?? 0 >= 0.5
    }

    private func localRecallScore(
        for match: SectionSearchMatch,
        query: String
    ) -> Double {
        let lexical = sectionRelevanceScore(match.section, query: query)
        let storeScore = min(max(match.hit.score, 0), 1)
        return max(lexical, storeScore)
    }

    private func boundedEnvelope(
        _ envelope: WebSearchEnvelope,
        detail: WebSearchTool.Detail
    ) -> WebSearchEnvelope {
        var bounded = envelope
        let charBudget = max(configuration.contextProfile.maxToolOutputTokens * 4, 512)

        bounded.summary = trimmedSnippet(bounded.summary, limit: min(320, charBudget / 4))
        bounded.final4KAnswer = trimmedSnippet(bounded.final4KAnswer, limit: min(900, charBudget / 2))
        bounded.semanticCore = bounded.semanticCore.map { trimmedSnippet($0, limit: min(700, charBudget / 3)) }
        bounded.hits = bounded.hits
            .prefix(detail == .compact ? min(5, configuration.maxGroundedFetches + 2) : max(5, configuration.maxGroundedFetches))
            .map { hit in
                var copy = hit
                copy.title = trimmedSnippet(copy.title, limit: 120)
                copy.snippet = trimmedSnippet(copy.snippet, limit: detail == .compact ? 160 : 240)
                return copy
            }
        bounded.citations = bounded.citations.prefix(configuration.maxEvidenceSections * 2).map { citation in
            var copy = citation
            copy.title = trimmedSnippet(copy.title, limit: 120)
            copy.snippet = trimmedSnippet(copy.snippet, limit: 180)
            return copy
        }

        let maxSections = switch detail {
        case .compact:
            0
        case .standard:
            min(3, configuration.maxEvidenceSections)
        case .deep, .raw:
            configuration.maxEvidenceSections
        }

        bounded.sectionChunks = boundedSections(
            bounded.sectionChunks,
            limit: maxSections,
            sectionCharacterLimit: max(200, min(700, charBudget / max(1, maxSections + 1)))
        )

        if var document = bounded.normalizedDocument {
            document.summary = trimmedSnippet(document.summary, limit: min(320, charBudget / 4))
            document.sections = boundedSections(
                document.sections,
                limit: maxSections,
                sectionCharacterLimit: max(200, min(700, charBudget / max(1, maxSections + 1)))
            )
            bounded.normalizedDocument = detail.includesDocument ? document : nil
        }

        if var evidence = bounded.groundedEvidence {
            evidence.answer = trimmedSnippet(evidence.answer, limit: min(900, charBudget / 2))
            evidence.evidenceSections = boundedSections(
                evidence.evidenceSections,
                limit: maxSections,
                sectionCharacterLimit: max(200, min(700, charBudget / max(1, maxSections + 1)))
            )
            evidence.citations = bounded.citations
            bounded.groundedEvidence = evidence
        }

        if var artifact = bounded.artifact {
            artifact.title = trimmedSnippet(artifact.title, limit: 120)
            bounded.artifact = artifact
        }

        if var bundle = bounded.bundle {
            bundle.summary = trimmedSnippet(bundle.summary, limit: min(500, charBudget / 3))
            bounded.bundle = bundle
        }

        return bounded
    }

    private func boundedSections(
        _ sections: [WebSectionChunk],
        limit: Int,
        sectionCharacterLimit: Int
    ) -> [WebSectionChunk] {
        sections.prefix(limit).map { section in
            var copy = section
            copy.heading = trimmedSnippet(copy.heading, limit: 120)
            copy.text = trimmedSnippet(copy.text, limit: sectionCharacterLimit)
            copy.citations = copy.citations.prefix(2).map { citation in
                var citationCopy = citation
                citationCopy.title = trimmedSnippet(citationCopy.title, limit: 120)
                citationCopy.snippet = trimmedSnippet(citationCopy.snippet, limit: 180)
                return citationCopy
            }
            return copy
        }
    }

    private func requireNonEmpty(
        _ value: String?,
        field: String,
        mode: WebSearchTool.Mode
    ) throws -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw AgentError.invalidToolArguments(
                toolName: "websearch",
                reason: "mode '\(mode.rawValue)' requires non-empty \(field)"
            )
        }
        return trimmed
    }
}

internal actor WaxWebArtifactStore {
    private let configuration: WebSearchTool.Configuration
    private let rootURL: URL
    private let manifestsURL: URL
    private let rawURL: URL
    private let bundlesURL: URL
    private let indexURL: URL
    private var memory: Wax.Memory
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: WebSearchTool.Configuration) async throws {
        self.configuration = configuration
        rootURL = configuration.storeURL
        manifestsURL = rootURL.appendingPathComponent("artifacts", isDirectory: true)
        rawURL = rootURL.appendingPathComponent("raw", isDirectory: true)
        bundlesURL = rootURL.appendingPathComponent("bundles", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("web-index.wax")

        try FileManager.default.createDirectory(at: manifestsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundlesURL, withIntermediateDirectories: true)

        var waxConfig = Wax.Memory.Config.default
        waxConfig.enableVectorSearch = false
        memory = try await Wax.Memory(at: indexURL, config: waxConfig)
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func save(_ artifact: StoredWebArtifact) async throws -> StoredWebArtifact {
        try await enforceQuotaIfNeeded()

        let manifestURL = manifestsURL.appendingPathComponent("\(artifact.artifact.artifactID).json")
        let rawURL = URL(fileURLWithPath: artifact.artifact.rawArtifactRef)
        let data = try encoder.encode(artifact)
        try data.write(to: manifestURL, options: .atomic)
        try await rebuildIndex()

        if !FileManager.default.fileExists(atPath: rawURL.path) {
            Log.agents.warning("Expected raw artifact is missing at \(rawURL.path)")
        }
        return artifact
    }

    func loadArtifact(id: String) throws -> StoredWebArtifact? {
        let url = manifestsURL.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(StoredWebArtifact.self, from: Data(contentsOf: url))
    }

    func loadArtifact(canonicalURL: String) throws -> StoredWebArtifact? {
        let urls = try FileManager.default.contentsOfDirectory(
            at: manifestsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls {
            let artifact = try decoder.decode(StoredWebArtifact.self, from: Data(contentsOf: url))
            if artifact.artifact.canonicalURL == canonicalURL {
                return artifact
            }
        }
        return nil
    }

    func refreshArtifactFreshness(
        artifactID: String,
        fetchedAt: Date
    ) throws -> StoredWebArtifact? {
        guard var artifact = try loadArtifact(id: artifactID) else { return nil }
        artifact.artifact.fetchedAt = fetchedAt
        artifact.artifact.freshnessScore = Self.freshnessScore(
            fetchedAt: fetchedAt,
            pageType: artifact.artifact.pageType
        )
        artifact.document.fetchedAt = fetchedAt
        return try saveLocally(artifact)
    }

    func searchSections(query: String, topK: Int) async throws -> [SectionSearchMatch] {
        let results = try await memory.search(
            query,
            options: .init(topK: max(topK * 4, topK), includeSurrogates: false, mode: .textOnly)
        )

        var matches: [SectionSearchMatch] = []
        var seenSectionKeys: Set<String> = []
        for item in results.items {
            guard let indexed = parseIndexedSectionText(item.text),
                  let artifactID = indexed.artifactID,
                  let sectionID = indexed.sectionID,
                  let artifact = try loadArtifact(id: artifactID),
                  let section = artifact.document.sections.first(where: { $0.id == sectionID })
            else {
                continue
            }
            let sectionKey = "\(artifactID)::\(sectionID)"
            guard seenSectionKeys.insert(sectionKey).inserted else { continue }

            let hit = WebSearchHit(
                id: artifactID,
                title: artifact.artifact.title,
                url: artifact.artifact.canonicalURL,
                snippet: artifact.document.summary,
                score: Double(item.score),
                source: "wax",
                cached: true,
                artifactID: artifactID
            )
            matches.append(SectionSearchMatch(hit: hit, section: section))
            if matches.count == topK {
                break
            }
        }
        return matches
    }

    func sections(artifactIDs: [String], sectionIDs: [String]) throws -> [WebSectionChunk] {
        var chunks: [WebSectionChunk] = []
        for artifactID in artifactIDs {
            guard let artifact = try loadArtifact(id: artifactID) else { continue }
            let selected = artifact.document.sections.filter { sectionIDs.isEmpty || sectionIDs.contains($0.id) }
            chunks.append(contentsOf: selected)
        }
        return chunks.sorted { lhs, rhs in
            if lhs.artifactID == rhs.artifactID {
                return lhs.index < rhs.index
            }
            return lhs.artifactID < rhs.artifactID
        }
    }

    func saveBundle(
        query: String,
        sections: [WebSectionChunk],
        summary: String
    ) throws -> EvidenceBundleRecord {
        let now = Date()
        let bundle = EvidenceBundleRecord(
            bundleID: UUID().uuidString,
            query: query,
            artifactIDs: Array(Set(sections.map(\.artifactID))).sorted(),
            sectionIDs: sections.map(\.id),
            summary: summary,
            createdAt: now,
            updatedAt: now
        )
        let url = bundlesURL.appendingPathComponent("\(bundle.bundleID).json")
        try encoder.encode(bundle).write(to: url, options: .atomic)
        return bundle
    }

    func loadBundle(id: String) throws -> EvidenceBundleRecord? {
        let url = bundlesURL.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(EvidenceBundleRecord.self, from: Data(contentsOf: url))
    }

    private func saveLocally(_ artifact: StoredWebArtifact) throws -> StoredWebArtifact {
        let manifestURL = manifestsURL.appendingPathComponent("\(artifact.artifact.artifactID).json")
        try encoder.encode(artifact).write(to: manifestURL, options: .atomic)
        return artifact
    }

    private func enforceQuotaIfNeeded() async throws {
        guard configuration.storageQuotaBytes > 0 else { return }
        let manifests = try FileManager.default.contentsOfDirectory(
            at: manifestsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        struct ArtifactDiskRecord {
            let artifactID: String
            let manifestURL: URL
            let rawURL: URL?
            let bundleSize: Int
            let modifiedAt: Date
        }

        var diskRecords: [ArtifactDiskRecord] = []
        var totalBytes = try directorySize(at: manifestsURL) + directorySize(at: rawURL) + directorySize(at: bundlesURL)

        guard totalBytes > configuration.storageQuotaBytes else { return }
        var evictedArtifacts = false

        for manifestURL in manifests {
            guard manifestURL.pathExtension == "json" else { continue }
            guard let stored = try? decoder.decode(StoredWebArtifact.self, from: Data(contentsOf: manifestURL)) else { continue }
            let values = try manifestURL.resourceValues(forKeys: [.contentModificationDateKey])
            diskRecords.append(
                ArtifactDiskRecord(
                    artifactID: stored.artifact.artifactID,
                    manifestURL: manifestURL,
                    rawURL: URL(fileURLWithPath: stored.artifact.rawArtifactRef),
                    bundleSize: 0,
                    modifiedAt: values.contentModificationDate ?? stored.artifact.fetchedAt
                )
            )
        }

        for record in diskRecords.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            let reclaimed = try fileSize(at: record.manifestURL) + fileSize(at: record.rawURL)
            try? FileManager.default.removeItem(at: record.manifestURL)
            if let rawURL = record.rawURL, FileManager.default.fileExists(atPath: rawURL.path) {
                try? FileManager.default.removeItem(at: rawURL)
            }
            totalBytes -= reclaimed
            evictedArtifacts = true
            if totalBytes <= configuration.storageQuotaBytes {
                break
            }
        }

        if totalBytes > configuration.storageQuotaBytes {
            let bundles = try FileManager.default.contentsOfDirectory(
                at: bundlesURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            for bundleURL in bundles.sorted(by: {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs < rhs
            }) {
                let reclaimed = try fileSize(at: bundleURL)
                try? FileManager.default.removeItem(at: bundleURL)
                totalBytes -= reclaimed
                if totalBytes <= configuration.storageQuotaBytes {
                    break
                }
            }
        }

        if evictedArtifacts {
            try await rebuildIndex()
        }
    }

    private func rebuildIndex() async throws {
        try await memory.close()
        try? FileManager.default.removeItem(at: indexURL)

        var waxConfig = Wax.Memory.Config.default
        waxConfig.enableVectorSearch = false
        memory = try await Wax.Memory(at: indexURL, config: waxConfig)

        let manifests = try FileManager.default.contentsOfDirectory(
            at: manifestsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for manifestURL in manifests.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard manifestURL.pathExtension == "json" else { continue }
            let artifact = try decoder.decode(StoredWebArtifact.self, from: Data(contentsOf: manifestURL))
            for section in artifact.document.sections {
                try await memory.save(indexedSectionText(for: section, artifact: artifact))
            }
        }

        try await memory.flush()
    }

    private func indexedSectionText(
        for section: WebSectionChunk,
        artifact: StoredWebArtifact
    ) -> String {
        let safeHeading = section.heading.replacingOccurrences(of: "]]", with: "")
        let lines = [
            "[[artifact_id:\(artifact.artifact.artifactID)]]",
            "[[section_id:\(section.id)]]",
            "[[section_heading:\(safeHeading)]]",
            section.heading,
            section.text,
        ]
        return lines.joined(separator: "\n")
    }

    private func parseIndexedSectionText(_ text: String) -> (artifactID: String?, sectionID: String?)? {
        var artifactID: String?
        var sectionID: String?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(4) {
            let value = String(line)
            if value.hasPrefix("[[artifact_id:"), value.hasSuffix("]]") {
                artifactID = String(value.dropFirst(14).dropLast(2))
            } else if value.hasPrefix("[[section_id:"), value.hasSuffix("]]") {
                sectionID = String(value.dropFirst(13).dropLast(2))
            }
        }

        if artifactID == nil, sectionID == nil {
            return nil
        }
        return (artifactID, sectionID)
    }

    private func directorySize(at url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            total += try fileSize(at: fileURL)
        }
        return total
    }

    private func fileSize(at url: URL?) throws -> Int {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { return 0 }
        return values.fileSize ?? 0
    }

    static func freshnessScore(fetchedAt: Date, pageType: WebPageType) -> Double {
        let staleDays: Double = switch pageType {
        case .docs, .apiReference:
            7
        case .blog, .generic, .tableHeavy, .codeHeavy:
            3
        case .forum:
            1
        case .pdf:
            7
        }

        let ageDays = Date().timeIntervalSince(fetchedAt) / 86_400
        let raw = max(0, 1 - (ageDays / max(1, staleDays)))
        return min(raw, 1)
    }
}

internal struct SectionSearchMatch: Sendable {
    var hit: WebSearchHit
    var section: WebSectionChunk
}

internal struct TavilySearchBackend: Sendable {
    let configuration: WebSearchTool.Configuration

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let title: String
        let url: String
        let content: String
        let score: Double
    }

    func search(
        query: String,
        maxResults: Int,
        domains: [String],
        recencyDays: Int?
    ) async throws -> [WebSearchHit] {
        guard let apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            Log.agents.warning("[TavilySearchBackend] API key is empty — returning 0 hits")
            return []
        }

        Log.agents.info("[TavilySearchBackend] POST api.tavily.com/search — query='\(query)', maxResults=\(maxResults)")

        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw AgentError.toolExecutionFailed(toolName: "websearch", underlyingError: "Invalid Tavily URL")
        }

        var body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": max(1, maxResults),
            "search_depth": "advanced",
            "include_raw_content": false,
        ]
        if !domains.isEmpty {
            body["include_domains"] = domains
        }
        if let recencyDays {
            body["days"] = recencyDays
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = min(configuration.fetchTimeout, 6)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = Self.makeSession(timeout: min(configuration.fetchTimeout, 6))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.toolExecutionFailed(toolName: "websearch", underlyingError: "Tavily returned a non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "(no body)"
            Log.agents.error("[TavilySearchBackend] HTTP \(http.statusCode) — \(errorBody)")
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Tavily request failed (HTTP \(http.statusCode)): \(errorBody)"
            )
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        Log.agents.info("[TavilySearchBackend] Decoded \(decoded.results.count) results from Tavily")
        return decoded.results.enumerated().map { index, result in
            WebSearchHit(
                id: "tavily-\(index)-\(abs(result.url.hashValue))",
                title: result.title,
                url: result.url,
                snippet: trimmedSnippet(result.content),
                score: result.score,
                source: "tavily",
                cached: false
            )
        }
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }
}

internal struct SafeWebFetcher: Sendable {
    let configuration: WebSearchTool.Configuration

    func fetch(
        url: URL,
        conditionalEtag: String?,
        conditionalLastModified: String?
    ) async throws -> WebFetchPayload {
        try validate(url: url)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.fetchTimeout
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        if let conditionalEtag, !conditionalEtag.isEmpty {
            request.setValue(conditionalEtag, forHTTPHeaderField: "If-None-Match")
        }
        if let conditionalLastModified, !conditionalLastModified.isEmpty {
            request.setValue(conditionalLastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.toolExecutionFailed(toolName: "websearch", underlyingError: "Fetch returned a non-HTTP response")
        }

        if http.statusCode == 304 {
            return WebFetchPayload(
                requestedURL: url,
                finalURL: http.url ?? url,
                statusCode: http.statusCode,
                contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
                data: Data(),
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                notModified: true
            )
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Fetch failed for \(url.absoluteString) (HTTP \(http.statusCode))"
            )
        }

        guard data.count <= configuration.maxBodyBytes else {
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Fetched body exceeded limit of \(configuration.maxBodyBytes) bytes"
            )
        }

        return WebFetchPayload(
            requestedURL: url,
            finalURL: http.url ?? url,
            statusCode: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream",
            data: data,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            notModified: false
        )
    }

    private func validate(url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Only http/https URLs are allowed")
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "URL must include a valid host")
        }

        if host == "localhost" || host == "::1" || host == "[::1]" || host.hasPrefix("127.") {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Loopback hosts are blocked")
        }

        if host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") {
            throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Private-network hosts are blocked")
        }

        if host.hasPrefix("172.") {
            let octets = host.split(separator: ".")
            if octets.count >= 2, let second = Int(octets[1]), (16 ... 31).contains(second) {
                throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Private-network hosts are blocked")
            }
        }
    }
}

internal struct WebContentExtractor: Sendable {
    func extract(
        payload: WebFetchPayload,
        goal: String?,
        existingArtifactID: String?,
        rawRootURL: URL
    ) throws -> StoredWebArtifact {
        let finalURL = try canonicalizeURL(payload.finalURL.absoluteString)
        let pageType = classify(payload: payload, url: finalURL)
        let title: String
        let summary: String
        let sections: [WebSectionChunk]

        switch pageType {
        case .pdf:
            let pdfText = extractPDFText(from: payload.data)
            title = finalURL.lastPathComponent.isEmpty ? finalURL.host ?? finalURL.absoluteString : finalURL.lastPathComponent
            sections = sectionizeText(
                pdfText ?? "PDF fetched successfully. Text extraction unavailable on this platform.",
                artifactID: existingArtifactID ?? UUID().uuidString,
                pageType: .pdf,
                url: finalURL.absoluteString,
                title: title
            )
            summary = summarizeSections(sections, goal: goal)
        default:
            let htmlOrText = decodeText(payload.data)
            if payload.contentType.contains("text/html") || htmlOrText.contains("<html") {
                let html = HTMLDocumentParser.parse(htmlOrText, url: finalURL)
                title = html.title
                sections = html.sections.enumerated().map { index, section in
                    let artifactID = existingArtifactID ?? UUID().uuidString
                    return WebSectionChunk(
                        id: "\(artifactID)-section-\(index)",
                        artifactID: artifactID,
                        heading: section.heading,
                        text: section.text,
                        index: index,
                        pageType: pageType,
                        citations: [
                            CitationRecord(
                                artifactID: artifactID,
                                sectionID: "\(artifactID)-section-\(index)",
                                url: html.canonicalURL ?? finalURL.absoluteString,
                                title: html.title,
                                snippet: trimmedSnippet(section.text, limit: 240)
                            )
                        ]
                    )
                }
                summary = summarizeSections(sections, goal: goal, fallback: html.description)
            } else if payload.contentType.contains("json") {
                let pretty = prettifyJSON(payload.data)
                title = finalURL.lastPathComponent.isEmpty ? "JSON" : finalURL.lastPathComponent
                sections = sectionizeText(pretty, artifactID: existingArtifactID ?? UUID().uuidString, pageType: pageType, url: finalURL.absoluteString, title: title)
                summary = summarizeSections(sections, goal: goal)
            } else {
                title = finalURL.lastPathComponent.isEmpty ? finalURL.absoluteString : finalURL.lastPathComponent
                sections = sectionizeText(htmlOrText, artifactID: existingArtifactID ?? UUID().uuidString, pageType: pageType, url: finalURL.absoluteString, title: title)
                summary = summarizeSections(sections, goal: goal)
            }
        }

        let artifactID = sections.first?.artifactID ?? existingArtifactID ?? UUID().uuidString
        let hostTrust = hostTrustProfile(for: finalURL)
        let fetchedAt = Date()
        let rawFileURL = rawFileURL(rootURL: rawRootURL, artifactID: artifactID, contentType: payload.contentType)
        try payload.data.write(to: rawFileURL, options: .atomic)

        let normalizedSections = sections.enumerated().map { index, section in
            var copy = section
            copy.id = "\(artifactID)-section-\(index)"
            copy.artifactID = artifactID
            copy.index = index
            copy.citations = [
                CitationRecord(
                    artifactID: artifactID,
                    sectionID: copy.id,
                    url: finalURL.absoluteString,
                    title: title,
                    snippet: trimmedSnippet(copy.text, limit: 240)
                )
            ]
            return copy
        }

        let contentHash = sha256Hex(payload.data)
        let document = NormalizedWebDocument(
            artifactID: artifactID,
            canonicalURL: finalURL.absoluteString,
            title: title,
            summary: summary,
            pageType: pageType,
            contentType: payload.contentType,
            fetchedAt: fetchedAt,
            sections: normalizedSections
        )
        let artifact = WebArtifactRecord(
            artifactID: artifactID,
            canonicalURL: finalURL.absoluteString,
            title: title,
            contentType: payload.contentType,
            fetchedAt: fetchedAt,
            contentHash: contentHash,
            etag: payload.etag,
            lastModified: payload.lastModified,
            pageType: pageType,
            hostTrust: hostTrust,
            freshnessScore: WaxWebArtifactStore.freshnessScore(fetchedAt: fetchedAt, pageType: pageType),
            rawArtifactRef: rawFileURL.path
        )
        return StoredWebArtifact(artifact: artifact, document: document)
    }

    private func extractPDFText(from data: Data) -> String? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data) else { return nil }
        return (0 ..< document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
        #else
        return nil
        #endif
    }

    private func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func classify(payload: WebFetchPayload, url: URL) -> WebPageType {
        let contentType = payload.contentType.lowercased()
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""
        let body = decodeText(payload.data).lowercased()

        if contentType.contains("pdf") || path.hasSuffix(".pdf") {
            return .pdf
        }
        if host.contains("reddit.") || host.contains("stackoverflow.") || host.contains("forum") || host.contains("discuss") || host.contains("community") {
            return .forum
        }
        if path.contains("/api") || path.contains("reference") || body.contains("parameters") && body.contains("returns") {
            return .apiReference
        }
        if host.contains("docs.") || path.contains("/docs") {
            return .docs
        }
        if path.contains("/blog") || path.contains("/news") || path.contains("/posts") {
            return .blog
        }
        if body.contains("<table") {
            return .tableHeavy
        }
        if body.contains("<pre") || body.contains("<code") {
            return .codeHeavy
        }
        return .generic
    }
}

internal struct HTMLDocumentParser {
    struct Section: Sendable {
        var heading: String
        var text: String
    }

    struct ParsedDocument: Sendable {
        var title: String
        var description: String?
        var canonicalURL: String?
        var sections: [Section]
    }

    static func parse(_ html: String, url: URL) -> ParsedDocument {
        #if canImport(SwiftSoup)
        if let parsed = parseWithSwiftSoup(html, url: url) {
            return parsed
        }
        #endif

        let sanitized = strip(html: html, tags: ["script", "style", "nav", "footer", "header", "aside", "noscript", "svg", "form"])
        let canonicalURL = attribute(
            named: "href",
            inFirstTagMatching: "<link[^>]*rel=[\"']canonical[\"'][^>]*>",
            html: sanitized
        )
        let title = (firstCapture(in: sanitized, pattern: "(?is)<title[^>]*>(.*?)</title>")
            .flatMap(htmlToText)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty)
            ?? (url.host ?? url.absoluteString)
        let description = firstCapture(
            in: sanitized,
            pattern: "(?is)<meta[^>]*name=[\"']description[\"'][^>]*content=[\"'](.*?)[\"'][^>]*>"
        )

        let blockPattern = "(?is)<(h[1-6]|p|pre|code|li|tr|td|th)[^>]*>(.*?)</\\1>"
        let regex = try? NSRegularExpression(pattern: blockPattern)
        let nsRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        let matches = regex?.matches(in: sanitized, range: nsRange) ?? []

        var sections: [Section] = []
        var currentHeading = title
        var buffer: [String] = []

        func flush() {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            sections.append(Section(heading: currentHeading, text: text))
            buffer.removeAll(keepingCapacity: true)
        }

        for match in matches {
            guard
                let tagRange = Range(match.range(at: 1), in: sanitized),
                let contentRange = Range(match.range(at: 2), in: sanitized)
            else { continue }

            let tag = String(sanitized[tagRange]).lowercased()
            let content = htmlToText(String(sanitized[contentRange]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else { continue }

            if tag.hasPrefix("h") {
                flush()
                currentHeading = content
            } else {
                buffer.append(content)
            }
        }
        flush()

        if sections.isEmpty {
            let plain = htmlToText(sanitized)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !plain.isEmpty {
                sections = [Section(heading: title, text: plain)]
            }
        }

        return ParsedDocument(title: title, description: description, canonicalURL: canonicalURL, sections: sections)
    }

    #if canImport(SwiftSoup)
    private static func parseWithSwiftSoup(_ html: String, url: URL) -> ParsedDocument? {
        do {
            let document = try SwiftSoup.parse(html, url.absoluteString)
            try document.select("script, style, nav, footer, header, aside, noscript, svg, form").remove()

            let canonical = try document.select("link[rel=canonical]").first()?.attr("href")
            let title = try document.title().trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? url.host
                ?? url.absoluteString
            let description = try document.select("meta[name=description]").first()?.attr("content").nonEmpty

            let root = try document.select("article, main").first() ?? document.body()
            let blocks = try root?.select("h1, h2, h3, h4, h5, h6, p, pre, code, li, tr, td, th").array() ?? []

            var sections: [Section] = []
            var currentHeading = title
            var buffer: [String] = []

            func flush() {
                let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                sections.append(Section(heading: currentHeading, text: text))
                buffer.removeAll(keepingCapacity: true)
            }

            for block in blocks {
                let tag = block.tagName().lowercased()
                let text = try block.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                if tag.hasPrefix("h") {
                    flush()
                    currentHeading = text
                } else {
                    buffer.append(text)
                }
            }
            flush()

            if sections.isEmpty {
                let plain = try root?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !plain.isEmpty {
                    sections = [Section(heading: title, text: plain)]
                }
            }

            return ParsedDocument(title: title, description: description, canonicalURL: canonical, sections: sections)
        } catch {
            return nil
        }
    }
    #endif

    private static func strip(html: String, tags: [String]) -> String {
        tags.reduce(html) { partial, tag in
            partial.replacingOccurrences(
                of: "(?is)<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: .regularExpression
            )
        }
    }
}

internal func htmlToText(_ html: String) -> String? {
    let normalized = html
        .replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    let collapsed = normalized.replacingOccurrences(of: "[ \\t\\r\\f\\v]+", with: " ", options: .regularExpression)
    return collapsed.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
}

internal func firstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
          let range = Range(match.range(at: 1), in: text)
    else {
        return nil
    }
    return String(text[range])
}

internal func attribute(named attribute: String, inFirstTagMatching pattern: String, html: String) -> String? {
    guard let tag = firstCapture(in: html, pattern: "(?is)(\(pattern))") else { return nil }
    return firstCapture(in: tag, pattern: "(?is)\(attribute)=[\"'](.*?)[\"']")
}

internal func sectionizeText(
    _ text: String,
    artifactID: String,
    pageType: WebPageType,
    url: String,
    title: String
) -> [WebSectionChunk] {
    let blocks = text
        .replacingOccurrences(of: "\n\\s*\n", with: "\n\n", options: .regularExpression)
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if blocks.isEmpty {
        return [
            WebSectionChunk(
                id: "\(artifactID)-section-0",
                artifactID: artifactID,
                heading: title,
                text: trimmedSnippet(text, limit: 800),
                index: 0,
                pageType: pageType,
                citations: [
                    CitationRecord(
                        artifactID: artifactID,
                        sectionID: "\(artifactID)-section-0",
                        url: url,
                        title: title,
                        snippet: trimmedSnippet(text, limit: 240)
                    )
                ]
            )
        ]
    }

    return blocks.enumerated().map { index, block in
        let heading = firstMeaningfulLine(in: block) ?? title
        return WebSectionChunk(
            id: "\(artifactID)-section-\(index)",
            artifactID: artifactID,
            heading: heading,
            text: block,
            index: index,
            pageType: pageType,
            citations: [
                CitationRecord(
                    artifactID: artifactID,
                    sectionID: "\(artifactID)-section-\(index)",
                    url: url,
                    title: title,
                    snippet: trimmedSnippet(block, limit: 240)
                )
            ]
        )
    }
}

internal func summarizeSections(
    _ sections: [WebSectionChunk],
    goal: String?,
    fallback: String? = nil
) -> String {
    let selected = sections
        .sorted { lhs, rhs in
            sectionRelevanceScore(lhs, query: goal ?? "") > sectionRelevanceScore(rhs, query: goal ?? "")
        }
        .prefix(2)
    let joined = selected.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = joined.isEmpty ? (fallback ?? "") : joined
    return trimmedSnippet(candidate, limit: 320)
}

internal func shapeAnswer(
    for query: String,
    sections: [WebSectionChunk],
    maxSections: Int
) -> String {
    guard !sections.isEmpty else {
        return "No grounded evidence is currently cached for '\(query)'."
    }

    let selected = sections.prefix(maxSections).map { section in
        let lead = section.heading == query ? section.text : "\(section.heading): \(section.text)"
        return trimmedSnippet(lead, limit: 220)
    }
    return selected.joined(separator: "\n")
}

internal func sectionRelevanceScore(_ section: WebSectionChunk, query: String) -> Double {
    let haystack = "\(section.heading) \(section.text)".lowercased()
    let tokens = query
        .lowercased()
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { $0.count >= 3 }
    guard !tokens.isEmpty else { return Double(section.text.count) / 1_000.0 }
    let hits = tokens.reduce(into: 0) { partial, token in
        if haystack.contains(token) {
            partial += 1
        }
    }
    return Double(hits) / Double(tokens.count)
}

internal func scoredSections(
    in document: NormalizedWebDocument,
    query: String,
    maxCount: Int
) -> [WebSectionChunk] {
    document.sections
        .sorted { sectionRelevanceScore($0, query: query) > sectionRelevanceScore($1, query: query) }
        .prefix(maxCount)
        .map { $0 }
}

internal func deduplicateSections(_ sections: [WebSectionChunk]) -> [WebSectionChunk] {
    var seen: Set<String> = []
    var deduped: [WebSectionChunk] = []
    for section in sections {
        let key = normalizedDedupKey(section.text)
        guard seen.insert(key).inserted else { continue }
        deduped.append(section)
    }
    return deduped
}

internal func deduplicateHits(_ hits: [WebSearchHit]) -> [WebSearchHit] {
    var seen: Set<String> = []
    var deduped: [WebSearchHit] = []
    for hit in hits.sorted(by: { $0.score > $1.score }) {
        let key = normalizedDedupKey(hit.url)
        guard seen.insert(key).inserted else { continue }
        deduped.append(hit)
    }
    return deduped
}

internal func mergeHits(
    localHits: [WebSearchHit],
    remoteHits: [WebSearchHit],
    maxResults: Int,
    query: String
) -> [WebSearchHit] {
    let ranked = deduplicateHits(localHits + remoteHits)
        .map { hit in
            (
                hit,
                compositeHitScore(hit, query: query)
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.score > rhs.0.score
            }
            return lhs.1 > rhs.1
        }
        .map(\.0)

    return diversifyHits(ranked, query: query, maxResults: maxResults)
}

internal func compositeHitScore(_ hit: WebSearchHit, query: String) -> Double {
    let base = hit.score * 0.45
    let queryScore = hitQueryMatchScore(hit, query: query) * 0.45
    let trust = hostTrustWeight(for: hit.url) * 0.1
    let cacheBoost = hit.cached ? 0.05 : 0
    let genericPenalty = genericHitPenalty(hit, query: query)
    let intentBoost = queryIntentPreferenceScore(hit, query: query)
    return base + queryScore + trust + cacheBoost + intentBoost - genericPenalty
}

internal func hitQueryMatchScore(_ hit: WebSearchHit, query: String) -> Double {
    let tokens = query
        .lowercased()
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { $0.count >= 3 }

    guard !tokens.isEmpty else {
        return 0
    }

    let title = hit.title.lowercased()
    let snippet = hit.snippet.lowercased()
    let url = hit.url.lowercased()
    var matches = 0.0
    for token in tokens {
        if title.contains(token) { matches += 0.55 }
        if snippet.contains(token) { matches += 0.30 }
        if url.contains(token) { matches += 0.15 }
    }

    let exactPhraseBonus = title.contains(query.lowercased())
        || snippet.contains(query.lowercased())
        || url.contains(query.lowercased()) ? 0.25 : 0
    return min((matches / Double(tokens.count)) + exactPhraseBonus, 1.6)
}

internal func genericHitPenalty(_ hit: WebSearchHit, query: String) -> Double {
    let loweredURL = hit.url.lowercased()
    let loweredTitle = hit.title.lowercased()
    let loweredQuery = query.lowercased()
    let genericMarkers = [
        "/whats-new",
        "/news",
        "/blog",
        "what’s new",
        "what's new",
        "release notes",
    ]

    let isGeneric = genericMarkers.contains(where: { loweredURL.contains($0) || loweredTitle.contains($0) })
    guard isGeneric else {
        return 0
    }
    let queryTokens = loweredQuery
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { $0.count >= 4 }
    let distinctMatches = Set(queryTokens.filter { token in
        loweredTitle.contains(token) || loweredURL.contains(token)
    }).count

    if distinctMatches >= min(3, queryTokens.count) {
        return 0.08
    }

    if distinctMatches >= 1 {
        return 0.22
    }

    return 0.38
}

internal func diversifyHits(_ hits: [WebSearchHit], query: String, maxResults: Int) -> [WebSearchHit] {
    var selected: [WebSearchHit] = []
    var seenDomains: [String: Int] = [:]

    for hit in hits {
        let domain = hit.urlDomain
        let duplicateCount = seenDomains[domain, default: 0]
        if duplicateCount > 0, selected.count >= 2 {
            let currentMatch = hitQueryMatchScore(hit, query: query)
            let bestForDomain = selected
                .filter { $0.urlDomain == domain }
                .map { hitQueryMatchScore($0, query: query) }
                .max() ?? 0
            if currentMatch <= bestForDomain + 0.18 {
                continue
            }
        }
        selected.append(hit)
        seenDomains[domain, default: 0] += 1
        if selected.count == max(1, maxResults) {
            break
        }
    }

    return selected
}

internal func hostTrustWeight(for urlString: String) -> Double {
    guard let url = URL(string: urlString) else {
        return 0.2
    }
    switch hostTrustProfile(for: url) {
    case .officialDocs:
        return 1.0
    case .officialProduct:
        return 0.9
    case .reference:
        return 0.75
    case .community:
        return 0.55
    case .userGenerated:
        return 0.35
    case .unknown:
        return 0.2
    }
}

internal func shouldRefineDocsSearch(query: String, hits: [WebSearchHit], request: WebToolRequest) -> Bool {
    guard request.domains.isEmpty else {
        return false
    }
    guard let topHit = hits.first else {
        return false
    }

    let loweredQuery = query.lowercased()
    let docsSignals = [
        "doc", "documentation", "developer", "framework", "foundationmodels",
        "language model session", "session", "prompt", "context", "tool",
        "api", "guide", "technote", "wwdc", "sample", "example", "limit"
    ]
    let queryLooksDocsHeavy = docsSignals.contains { loweredQuery.contains($0) }
    guard queryLooksDocsHeavy else {
        return false
    }

    guard request.maxResults <= 2 else {
        return false
    }

    guard localHitNeedsLiveRefresh(topHit, query: query, request: request) else {
        return false
    }

    let currentTopHits = hits.prefix(3)
    let hasStrongSpecificHit = currentTopHits.contains { hit in
        let trust = hostTrustWeight(for: hit.url)
        let queryMatch = hitQueryMatchScore(hit, query: query)
        let penalty = genericHitPenalty(hit, query: query)
        return trust >= 0.75 && queryMatch >= 0.95 && penalty < 0.22
    }
    return hasStrongSpecificHit == false
}

internal func docsRefinementDomains(for query: String) -> [String] {
    let loweredQuery = query.lowercased()
    var domains = [
        "developer.apple.com",
        "machinelearning.apple.com",
    ]
    if loweredQuery.contains("wwdc") || loweredQuery.contains("video") {
        domains.append("developer.apple.com")
    }
    return Array(Set(domains))
}

internal func queryIntentPreferenceScore(_ hit: WebSearchHit, query: String) -> Double {
    let loweredQuery = query.lowercased()
    let loweredTitle = hit.title.lowercased()
    let loweredURL = hit.url.lowercased()
    let isVideo = loweredURL.contains("/videos/play/") || loweredTitle.contains("wwdc")
    let isTechnote = loweredURL.contains("/documentation/technotes/")
    let isFoundationDocs = loweredURL.contains("/documentation/foundationmodels")
    let isMachineLearningResearch = loweredURL.contains("machinelearning.apple.com/research/")

    let wantsWWDC = loweredQuery.contains("wwdc") || loweredQuery.contains("video")
    let wantsResearch = loweredQuery.contains("research") || loweredQuery.contains("introducing")
    let wantsTechnote = loweredQuery.contains("technote")
    let wantsDocs = [
        "doc", "documentation", "guide", "guides", "api",
        "languagemodelsession", "language model session", "generable",
        "@guide", "structured generation", "context window", "availability",
        "tool calling", "prompt engineering", "foundation models"
    ].contains { loweredQuery.contains($0) }

    var score = 0.0
    if wantsWWDC {
        if isVideo { score += 0.2 }
        if isFoundationDocs { score -= 0.08 }
        return score
    }

    if wantsResearch {
        if isMachineLearningResearch { score += 0.2 }
        if isVideo { score -= 0.05 }
        return score
    }

    if wantsTechnote {
        if isTechnote { score += 0.22 }
        if isVideo { score -= 0.15 }
        return score
    }

    if wantsDocs {
        if isFoundationDocs { score += 0.18 }
        if isTechnote { score += 0.12 }
        if isMachineLearningResearch { score += 0.05 }
        if isVideo { score -= 0.16 }
    }

    return score
}

internal func localHitNeedsLiveRefresh(
    _ hit: WebSearchHit,
    query: String,
    request: WebToolRequest
) -> Bool {
    guard request.domains.isEmpty else {
        return false
    }

    let queryMatch = hitQueryMatchScore(hit, query: query)
    let penalty = genericHitPenalty(hit, query: query)
    let trust = hostTrustWeight(for: hit.url)
    let refinementDomains = Set(docsRefinementDomains(for: query))
    let isAlreadyInPreferredDocsDomain = refinementDomains.contains(hit.urlDomain)

    if penalty < 0.22 {
        return false
    }

    if isAlreadyInPreferredDocsDomain, trust >= 0.9, queryMatch >= 1.0 {
        return false
    }

    return queryMatch < 1.1 || isAlreadyInPreferredDocsDomain == false
}

internal func canonicalizeURL(_ urlString: String) throws -> URL {
    guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased(),
          ["http", "https"].contains(scheme)
    else {
        throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Invalid URL: \(urlString)")
    }

    components.scheme = scheme
    components.host = host
    if components.path.isEmpty {
        components.path = "/"
    }
    components.fragment = nil
    guard let url = components.url else {
        throw AgentError.invalidToolArguments(toolName: "websearch", reason: "Invalid URL: \(urlString)")
    }
    return url
}

internal func hostTrustProfile(for url: URL) -> WebHostTrustProfile {
    let host = url.host?.lowercased() ?? ""
    if host.hasPrefix("docs.") || host.contains("developer.") {
        return .officialDocs
    }
    if host.contains("github.io") || host.contains("wikipedia.") || host.contains("mdn") {
        return .reference
    }
    if host.contains("reddit.") || host.contains("stackoverflow.") || host.contains("forum") || host.contains("community") {
        return .community
    }
    if host.split(separator: ".").count <= 2 {
        return .officialProduct
    }
    return .unknown
}

internal func rawFileURL(rootURL: URL, artifactID: String, contentType: String) -> URL {
    let root = rootURL
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let ext: String = if contentType.contains("html") {
        "html"
    } else if contentType.contains("pdf") {
        "pdf"
    } else if contentType.contains("json") {
        "json"
    } else {
        "txt"
    }
    return root.appendingPathComponent("\(artifactID).\(ext)")
}

internal func sha256Hex(_ data: Data) -> String {
    #if canImport(CryptoKit)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
    #else
    return String(data.hashValue, radix: 16)
    #endif
}

internal func trimmedSnippet(_ text: String, limit: Int = 280) -> String {
    let collapsed = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard collapsed.count > limit else { return collapsed }
    return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}

private extension WebSearchHit {
    var urlDomain: String {
        if let url = URL(string: url), let host = url.host?.lowercased() {
            return host
        }
        return "unknown"
    }
}

internal func prettifyJSON(_ data: Data) -> String {
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
        let text = String(data: pretty, encoding: .utf8)
    else {
        return String(data: data, encoding: .utf8) ?? ""
    }
    return text
}

internal func firstMeaningfulLine(in text: String) -> String? {
    text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
}

internal func normalizedDedupKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
