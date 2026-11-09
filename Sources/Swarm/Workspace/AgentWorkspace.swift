import Foundation

/// File-backed workspace for on-device Swarm agents.
public struct AgentWorkspace: Sendable {
    public let bundleRoot: URL
    public let writableRoot: URL
    public let indexCacheRoot: URL

    public init(
        bundleRoot: URL,
        writableRoot: URL,
        indexCacheRoot: URL
    ) throws {
        self.bundleRoot = bundleRoot
        self.writableRoot = writableRoot
        self.indexCacheRoot = indexCacheRoot

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: writableRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: indexCacheRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: memoryDirectory, withIntermediateDirectories: true, attributes: nil)

        for kind in WorkspaceMemoryNote.Kind.allCases {
            try fileManager.createDirectory(
                at: memoryDirectory.appendingPathComponent(kind.directoryName, isDirectory: true),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    public static func appDefault(bundle: Bundle = .main) throws -> AgentWorkspace {
        let fileManager = FileManager.default
        let bundleRoot = (bundle.resourceURL ?? bundle.bundleURL).appendingPathComponent("AgentWorkspace", isDirectory: true)
        let bundleID = bundle.bundleIdentifier ?? "Swarm"

        let appSupportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cachesRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return try AgentWorkspace(
            bundleRoot: bundleRoot,
            writableRoot: appSupportRoot
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("AgentWorkspace", isDirectory: true),
            indexCacheRoot: cachesRoot
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("AgentWorkspace", isDirectory: true)
        )
    }

    public func validate() async throws -> WorkspaceValidationReport {
        var issues: [WorkspaceValidationIssue] = []

        do {
            _ = try loadAgentInstructions()
        } catch {
            issues.append(
                WorkspaceValidationIssue(
                    path: relativePath(for: agentsFileURL),
                    message: error.localizedDescription
                )
            )
        }

        for specURL in try agentSpecURLs() {
            do {
                let spec = try parseAgentSpec(at: specURL)
                for skillID in spec.skills {
                    let skillURL: URL
                    do {
                        let safeSkillID = try validatedPathComponent(
                            skillID,
                            field: "skills",
                            path: relativePath(for: specURL)
                        )
                        skillURL = skillsDirectory
                            .appendingPathComponent(safeSkillID, isDirectory: true)
                            .appendingPathComponent("SKILL.md")
                        _ = try parseSkill(at: skillURL)
                    } catch {
                        issues.append(
                            WorkspaceValidationIssue(
                                path: relativePath(for: specURL),
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            } catch {
                issues.append(
                    WorkspaceValidationIssue(
                        path: relativePath(for: specURL),
                        message: error.localizedDescription
                    )
                )
            }
        }

        for skillURL in try skillEntryURLs() {
            do {
                _ = try parseSkill(at: skillURL)
            } catch {
                issues.append(
                    WorkspaceValidationIssue(
                        path: relativePath(for: skillURL),
                        message: error.localizedDescription
                    )
                )
            }
        }

        for (url, error) in memoryNoteFailures() {
            issues.append(
                WorkspaceValidationIssue(
                    path: relativePath(for: url),
                    message: error.localizedDescription
                )
            )
        }

        return WorkspaceValidationReport(issues: issues)
    }

    public func makeWriter() -> WorkspaceWriter {
        WorkspaceWriter(workspace: self)
    }
}

// MARK: - Runtime Loading

extension AgentWorkspace {
    var agentsFileURL: URL {
        bundleRoot.appendingPathComponent("AGENTS.md")
    }

    var agentsDirectory: URL {
        bundleRoot.appendingPathComponent(".swarm/agents", isDirectory: true)
    }

    var skillsDirectory: URL {
        bundleRoot.appendingPathComponent(".swarm/skills", isDirectory: true)
    }

    var memoryDirectory: URL {
        writableRoot.appendingPathComponent(".swarm/memory", isDirectory: true)
    }

    func loadAgentInstructions() throws -> String {
        guard FileManager.default.fileExists(atPath: agentsFileURL.path) else {
            return ""
        }

        let raw = try String(contentsOf: agentsFileURL, encoding: .utf8)
        if let parsed = try? WorkspaceMarkdownDocument.parse(raw, requireFrontMatterClosure: false) {
            return parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadAgentSpec(id: String) throws -> WorkspaceAgentSpec {
        let id = try validatedPathComponent(id, field: "id", path: relativePath(for: agentsDirectory))
        let specURL = agentsDirectory.appendingPathComponent("\(id).md")
        return try parseAgentSpec(at: specURL)
    }

    func loadSkills(named names: [String]) throws -> [WorkspaceSkill] {
        try names.map { name in
            let name = try validatedPathComponent(name, field: "name", path: relativePath(for: skillsDirectory))
            return try parseSkill(
                at: skillsDirectory
                    .appendingPathComponent(name, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
            )
        }
    }

    /// Loads every well-formed memory note.
    ///
    /// Read-only: malformed notes are skipped and logged, never moved or
    /// rewritten. ``validate()`` reports them.
    func loadMemoryNotes() throws -> [WorkspaceMemoryNote] {
        scanMemoryNotes().compactMap { url, result in
            switch result {
            case .success(let note):
                return note
            case .failure(let error):
                Log.memory.warning("WorkspaceMemory: Skipping malformed note at \(url.path): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Memory notes that fail to parse, with their errors.
    func memoryNoteFailures() -> [(url: URL, error: any Error)] {
        scanMemoryNotes().compactMap { url, result in
            guard case .failure(let error) = result else { return nil }
            return (url, error)
        }
    }

    private func scanMemoryNotes() -> [(url: URL, result: Result<WorkspaceMemoryNote, any Error>)] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: memoryDirectory.path) else {
            return []
        }

        var results: [(url: URL, result: Result<WorkspaceMemoryNote, any Error>)] = []
        for kind in WorkspaceMemoryNote.Kind.allCases {
            let kindDirectory = memoryDirectory.appendingPathComponent(kind.directoryName, isDirectory: true)
            guard let enumerator = fileManager.enumerator(at: kindDirectory, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
                results.append((url, Result { try parseMemoryNote(at: url, expectedKind: kind) }))
            }
        }
        return results
    }
}

// MARK: - Validation Models

public struct WorkspaceValidationReport: Sendable {
    public let issues: [WorkspaceValidationIssue]

    public var isValid: Bool { issues.isEmpty }

    public init(issues: [WorkspaceValidationIssue]) {
        self.issues = issues
    }
}

public struct WorkspaceValidationIssue: Sendable, Equatable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public enum AgentWorkspaceError: LocalizedError {
    case missingAgentSpec(String)
    case missingSkill(String)
    case invalidFrontMatter(path: String, reason: String)
    case invalidField(path: String, field: String, reason: String)
    case invalidSkillDirectory(path: String, expectedName: String, actualName: String)
    case invalidMemoryNote(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingAgentSpec(let id):
            return "Missing agent spec '\(id)'."
        case .missingSkill(let name):
            return "Missing SKILL.md for skill '\(name)'."
        case .invalidFrontMatter(let path, let reason):
            return "Invalid front matter in \(path): \(reason)"
        case .invalidField(let path, let field, let reason):
            return "Invalid field '\(field)' in \(path): \(reason)"
        case .invalidSkillDirectory(let path, let expectedName, let actualName):
            return "Skill directory mismatch in \(path): expected '\(expectedName)' but found '\(actualName)'"
        case .invalidMemoryNote(let path, let reason):
            return "Invalid memory note in \(path): \(reason)"
        }
    }
}

// MARK: - Parsed Workspace Types

struct WorkspaceAgentSpec: Sendable, Equatable {
    let id: String
    let title: String
    let skills: [String]
    let body: String
    let path: URL
}

struct WorkspaceSkill: Sendable, Equatable {
    let name: String
    let description: String
    let body: String
    let allowedTools: [String]
    let compatibility: [String]
    let metadata: [String: String]
    let path: URL
}

struct WorkspaceMemoryNote: Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        case fact
        case decision
        case task
        case lesson
        case handoff

        var directoryName: String {
            switch self {
            case .fact: "facts"
            case .decision: "decisions"
            case .task: "tasks"
            case .lesson: "lessons"
            case .handoff: "handoffs"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let body: String
    let tags: [String]
    let status: String?
    let revision: Int
    let path: URL
}

// MARK: - Parsing

extension AgentWorkspace {
    func parseAgentSpec(at url: URL) throws -> WorkspaceAgentSpec {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentWorkspaceError.missingAgentSpec(url.deletingPathExtension().lastPathComponent)
        }

        let raw = try String(contentsOf: url, encoding: .utf8)
        let document: WorkspaceMarkdownDocument
        do {
            document = try WorkspaceMarkdownDocument.parse(raw, requireFrontMatterClosure: true)
        } catch let error as AgentWorkspaceError {
            throw error.relocated(to: relativePath(for: url))
        }

        let schemaVersion = try document.requiredInt("schema_version", path: relativePath(for: url))
        guard schemaVersion >= 1 else {
            throw AgentWorkspaceError.invalidField(
                path: relativePath(for: url),
                field: "schema_version",
                reason: "must be >= 1"
            )
        }

        let id = try document.requiredString("id", path: relativePath(for: url))
        _ = try validatedPathComponent(id, field: "id", path: relativePath(for: url))
        let expectedID = url.deletingPathExtension().lastPathComponent
        guard id == expectedID else {
            throw AgentWorkspaceError.invalidField(
                path: relativePath(for: url),
                field: "id",
                reason: "must match file name '\(expectedID)'"
            )
        }
        let title = try document.requiredString("title", path: relativePath(for: url))
        _ = try document.requiredInt("revision", path: relativePath(for: url))
        _ = try document.requiredString("updated_at", path: relativePath(for: url))
        let skills = document.stringArray("skills") ?? []
        let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty else {
            throw AgentWorkspaceError.invalidField(
                path: relativePath(for: url),
                field: "body",
                reason: "agent specs require a non-empty markdown body"
            )
        }

        return WorkspaceAgentSpec(
            id: id,
            title: title,
            skills: skills,
            body: body,
            path: url
        )
    }

    func parseSkill(at url: URL) throws -> WorkspaceSkill {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentWorkspaceError.missingSkill(url.deletingLastPathComponent().lastPathComponent)
        }

        let raw = try String(contentsOf: url, encoding: .utf8)
        let document: WorkspaceMarkdownDocument
        do {
            document = try WorkspaceMarkdownDocument.parse(raw, requireFrontMatterClosure: true)
        } catch let error as AgentWorkspaceError {
            throw error.relocated(to: relativePath(for: url))
        }

        let name = try document.requiredString("name", path: relativePath(for: url))
        _ = try validatedPathComponent(name, field: "name", path: relativePath(for: url))
        let description = try document.requiredString("description", path: relativePath(for: url))
        let directoryName = url.deletingLastPathComponent().lastPathComponent
        guard name == directoryName else {
            throw AgentWorkspaceError.invalidSkillDirectory(
                path: relativePath(for: url),
                expectedName: name,
                actualName: directoryName
            )
        }

        return WorkspaceSkill(
            name: name,
            description: description,
            body: document.body.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedTools: document.stringArray("allowed-tools") ?? [],
            compatibility: document.stringArray("compatibility") ?? [],
            metadata: document.stringDictionary("metadata") ?? [:],
            path: url
        )
    }

    func parseMemoryNote(at url: URL, expectedKind: WorkspaceMemoryNote.Kind) throws -> WorkspaceMemoryNote {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let decoded = try WorkspaceNoteCodec.decode(raw, expectedKind: expectedKind, path: relativePath(for: url))
        return WorkspaceMemoryNote(
            id: decoded.id,
            kind: decoded.fields.kind,
            title: decoded.fields.title,
            body: decoded.fields.body,
            tags: decoded.fields.tags,
            status: decoded.fields.status,
            revision: decoded.fields.revision,
            path: url
        )
    }

    private func agentSpecURLs() throws -> [URL] {
        try markdownFiles(in: agentsDirectory)
    }

    private func skillEntryURLs() throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: skillsDirectory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(at: skillsDirectory, includingPropertiesForKeys: nil)
            .filter { url in
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }
            .map { $0.appendingPathComponent("SKILL.md") }
    }

    private func markdownFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func relativePath(for url: URL) -> String {
        if let range = url.path.range(of: bundleRoot.path) {
            let suffix = String(url.path[range.upperBound...])
            return suffix.isEmpty ? "." : String(suffix.drop(while: { $0 == "/" }))
        }
        if let range = url.path.range(of: writableRoot.path) {
            let suffix = String(url.path[range.upperBound...])
            return suffix.isEmpty ? "." : String(suffix.drop(while: { $0 == "/" }))
        }
        return url.path
    }

    private func validatedPathComponent(_ value: String, field: String, path: String) throws -> String {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines) == value,
              !value.isEmpty,
              value != ".",
              value != "..",
              !value.contains("/"),
              !value.contains("\\")
        else {
            throw AgentWorkspaceError.invalidField(
                path: path,
                field: field,
                reason: "must be a single path component"
            )
        }

        return value
    }

}

extension AgentWorkspaceError {
    /// The same error reported against `path` (parsers throw with a placeholder path).
    func relocated(to path: String) -> AgentWorkspaceError {
        switch self {
        case .invalidFrontMatter(_, let reason):
            .invalidFrontMatter(path: path, reason: reason)
        case .invalidField(_, let field, let reason):
            .invalidField(path: path, field: field, reason: reason)
        case .invalidSkillDirectory(_, let expectedName, let actualName):
            .invalidSkillDirectory(path: path, expectedName: expectedName, actualName: actualName)
        case .invalidMemoryNote(_, let reason):
            .invalidMemoryNote(path: path, reason: reason)
        case .missingAgentSpec, .missingSkill:
            self
        }
    }
}

/// Minimal front-matter markdown parser shared by agent specs, skills, and notes.
struct WorkspaceMarkdownDocument {
    enum FrontMatterValue: Equatable {
        case string(String)
        case int(Int)
        case bool(Bool)
        case array([String])
        case dictionary([String: String])
    }

    /// A front-matter value's source text, before typing or quote stripping.
    enum RawValue: Equatable {
        /// Text after `key:` on the same line, trimmed.
        case inline(String)
        /// Indented lines under `key:`, untrimmed.
        case block([String])
    }

    let metadata: [String: FrontMatterValue]
    let rawValues: [String: RawValue]
    let body: String

    static func parse(_ text: String, requireFrontMatterClosure: Bool) throws -> WorkspaceMarkdownDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return WorkspaceMarkdownDocument(
                metadata: [:],
                rawValues: [:],
                body: normalized.trimmingCharacters(in: .newlines)
            )
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            if requireFrontMatterClosure {
                throw AgentWorkspaceError.invalidFrontMatter(path: "<inline>", reason: "missing closing ---")
            }
            return WorkspaceMarkdownDocument(metadata: [:], rawValues: [:], body: normalized.trimmingCharacters(in: .newlines))
        }

        let metadataLines = Array(lines[1..<closingIndex])
        let bodyLines = Array(lines[(closingIndex + 1)...])
        let (metadata, rawValues) = try parseMetadataLines(metadataLines)
        return WorkspaceMarkdownDocument(
            metadata: metadata,
            rawValues: rawValues,
            body: bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        )
    }

    func string(_ key: String) -> String? {
        switch metadata[key] {
        case .string(let value): value
        case .int(let value): String(value)
        case .bool(let value): String(value)
        case .none, .array, .dictionary: nil
        }
    }

    func int(_ key: String) -> Int? {
        switch metadata[key] {
        case .int(let value): value
        case .string(let value): Int(value)
        case .none, .array, .dictionary, .bool: nil
        }
    }

    func stringArray(_ key: String) -> [String]? {
        switch metadata[key] {
        case .array(let values): values
        case .string(let value): [value]
        case .none, .int, .bool, .dictionary: nil
        }
    }

    func stringDictionary(_ key: String) -> [String: String]? {
        guard case .dictionary(let values)? = metadata[key] else {
            return nil
        }
        return values
    }

    func requiredString(_ key: String, path: String) throws -> String {
        guard let value = string(key), !value.isEmpty else {
            throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "is required")
        }
        return value
    }

    func requiredInt(_ key: String, path: String) throws -> Int {
        guard let value = int(key) else {
            throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "must be an integer")
        }
        return value
    }

    private static func parseMetadataLines(_ lines: [String]) throws -> ([String: FrontMatterValue], [String: RawValue]) {
        var metadata: [String: FrontMatterValue] = [:]
        var rawValues: [String: RawValue] = [:]
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            guard !rawLine.hasPrefix(" "), !rawLine.hasPrefix("\t") else {
                throw AgentWorkspaceError.invalidFrontMatter(path: "<inline>", reason: "unexpected indentation at '\(trimmed)'")
            }

            let parts = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw AgentWorkspaceError.invalidFrontMatter(path: "<inline>", reason: "expected key/value line '\(trimmed)'")
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let remainder = String(parts[1]).trimmingCharacters(in: .whitespaces)

            if !remainder.isEmpty {
                metadata[key] = parseInlineValue(remainder)
                rawValues[key] = .inline(remainder)
                index += 1
                continue
            }

            index += 1
            var nested: [String] = []
            while index < lines.count {
                let nestedLine = lines[index]
                if nestedLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                    continue
                }
                guard nestedLine.hasPrefix(" ") || nestedLine.hasPrefix("\t") else {
                    break
                }
                nested.append(nestedLine)
                index += 1
            }

            if nested.isEmpty {
                metadata[key] = .string("")
                rawValues[key] = .inline("")
            } else {
                metadata[key] = try parseNestedValue(nested)
                rawValues[key] = .block(nested)
            }
        }

        return (metadata, rawValues)
    }

    private static func parseInlineValue(_ value: String) -> FrontMatterValue {
        if value == "[]" {
            return .array([])
        }
        if value.first == "[", value.last == "]" {
            let contents = value.dropFirst().dropLast()
            let values = contents
                .split(separator: ",")
                .map { parseScalarText(String($0).trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
            return .array(values)
        }
        if let intValue = Int(value) {
            return .int(intValue)
        }
        if value == "true" || value == "false" {
            return .bool(value == "true")
        }
        return .string(parseScalarText(value))
    }

    private static func parseNestedValue(_ lines: [String]) throws -> FrontMatterValue {
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else {
            return .string("")
        }

        if first.hasPrefix("- ") {
            let values = lines.map { line in
                parseScalarText(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
            }
            return .array(values)
        }

        var dictionary: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw AgentWorkspaceError.invalidFrontMatter(path: "<inline>", reason: "invalid nested metadata '\(trimmed)'")
            }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = parseScalarText(String(parts[1]).trimmingCharacters(in: .whitespaces))
            dictionary[key] = value
        }
        return .dictionary(dictionary)
    }

    private static func parseScalarText<S: StringProtocol>(_ value: S) -> String {
        let trimmed = String(value).trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return String(trimmed) }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return String(trimmed)
    }
}
