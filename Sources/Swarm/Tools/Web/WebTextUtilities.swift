#if SWARM_INTEGRATIONS
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

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
    maxResults: Int
) -> [WebSearchHit] {
    deduplicateHits(localHits + remoteHits)
        .sorted { lhs, rhs in
            if lhs.cached != rhs.cached {
                return lhs.cached && lhs.score >= rhs.score * 0.9
            }
            return lhs.score > rhs.score
        }
        .prefix(max(1, maxResults))
        .map { $0 }
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
    try? SecureFileIO.createDirectory(at: root)
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
#endif
