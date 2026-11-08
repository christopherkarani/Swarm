#if SWARM_INTEGRATIONS
import Foundation
import Wax

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

        try SecureFileIO.createDirectory(at: manifestsURL)
        try SecureFileIO.createDirectory(at: rawURL)
        try SecureFileIO.createDirectory(at: bundlesURL)

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
        try SecureFileIO.write(data, to: manifestURL)
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
        try SecureFileIO.write(encoder.encode(bundle), to: url)
        return bundle
    }

    func loadBundle(id: String) throws -> EvidenceBundleRecord? {
        let url = bundlesURL.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(EvidenceBundleRecord.self, from: Data(contentsOf: url))
    }

    private func saveLocally(_ artifact: StoredWebArtifact) throws -> StoredWebArtifact {
        let manifestURL = manifestsURL.appendingPathComponent("\(artifact.artifact.artifactID).json")
        try SecureFileIO.write(encoder.encode(artifact), to: manifestURL)
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
#endif
