#if SWARM_INTEGRATIONS
import Foundation

enum WebPageType: String, Codable, Sendable, Equatable {
    case docs
    case apiReference
    case blog
    case forum
    case pdf
    case tableHeavy
    case codeHeavy
    case generic
}

enum WebHostTrustProfile: String, Codable, Sendable, Equatable {
    case officialDocs
    case officialProduct
    case reference
    case community
    case userGenerated
    case unknown
}

struct WebSearchHit: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var url: String
    var snippet: String
    var score: Double
    var source: String
    var cached: Bool
    var artifactID: String?

    init(
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

struct CitationRecord: Codable, Sendable, Equatable {
    var artifactID: String
    var sectionID: String
    var url: String
    var title: String
    var snippet: String

    init(
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

struct WebSectionChunk: Codable, Sendable, Equatable {
    var id: String
    var artifactID: String
    var heading: String
    var text: String
    var index: Int
    var pageType: WebPageType
    var citations: [CitationRecord]

    init(
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

struct WebArtifactRecord: Codable, Sendable, Equatable {
    var artifactID: String
    var canonicalURL: String
    var title: String
    var contentType: String
    var fetchedAt: Date
    var contentHash: String
    var etag: String?
    var lastModified: String?
    var pageType: WebPageType
    var hostTrust: WebHostTrustProfile
    var freshnessScore: Double
    var rawArtifactRef: String

    init(
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

struct NormalizedWebDocument: Codable, Sendable, Equatable {
    var artifactID: String
    var canonicalURL: String
    var title: String
    var summary: String
    var pageType: WebPageType
    var contentType: String
    var fetchedAt: Date
    var sections: [WebSectionChunk]

    init(
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

struct GroundedEvidence: Codable, Sendable, Equatable {
    var query: String
    var answer: String
    var evidenceSections: [WebSectionChunk]
    var citations: [CitationRecord]
    var bundleID: String?

    init(
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

struct EvidenceBundleRecord: Codable, Sendable, Equatable {
    var bundleID: String
    var query: String
    var artifactIDs: [String]
    var sectionIDs: [String]
    var summary: String
    var createdAt: Date
    var updatedAt: Date

    init(
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

struct WebSearchEnvelope: Codable, Sendable, Equatable {
    var mode: String
    var summary: String
    var final4KAnswer: String
    var semanticCore: String?
    var hits: [WebSearchHit]
    var artifact: WebArtifactRecord?
    var normalizedDocument: NormalizedWebDocument?
    var sectionChunks: [WebSectionChunk]
    var groundedEvidence: GroundedEvidence?
    var citations: [CitationRecord]
    var artifactRefs: [String]
    var bundle: EvidenceBundleRecord?
    var cacheStatus: String
    var rawArtifactRef: String?

    init(
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
#endif
