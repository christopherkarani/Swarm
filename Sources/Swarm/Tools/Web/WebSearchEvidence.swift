import Foundation
import Wax

internal let embeddedWebSearchEnvelopePrefix = "[[swarm.websearch.envelope:"
internal let embeddedWebSearchEnvelopeSuffix = "]]"

public struct WebSearchEvidenceRecord: Codable, Sendable, Equatable {
    public struct Hit: Codable, Sendable, Equatable {
        public var title: String
        public var url: String
        public var snippet: String
        public var domain: String
        public var score: Double

        public init(
            title: String,
            url: String,
            snippet: String,
            domain: String,
            score: Double
        ) {
            self.title = title
            self.url = url
            self.snippet = snippet
            self.domain = domain
            self.score = score
        }
    }

    public var id: String
    public var query: String
    public var mode: String
    public var summary: String
    public var semanticCore: String?
    public var primaryHit: Hit?
    public var supportingHits: [Hit]
    public var citations: [CitationRecord]
    public var artifactRefs: [String]
    public var bundleID: String?
    public var createdAt: Date
    public var rawPayloadRef: String?

    public init(
        id: String = UUID().uuidString,
        query: String,
        mode: String,
        summary: String,
        semanticCore: String? = nil,
        primaryHit: Hit? = nil,
        supportingHits: [Hit] = [],
        citations: [CitationRecord] = [],
        artifactRefs: [String] = [],
        bundleID: String? = nil,
        createdAt: Date = Date(),
        rawPayloadRef: String? = nil
    ) {
        self.id = id
        self.query = query
        self.mode = mode
        self.summary = summary
        self.semanticCore = semanticCore
        self.primaryHit = primaryHit
        self.supportingHits = supportingHits
        self.citations = citations
        self.artifactRefs = artifactRefs
        self.bundleID = bundleID
        self.createdAt = createdAt
        self.rawPayloadRef = rawPayloadRef
    }
}

internal struct CompiledWebSearchEvidence: Sendable, Equatable {
    let record: WebSearchEvidenceRecord
    let compactTranscript: String
    let searchableText: String
}

internal enum WebSearchEvidenceCompiler {
    static func embedEnvelope(_ envelope: WebSearchEnvelope, in legacyText: String) -> String {
        guard let data = try? JSONEncoder().encode(envelope) else {
            return legacyText
        }
        let encoded = data.base64EncodedString()
        return """
        \(legacyText)

        \(embeddedWebSearchEnvelopePrefix)\(encoded)\(embeddedWebSearchEnvelopeSuffix)
        """
    }

    static func extractEnvelope(from text: String) -> WebSearchEnvelope? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.range(of: embeddedWebSearchEnvelopePrefix),
              let end = trimmed.range(
                  of: embeddedWebSearchEnvelopeSuffix,
                  range: start.upperBound..<trimmed.endIndex
              )
        else {
            return nil
        }

        let encoded = String(trimmed[start.upperBound..<end.lowerBound])
        guard let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return try? JSONDecoder().decode(WebSearchEnvelope.self, from: data)
    }

    static func stripEnvelopeMarker(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(embeddedWebSearchEnvelopePrefix) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compile(
        rawPayload: String,
        queryFallback: String?,
        modeFallback: String = "search"
    ) -> CompiledWebSearchEvidence? {
        let normalizedPayload = normalizeLegacyPayload(rawPayload)
        let envelope = extractEnvelope(from: normalizedPayload)
        let cleanedPayload = stripEnvelopeMarker(from: normalizedPayload)
        let query = resolveQuery(from: envelope, fallback: queryFallback, rawPayload: cleanedPayload)
        guard !query.isEmpty else {
            return nil
        }

        let rankedHits = rankHits(
            hits: envelope?.hits ?? legacyHits(from: cleanedPayload, query: query),
            query: query
        )
        let primary = rankedHits.first.map(makeHit(from:))
        let supporting = Array(rankedHits.dropFirst().prefix(2)).map(makeHit(from:))
        let summary = envelope?.final4KAnswer.nonEmpty
            ?? envelope?.summary.nonEmpty
            ?? cleanedPayload.nonEmpty
            ?? "No websearch summary captured."

        let record = WebSearchEvidenceRecord(
            query: query,
            mode: envelope?.mode ?? modeFallback,
            summary: trimmedSnippet(summary, limit: 360),
            semanticCore: envelope?.semanticCore.map { trimmedSnippet($0, limit: 320) },
            primaryHit: primary,
            supportingHits: supporting,
            citations: Array((envelope?.citations ?? []).prefix(4)),
            artifactRefs: envelope?.artifactRefs ?? [],
            bundleID: envelope?.bundle?.bundleID ?? envelope?.groundedEvidence?.bundleID
        )

        return CompiledWebSearchEvidence(
            record: record,
            compactTranscript: compactTranscript(for: record),
            searchableText: searchableText(for: record)
        )
    }

    static func compactTranscript(for record: WebSearchEvidenceRecord) -> String {
        var lines = [
            "[Websearch Evidence]",
            "Query: \(record.query)",
        ]
        if let primary = record.primaryHit {
            lines.append("Best: [\(primary.title)](\(primary.url))")
            lines.append("Snippet: \(primary.snippet)")
        } else {
            lines.append("Best: no ranked result captured.")
        }
        for (index, hit) in record.supportingHits.enumerated() {
            lines.append("Support \(index + 1): [\(hit.title)](\(hit.url))")
        }
        lines.append("Summary: \(record.summary)")
        if let bundleID = record.bundleID, !bundleID.isEmpty {
            lines.append("Bundle: \(bundleID)")
        }
        return lines.joined(separator: "\n")
    }

    static func searchableText(for record: WebSearchEvidenceRecord) -> String {
        var chunks = [
            "query: \(record.query)",
            "summary: \(record.summary)",
        ]
        if let semanticCore = record.semanticCore, !semanticCore.isEmpty {
            chunks.append("semantic_core: \(semanticCore)")
        }
        if let primary = record.primaryHit {
            chunks.append("primary_title: \(primary.title)")
            chunks.append("primary_url: \(primary.url)")
            chunks.append("primary_snippet: \(primary.snippet)")
        }
        for hit in record.supportingHits {
            chunks.append("support_title: \(hit.title)")
            chunks.append("support_url: \(hit.url)")
            chunks.append("support_snippet: \(hit.snippet)")
        }
        for citation in record.citations.prefix(4) {
            chunks.append("citation_title: \(citation.title)")
            chunks.append("citation_url: \(citation.url)")
            chunks.append("citation_snippet: \(citation.snippet)")
        }
        return chunks.joined(separator: "\n")
    }

    private static func resolveQuery(
        from envelope: WebSearchEnvelope?,
        fallback: String?,
        rawPayload: String
    ) -> String {
        if let groundedQuery = envelope?.groundedEvidence?.query.trimmingCharacters(in: .whitespacesAndNewlines),
           !groundedQuery.isEmpty
        {
            return groundedQuery
        }
        if let bundleQuery = envelope?.bundle?.query.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleQuery.isEmpty
        {
            return bundleQuery
        }
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let extracted = extractLegacyQuery(from: rawPayload) {
            return extracted
        }
        return ""
    }

    private static func legacyHits(from rawPayload: String, query: String) -> [WebSearchHit] {
        let lines = rawPayload
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var hits: [WebSearchHit] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let parsed = parseMarkdownLink(line) else {
                index += 1
                continue
            }
            let snippet = lines.indices.contains(index + 1) ? lines[index + 1] : ""
            hits.append(
                WebSearchHit(
                    id: "legacy-\(hits.count)",
                    title: parsed.title,
                    url: parsed.url,
                    snippet: trimmedSnippet(snippet, limit: 220),
                    score: 0.5,
                    source: "legacy",
                    cached: false
                )
            )
            index += 2
        }

        if hits.isEmpty, let legacyQuery = extractLegacyQuery(from: rawPayload) {
            hits.append(
                WebSearchHit(
                    id: "legacy-query",
                    title: "Search result for \(legacyQuery)",
                    url: "",
                    snippet: trimmedSnippet(rawPayload, limit: 220),
                    score: 0.1,
                    source: "legacy",
                    cached: false
                )
            )
        }
        return hits
    }

    private static func rankHits(hits: [WebSearchHit], query: String) -> [WebSearchHit] {
        let reranked = hits.map { hit -> (WebSearchHit, Double) in
            let queryScore = hitQueryMatchScore(hit, query: query)
            let trust = hit.hostTrustWeight
            let genericPenalty = genericHitPenalty(hit, query: query)
            let intentBoost = queryIntentPreferenceScore(hit, query: query)
            let score = (hit.score * 0.45) + (queryScore * 0.45) + (trust * 0.1) + intentBoost - genericPenalty
            return (hit, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.score > rhs.0.score
            }
            return lhs.1 > rhs.1
        }

        var selected: [WebSearchHit] = []
        var seenDomains: [String: Int] = [:]

        for (hit, _) in reranked {
            let domain = hit.domainKey
            let duplicateCount = seenDomains[domain, default: 0]
            if duplicateCount > 0, selected.count >= 2 {
                let currentScore = hitQueryMatchScore(hit, query: query)
                let bestDomainScore = selected
                    .filter { $0.domainKey == domain }
                    .map { hitQueryMatchScore($0, query: query) }
                    .max() ?? 0
                if currentScore <= bestDomainScore + 0.12 {
                    continue
                }
            }
            selected.append(hit)
            seenDomains[domain, default: 0] += 1
        }

        return selected
    }

    private static func makeHit(from hit: WebSearchHit) -> WebSearchEvidenceRecord.Hit {
        WebSearchEvidenceRecord.Hit(
            title: trimmedSnippet(hit.title, limit: 140),
            url: hit.url,
            snippet: trimmedSnippet(hit.snippet, limit: 220),
            domain: hit.domainKey,
            score: hit.score
        )
    }

    private static func hitQueryMatchScore(_ hit: WebSearchHit, query: String) -> Double {
        let title = hit.title.lowercased()
        let snippet = hit.snippet.lowercased()
        let url = hit.url.lowercased()
        let tokens = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !tokens.isEmpty else {
            return 0
        }

        var hits = 0.0
        for token in tokens {
            if title.contains(token) { hits += 0.55 }
            if snippet.contains(token) { hits += 0.3 }
            if url.contains(token) { hits += 0.15 }
        }

        let normalized = min(hits / Double(tokens.count), 1.5)
        let exactPhraseBonus = title.contains(query.lowercased()) || url.contains(query.lowercased()) ? 0.2 : 0
        return min(normalized + exactPhraseBonus, 1.6)
    }

    private static func genericHitPenalty(_ hit: WebSearchHit, query: String) -> Double {
        let loweredURL = hit.url.lowercased()
        let loweredTitle = hit.title.lowercased()
        let queryLower = query.lowercased()
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
        return loweredTitle.contains(queryLower) || loweredURL.contains(queryLower) ? 0.05 : 0.18
    }

    private static func extractLegacyQuery(from rawPayload: String) -> String? {
        let firstLine = rawPayload
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let firstLine,
              let range = firstLine.range(of: "for '")
        else {
            return nil
        }
        let suffix = firstLine[range.upperBound...]
        guard let end = suffix.firstIndex(of: "'") else {
            return nil
        }
        return String(suffix[..<end])
    }

    private static func parseMarkdownLink(_ line: String) -> (title: String, url: String)? {
        let pattern = #"\[(.+?)\]\((https?://[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let titleRange = Range(match.range(at: 1), in: line),
              let urlRange = Range(match.range(at: 2), in: line)
        else {
            return nil
        }
        return (String(line[titleRange]), String(line[urlRange]))
    }

    private static func normalizeLegacyPayload(_ rawPayload: String) -> String {
        let trimmed = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data)
        {
            return decoded
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\t", with: "\t")
        }
        return trimmed
    }
}

extension WebSearchHit {
    fileprivate var domainKey: String {
        if let url = URL(string: url), let host = url.host?.lowercased() {
            return host
        }
        return "unknown"
    }

    fileprivate var hostTrustWeight: Double {
        if let url = URL(string: url) {
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
        return 0.2
    }
}

public protocol WebSearchEvidenceMemory: Memory {
    func addWebSearchResult(rawPayload: String, evidence: WebSearchEvidenceRecord) async
}

internal actor WebSearchEvidenceStore {
    private let rootURL: URL
    private let recordsURL: URL
    private let rawResultsURL: URL
    private let indexURL: URL
    private var memory: Wax.Memory
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootURL: URL) async throws {
        self.rootURL = rootURL
        recordsURL = rootURL.appendingPathComponent("records", isDirectory: true)
        rawResultsURL = rootURL.appendingPathComponent("raw-results", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("evidence-index.wax")

        try FileManager.default.createDirectory(at: recordsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawResultsURL, withIntermediateDirectories: true)

        var config = Wax.Memory.Config.default
        config.enableVectorSearch = false
        do {
            memory = try await Wax.Memory(at: indexURL, config: config)
        } catch {
            try? FileManager.default.removeItem(at: indexURL)
            memory = try await Wax.Memory(at: indexURL, config: config)
        }
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try await rebuildIndex()
    }

    func save(rawPayload: String, record: WebSearchEvidenceRecord, searchableText: String) async throws {
        let rawURL = rawResultsURL.appendingPathComponent("\(record.id).txt")
        try rawPayload.write(to: rawURL, atomically: true, encoding: .utf8)

        var stored = record
        stored.rawPayloadRef = rawURL.path
        let recordURL = recordsURL.appendingPathComponent("\(record.id).json")
        try encoder.encode(stored).write(to: recordURL, options: .atomic)

        try await rebuildIndex()
        try await memory.flush()
        _ = searchableText
    }

    func search(query: String, topK: Int) async throws -> [WebSearchEvidenceRecord] {
        var records: [WebSearchEvidenceRecord] = []
        var seen: Set<String> = []
        do {
            let firstResults = try await memory.search(
                query,
                options: .init(topK: max(topK * 3, topK), includeSurrogates: false, mode: .textOnly)
            )
            for item in firstResults.items {
                guard let recordID = parseRecordID(from: item.text),
                      seen.insert(recordID).inserted,
                      let record = try load(id: recordID)
                else {
                    continue
                }
                records.append(record)
                if records.count == topK {
                    break
                }
            }
        } catch {
            try await rebuildIndex()
            let retryResults = try await memory.search(
                query,
                options: .init(topK: max(topK * 3, topK), includeSurrogates: false, mode: .textOnly)
            )
            for item in retryResults.items {
                guard let recordID = parseRecordID(from: item.text),
                      seen.insert(recordID).inserted,
                      let record = try load(id: recordID)
                else {
                    continue
                }
                records.append(record)
                if records.count == topK {
                    break
                }
            }
        }
        return records
    }

    func clear() async throws {
        try await memory.close()
        try? FileManager.default.removeItem(at: rootURL)
    }

    private func load(id: String) throws -> WebSearchEvidenceRecord? {
        let url = recordsURL.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(WebSearchEvidenceRecord.self, from: Data(contentsOf: url))
    }

    private func rebuildIndex() async throws {
        try await memory.close()
        try? FileManager.default.removeItem(at: indexURL)

        var config = Wax.Memory.Config.default
        config.enableVectorSearch = false
        memory = try await Wax.Memory(at: indexURL, config: config)

        let files = try FileManager.default.contentsOfDirectory(
            at: recordsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
            let record = try decoder.decode(WebSearchEvidenceRecord.self, from: Data(contentsOf: file))
            try await memory.save(indexedText(for: record))
        }
    }


    private func indexedText(for record: WebSearchEvidenceRecord) -> String {
        let searchableText = WebSearchEvidenceCompiler.searchableText(for: record)
        return """
        [[record_id:\(record.id)]]
        \(searchableText)
        """
    }

    private func parseRecordID(from text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(2) {
            let value = String(line)
            if value.hasPrefix("[[record_id:"), value.hasSuffix("]]") {
                return String(value.dropFirst(12).dropLast(2))
            }
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
