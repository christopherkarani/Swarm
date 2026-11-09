import Foundation

/// Safe verbs for writing durable workspace memory notes.
public actor WorkspaceWriter {
    private let workspace: AgentWorkspace
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    /// - Parameters:
    ///   - now: Clock for `updated_at`; injectable for deterministic tests.
    ///   - makeID: Source of new note identifiers; injectable for deterministic tests.
    init(
        workspace: AgentWorkspace,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.workspace = workspace
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    public func recordFact(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .fact, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func recordDecision(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .decision, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func createTask(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .task, title: title, body: content, tags: tags, status: "open")
    }

    @discardableResult
    public func recordLesson(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .lesson, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func recordHandoff(title: String, content: String, tags: [String] = []) throws -> URL {
        try createNote(kind: .handoff, title: title, body: content, tags: tags, status: nil)
    }

    @discardableResult
    public func completeTask(id: String, resolution: String? = nil) throws -> URL {
        let taskDirectory = workspace.memoryDirectory.appendingPathComponent(WorkspaceMemoryNote.Kind.task.directoryName, isDirectory: true)
        let taskURL = try findNote(id: id, in: taskDirectory)
        let existingTask = try workspace.parseMemoryNote(at: taskURL, expectedKind: .task)
        let updatedRevision = existingTask.revision + 1
        let updatedBody: String
        if let resolution, !resolution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedBody = "\(existingTask.body)\n\nResolution:\n\(resolution.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            updatedBody = existingTask.body
        }

        let markdown = WorkspaceNoteCodec.encode(
            WorkspaceNoteFields(
                kind: .task,
                title: existingTask.title,
                body: updatedBody,
                tags: existingTask.tags,
                status: "completed",
                revision: updatedRevision
            ),
            id: existingTask.id,
            updatedAt: now()
        )
        try markdown.write(to: taskURL, atomically: true, encoding: .utf8)
        return taskURL
    }
}

private extension WorkspaceWriter {
    func createNote(
        kind: WorkspaceMemoryNote.Kind,
        title: String,
        body: String,
        tags: [String],
        status: String?
    ) throws -> URL {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = makeID()
        let fileName = "\(slug(from: trimmedTitle.isEmpty ? id : trimmedTitle))-\(id.prefix(8)).md"
        let directory = workspace.memoryDirectory.appendingPathComponent(kind.directoryName, isDirectory: true)
        let url = directory.appendingPathComponent(fileName)

        let markdown = WorkspaceNoteCodec.encode(
            WorkspaceNoteFields(
                kind: kind,
                title: trimmedTitle.isEmpty ? id : trimmedTitle,
                body: trimmedBody,
                tags: tags,
                status: status,
                revision: 1
            ),
            id: id,
            updatedAt: now()
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func findNote(id: String, in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw AgentWorkspaceError.invalidMemoryNote(path: directory.path, reason: "task directory not found")
        }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            if let note = try? workspace.parseMemoryNote(at: url, expectedKind: .task), note.id == id {
                return url
            }
        }

        throw AgentWorkspaceError.invalidMemoryNote(path: directory.path, reason: "task '\(id)' not found")
    }

    func slug(from text: String) -> String {
        let pieces = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let slug = pieces.joined(separator: "-")
        return slug.isEmpty ? "note" : slug
    }
}
