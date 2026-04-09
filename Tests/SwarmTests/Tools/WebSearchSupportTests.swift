import Foundation
@testable import Swarm
import Testing

@Suite("WebSearchSupport")
struct WebSearchSupportTests {
    @Test("HTML parser prefers semantic content over boilerplate")
    func htmlParserExtractsStructuredSections() throws {
        let html = """
        <html>
          <head>
            <title>Install Swarm</title>
            <meta name="description" content="Install guide">
            <link rel="canonical" href="https://example.com/docs/install">
          </head>
          <body>
            <nav>Home Docs Pricing</nav>
            <main>
              <h1>Install</h1>
              <p>Run swift build to compile the package.</p>
              <h2>Usage</h2>
              <p>Use websearch in grounded mode for research tasks.</p>
            </main>
            <script>console.log('ignore me')</script>
          </body>
        </html>
        """

        let parsed = HTMLDocumentParser.parse(html, url: try #require(URL(string: "https://example.com/docs/install")))

        #expect(parsed.title == "Install Swarm")
        #expect(parsed.canonicalURL == "https://example.com/docs/install")
        #expect(parsed.description == "Install guide")
        #expect(parsed.sections.count == 2)
        #expect(parsed.sections[0].heading == "Install")
        #expect(parsed.sections[0].text.contains("Run swift build"))
        #expect(parsed.sections[0].text.contains("Home Docs Pricing") == false)
    }

    @Test("Web content extractor writes raw artifacts into the provided store root")
    func extractorUsesProvidedRawRoot() throws {
        let rawRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-extractor-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rawRoot.deletingLastPathComponent()) }

        let html = """
        <html>
          <head><title>API Reference</title></head>
          <body>
            <main>
              <h1>fetch()</h1>
              <p>Parameters are query and detail.</p>
              <pre><code>websearch(mode: "fetch", url: "...")</code></pre>
            </main>
          </body>
        </html>
        """

        let url = try #require(URL(string: "https://docs.example.com/reference/fetch"))
        let payload = WebFetchPayload(
            requestedURL: url,
            finalURL: url,
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            data: Data(html.utf8),
            etag: "etag-1",
            lastModified: nil,
            notModified: false
        )

        let stored = try WebContentExtractor().extract(
            payload: payload,
            goal: "fetch parameters",
            existingArtifactID: nil,
            rawRootURL: rawRoot
        )

        #expect(stored.artifact.pageType == .apiReference)
        #expect(stored.artifact.rawArtifactRef.hasPrefix(rawRoot.path))
        #expect(FileManager.default.fileExists(atPath: stored.artifact.rawArtifactRef))
        #expect(stored.document.sections.isEmpty == false)
        #expect(stored.document.summary.contains("Parameters"))
    }

    @Test("Merged hits prefer close cached results")
    func mergeHitsPrefersUsefulCachedHits() {
        let cached = WebSearchHit(
            id: "cached-1",
            title: "Cached Docs",
            url: "https://example.com/docs",
            snippet: "Cached result",
            score: 0.82,
            source: "wax",
            cached: true,
            artifactID: "artifact-1"
        )
        let remote = WebSearchHit(
            id: "remote-1",
            title: "Remote Docs",
            url: "https://example.com/docs?ref=search",
            snippet: "Remote result",
            score: 0.90,
            source: "tavily",
            cached: false
        )

        let merged = mergeHits(
            localHits: [cached],
            remoteHits: [remote],
            maxResults: 2,
            query: "example docs"
        )

        #expect(merged.first?.cached == true)
        #expect(merged.first?.artifactID == "artifact-1")
    }

    @Test("Merged hits prefer query-specific and more diverse sources over generic pages")
    func mergeHitsPrefersQuerySpecificResults() {
        let genericApple = WebSearchHit(
            id: "remote-1",
            title: "What’s New - Machine Learning - Apple Developer",
            url: "https://developer.apple.com/machine-learning/whats-new/",
            snippet: "Generic machine learning updates.",
            score: 0.94,
            source: "tavily",
            cached: false
        )
        let promptingDoc = WebSearchHit(
            id: "remote-2",
            title: "Prompting an on-device foundation model - Apple Developer",
            url: "https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model",
            snippet: "Prompting techniques for on-device foundation models.",
            score: 0.82,
            source: "tavily",
            cached: false
        )
        let thirdParty = WebSearchHit(
            id: "remote-3",
            title: "Foundation Models Prompting Notes",
            url: "https://example.dev/foundation-models-prompting",
            snippet: "A focused write-up on prompting guidance.",
            score: 0.76,
            source: "tavily",
            cached: false
        )

        let merged = mergeHits(
            localHits: [],
            remoteHits: [genericApple, promptingDoc, thirdParty],
            maxResults: 3,
            query: "Apple Foundation Models prompt engineering"
        )

        #expect(merged.first?.url == promptingDoc.url)
        #expect(merged.prefix(2).contains(where: { $0.url == thirdParty.url }))
    }

    @Test("Broad docs queries prefer canonical docs over WWDC videos")
    func mergeHitsPrefersCanonicalDocsForBroadQueries() {
        let docs = WebSearchHit(
            id: "remote-docs",
            title: "Foundation Models | Apple Developer Documentation",
            url: "https://developer.apple.com/documentation/FoundationModels",
            snippet: "Overview of Apple's Foundation Models framework.",
            score: 0.78,
            source: "tavily",
            cached: false
        )
        let video = WebSearchHit(
            id: "remote-video",
            title: "Meet the Foundation Models framework - WWDC25 - Apple Developer",
            url: "https://developer.apple.com/videos/play/wwdc2025/286/",
            snippet: "WWDC session introducing the Foundation Models framework.",
            score: 0.83,
            source: "tavily",
            cached: false
        )
        let merged = mergeHits(
            localHits: [],
            remoteHits: [video, docs],
            maxResults: 2,
            query: "Apple Foundation Models guides"
        )

        #expect(merged.first?.url == docs.url)
    }

    @Test("Generic Apple landing pages trigger targeted docs refinement")
    func docsRefinementTriggersForGenericTopHit() {
        let genericApple = WebSearchHit(
            id: "remote-1",
            title: "What’s New - Machine Learning - Apple Developer",
            url: "https://developer.apple.com/machine-learning/whats-new/",
            snippet: "Generic machine learning updates.",
            score: 0.94,
            source: "tavily",
            cached: false
        )
        let request = WebToolRequest(
            mode: .search,
            query: "Apple Foundation Models prompt engineering",
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

        #expect(shouldRefineDocsSearch(query: "Apple Foundation Models prompt engineering", hits: [genericApple], request: request))
        #expect(docsRefinementDomains(for: "Apple Foundation Models prompt engineering").contains("developer.apple.com"))
        #expect(docsRefinementDomains(for: "Apple Foundation Models prompt engineering").contains("machinelearning.apple.com"))
    }

    @Test("Specific official docs hit does not trigger refinement")
    func docsRefinementSkipsWhenTopHitIsAlreadySpecific() {
        let specificDoc = WebSearchHit(
            id: "remote-1",
            title: "Managing the on-device foundation model's context window - Apple Developer",
            url: "https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window",
            snippet: "Guidance for managing Foundation Models context windows on device.",
            score: 0.86,
            source: "tavily",
            cached: false
        )
        let request = WebToolRequest(
            mode: .search,
            query: "Apple Foundation Models context window",
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

        #expect(shouldRefineDocsSearch(query: "Apple Foundation Models context window", hits: [specificDoc], request: request) == false)
        #expect(localHitNeedsLiveRefresh(specificDoc, query: "Apple Foundation Models context window", request: request) == false)
    }

    @Test("WebSearch evidence compiler preserves compact transcript and embedded envelope")
    func evidenceCompilerBuildsStructuredRecord() throws {
        let envelope = WebSearchEnvelope(
            mode: "search",
            summary: "Found 2 ranked results for 'Apple Foundation Models prompt engineering'.",
            final4KAnswer: "Prompting docs are available from Apple.",
            semanticCore: "Prompting docs for on-device foundation models.",
            hits: [
                WebSearchHit(
                    id: "hit-1",
                    title: "Prompting an on-device foundation model - Apple Developer",
                    url: "https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model",
                    snippet: "Prompting techniques for on-device foundation models.",
                    score: 0.88,
                    source: "tavily",
                    cached: false
                ),
                WebSearchHit(
                    id: "hit-2",
                    title: "What’s New - Machine Learning - Apple Developer",
                    url: "https://developer.apple.com/machine-learning/whats-new/",
                    snippet: "Generic machine learning updates.",
                    score: 0.93,
                    source: "tavily",
                    cached: false
                ),
            ],
            citations: [
                CitationRecord(
                    artifactID: "artifact-1",
                    sectionID: "section-1",
                    url: "https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model",
                    title: "Prompting an on-device foundation model - Apple Developer",
                    snippet: "Prompting techniques for on-device foundation models."
                )
            ]
        )

        let legacy = """
        Found 2 ranked results for 'Apple Foundation Models prompt engineering'.

        1. [Prompting an on-device foundation model - Apple Developer](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
           Prompting techniques for on-device foundation models.
        """

        let payload = WebSearchEvidenceCompiler.embedEnvelope(envelope, in: legacy)
        let compiled = try #require(
            WebSearchEvidenceCompiler.compile(
                rawPayload: payload,
                queryFallback: "Apple Foundation Models prompt engineering"
            )
        )

        #expect(compiled.record.query == "Apple Foundation Models prompt engineering")
        #expect(compiled.record.primaryHit?.url == "https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model")
        #expect(compiled.compactTranscript.contains("[Websearch Evidence]"))
        #expect(compiled.compactTranscript.contains("Best: [Prompting an on-device foundation model - Apple Developer]"))
    }

    @Test("Evidence compiler prefers canonical docs over WWDC videos for broad docs queries")
    func evidenceCompilerPrefersCanonicalDocsForBroadQueries() throws {
        let envelope = WebSearchEnvelope(
            mode: "search",
            summary: "Found 2 ranked results for 'Apple Foundation Models guides'.",
            final4KAnswer: "Foundation Models guides are available from Apple.",
            semanticCore: "Foundation Models guides and overview docs.",
            hits: [
                WebSearchHit(
                    id: "video",
                    title: "Meet the Foundation Models framework - WWDC25 - Apple Developer",
                    url: "https://developer.apple.com/videos/play/wwdc2025/286/",
                    snippet: "WWDC session introducing the Foundation Models framework.",
                    score: 0.84,
                    source: "tavily",
                    cached: false
                ),
                WebSearchHit(
                    id: "docs",
                    title: "Foundation Models | Apple Developer Documentation",
                    url: "https://developer.apple.com/documentation/FoundationModels",
                    snippet: "Overview of Apple's Foundation Models framework.",
                    score: 0.79,
                    source: "tavily",
                    cached: false
                ),
            ],
            citations: []
        )

        let payload = WebSearchEvidenceCompiler.embedEnvelope(envelope, in: "Found 2 ranked results.")
        let compiled = try #require(
            WebSearchEvidenceCompiler.compile(
                rawPayload: payload,
                queryFallback: "Apple Foundation Models guides"
            )
        )

        #expect(compiled.record.primaryHit?.url == "https://developer.apple.com/documentation/FoundationModels")
    }

    @Test("Saving a fetched artifact replaces old indexed sections")
    func savingArtifactReplacesIndexedSections() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-web-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let configuration = WebSearchTool.Configuration(
            apiKey: nil,
            persistFetchedArtifacts: true,
            storeURL: root,
            enabled: true
        )
        let store = try await WaxWebArtifactStore(configuration: configuration)
        let extractor = WebContentExtractor()
        let url = try #require(URL(string: "https://example.com/docs/install"))

        func payload(_ text: String, etag: String) -> WebFetchPayload {
            let html = """
            <html>
              <head><title>Install</title></head>
              <body>
                <main>
                  <h1>Install</h1>
                  <p>\(text)</p>
                </main>
              </body>
            </html>
            """
            return WebFetchPayload(
                requestedURL: url,
                finalURL: url,
                statusCode: 200,
                contentType: "text/html; charset=utf-8",
                data: Data(html.utf8),
                etag: etag,
                lastModified: nil,
                notModified: false
            )
        }

        let first = try extractor.extract(
            payload: payload("Initial instructions", etag: "etag-1"),
            goal: "install instructions",
            existingArtifactID: nil,
            rawRootURL: root.appendingPathComponent("raw", isDirectory: true)
        )
        let savedFirst = try await store.save(first)
        _ = try await store.save(
            extractor.extract(
                payload: payload("Updated instructions", etag: "etag-2"),
                goal: "updated instructions",
                existingArtifactID: savedFirst.artifact.artifactID,
                rawRootURL: root.appendingPathComponent("raw", isDirectory: true)
            )
        )

        let matches = try await store.searchSections(query: "updated instructions", topK: 10)
        #expect(matches.count == 1)
        #expect(matches.first?.section.text.contains("Updated instructions") == true)
    }
}
