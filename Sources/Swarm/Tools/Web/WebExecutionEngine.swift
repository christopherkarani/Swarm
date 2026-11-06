#if SWARM_INTEGRATIONS
import Foundation
import Wax

internal actor WebToolRuntime {
    static let shared = WebToolRuntime()

    private var stores: [String: WaxWebArtifactStore] = [:]

    func execute(
        request: WebToolRequest,
        configuration: WebSearchTool.Configuration,
        secretStore: (any SecretStore)? = nil
    ) async throws -> WebSearchEnvelope {
        let store = try await store(for: configuration)
        let engine = WebExecutionEngine(configuration: configuration, store: store, secretStore: secretStore)
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
    let secretStore: (any SecretStore)?

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
        let merged = mergeHits(localHits: localHits, remoteHits: remoteHits, maxResults: request.maxResults)
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
            candidates = mergeHits(localHits: candidates, remoteHits: live, maxResults: configuration.maxGroundedFetches)
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
        Log.agents.debug("[WebSearchTool] liveSearch: query=\(redactedQuery(query)), maxResults=\(request.maxResults), domains=\(request.domains), recencyDays=\(request.recencyDays ?? -1)")
        let hits = try await TavilySearchBackend(configuration: configuration, secretStore: secretStore).search(
            query: query,
            maxResults: request.maxResults,
            domains: request.domains,
            recencyDays: request.recencyDays
        )
        Log.agents.debug("[WebSearchTool] liveSearch returned \(hits.count) hits")
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
            rawRootURL: persist ? configuration.storeURL.appendingPathComponent("raw", isDirectory: true) : nil
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
#endif
