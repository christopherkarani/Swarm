#if SWARM_INTEGRATIONS
import Foundation

#if canImport(SwiftSoup)
import SwiftSoup
#endif

#if canImport(PDFKit)
import PDFKit
#endif

internal struct WebContentExtractor: Sendable {
    func extract(
        payload: WebFetchPayload,
        goal: String?,
        existingArtifactID: String?,
        rawRootURL: URL?
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
        let rawArtifactURL = rawRootURL.map {
            rawFileURL(rootURL: $0, artifactID: artifactID, contentType: payload.contentType)
        }
        if let rawArtifactURL {
            try SecureFileIO.write(payload.data, to: rawArtifactURL)
        }

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
            rawArtifactRef: rawArtifactURL?.path ?? ""
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
