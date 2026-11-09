import Foundation

/// The user-controlled fields of a workspace memory note.
///
/// These are the values ``WorkspaceNoteCodec`` round-trips: for any fields `x`
/// with a non-empty title and a body without surrounding whitespace,
/// `WorkspaceNoteCodec.decode(WorkspaceNoteCodec.encode(x, ...))` yields `x`.
struct WorkspaceNoteFields: Sendable, Equatable {
    let kind: WorkspaceMemoryNote.Kind
    let title: String
    let body: String
    let tags: [String]
    let status: String?
    let revision: Int
}

/// Pure encoder/decoder for workspace memory note markdown.
///
/// The codec performs no file I/O and reads no clock or random source; the
/// note identifier and timestamp are inputs. ``AgentWorkspace`` and
/// ``WorkspaceWriter`` own the file system.
///
/// ## Format versions
///
/// - `schema_version: 2` (written by ``encode(_:id:updatedAt:)``): every scalar
///   that is not a plain safe token is double-quoted, with `\\`, `\"`, `\n`,
///   `\r`, and `\t` escapes, so any title, tag, or status survives a round trip
///   and cannot inject front-matter keys.
/// - `schema_version: 1` or absent (written by earlier releases): decoded with
///   the original front-matter rules unchanged, so existing notes keep the
///   values they had. A bare bracketed title such as `[WIP]`, which those
///   releases wrote but could not read back, is recovered as its literal text.
enum WorkspaceNoteCodec {
    /// A decoded note: its identifier plus its fields.
    struct Decoded: Sendable, Equatable {
        let id: String
        let fields: WorkspaceNoteFields
    }

    /// The schema version ``encode(_:id:updatedAt:)`` writes.
    static let currentSchemaVersion = 2

    /// Renders `note` as markdown with YAML-style front matter.
    static func encode(_ note: WorkspaceNoteFields, id: String, updatedAt: Date) -> String {
        var lines = [
            "---",
            "schema_version: \(currentSchemaVersion)",
            "id: \(encodeScalar(id))",
            "kind: \(note.kind.rawValue)",
            "title: \(encodeScalar(note.title))",
            "updated_at: \(encodeScalar(ISO8601DateFormatter().string(from: updatedAt)))",
            "revision: \(note.revision)",
        ]

        if !note.tags.isEmpty {
            lines.append("tags:")
            lines.append(contentsOf: note.tags.map { "  - \(encodeScalar($0))" })
        }

        if let status = note.status {
            lines.append("status: \(encodeScalar(status))")
        }

        lines.append("---")
        lines.append(note.body)
        return lines.joined(separator: "\n")
    }

    /// Parses note markdown.
    ///
    /// - Parameters:
    ///   - text: The full markdown file contents.
    ///   - expectedKind: The kind implied by the note's directory; a mismatch throws.
    ///   - path: The display path used in thrown errors.
    /// - Throws: ``AgentWorkspaceError`` when the note is malformed.
    static func decode(_ text: String, expectedKind: WorkspaceMemoryNote.Kind, path: String) throws -> Decoded {
        let document: WorkspaceMarkdownDocument
        do {
            document = try WorkspaceMarkdownDocument.parse(text, requireFrontMatterClosure: true)
        } catch let error as AgentWorkspaceError {
            throw error.relocated(to: path)
        }

        let fields = NoteFieldReader(
            document: document,
            dialect: (document.int("schema_version") ?? 1) >= currentSchemaVersion ? .current : .legacy,
            path: path
        )
        let id = try fields.requiredScalar("id")
        let title = try fields.requiredScalar("title")
        let kindValue = try fields.requiredScalar("kind")
        guard kindValue == expectedKind.rawValue else {
            throw AgentWorkspaceError.invalidMemoryNote(
                path: path,
                reason: "expected kind '\(expectedKind.rawValue)' but found '\(kindValue)'"
            )
        }

        return Decoded(
            id: id,
            fields: WorkspaceNoteFields(
                kind: expectedKind,
                title: title,
                body: document.body.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: try fields.tags(),
                status: try fields.scalar("status"),
                revision: document.int("revision") ?? 1
            )
        )
    }
}

// MARK: - Scalar encoding

extension WorkspaceNoteCodec {
    /// Characters allowed as the first character of an unquoted scalar.
    private static let plainTokenLeadingScalars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    )

    /// Characters allowed anywhere else in an unquoted scalar.
    private static let plainTokenScalars = plainTokenLeadingScalars.union(CharacterSet(charactersIn: " .-_/"))

    static func encodeScalar(_ value: String) -> String {
        isPlainToken(value) ? value : quoted(value)
    }

    /// A plain token starts with an ASCII letter or digit, contains only ASCII
    /// alphanumerics, inner spaces, and `.-_/`, and does not read as an integer
    /// or boolean.
    private static func isPlainToken(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first, let last = scalars.last,
              plainTokenLeadingScalars.contains(first),
              last != " ",
              scalars.allSatisfy(plainTokenScalars.contains)
        else {
            return false
        }
        return Int(value) == nil && value != "true" && value != "false"
    }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    /// Decodes a schema-2 scalar: a double-quoted escaped string, or literal text.
    static func decodeScalar(_ raw: String, key: String, path: String) throws -> String {
        var scalars = Substring(raw).unicodeScalars
        guard scalars.first == "\"" else {
            return raw
        }
        scalars = scalars.dropFirst()

        var result = String.UnicodeScalarView()
        while let scalar = scalars.popFirst() {
            switch scalar {
            case "\"":
                guard scalars.isEmpty else {
                    throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "unexpected text after closing quote")
                }
                return String(result)
            case "\\":
                guard let escaped = scalars.popFirst() else {
                    throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "unterminated escape")
                }
                switch escaped {
                case "\\", "\"": result.append(escaped)
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default:
                    throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "unsupported escape '\\\(escaped)'")
                }
            default:
                result.append(scalar)
            }
        }
        throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "missing closing quote")
    }
}

// MARK: - Field reader

/// Reads note fields from a parsed document under one schema version's rules.
private struct NoteFieldReader {
    enum Dialect {
        /// Schema 1 / unversioned: the original front-matter value rules.
        case legacy
        /// Schema 2: quoted scalars carry escapes.
        case current
    }

    let document: WorkspaceMarkdownDocument
    let dialect: Dialect
    let path: String

    func scalar(_ key: String) throws -> String? {
        switch (dialect, document.rawValues[key]) {
        case (_, .none):
            return nil
        case (.legacy, .inline(let raw)):
            // Earlier writers emitted titles such as `[WIP]` unquoted; the
            // generic parser reads them as arrays. Recover the literal text.
            if case .array? = document.metadata[key] {
                return raw
            }
            return document.string(key)
        case (.legacy, .block):
            return document.string(key)
        case (.current, .inline(let raw)):
            return try WorkspaceNoteCodec.decodeScalar(raw, key: key, path: path)
        case (.current, .block):
            throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "must be a single value")
        }
    }

    func requiredScalar(_ key: String) throws -> String {
        guard let value = try scalar(key), !value.isEmpty else {
            throw AgentWorkspaceError.invalidField(path: path, field: key, reason: "is required")
        }
        return value
    }

    func tags() throws -> [String] {
        switch (dialect, document.rawValues["tags"]) {
        case (.legacy, _):
            return document.stringArray("tags") ?? []
        case (.current, .block(let lines)):
            return try lines.map(decodeTagItem)
        case (.current, _):
            return try scalar("tags").map { [$0] } ?? []
        }
    }

    private func decodeTagItem(_ line: String) throws -> String {
        let item = line.trimmingCharacters(in: .whitespaces)
        guard item.hasPrefix("- ") else {
            throw AgentWorkspaceError.invalidField(path: path, field: "tags", reason: "expected a '- ' list item")
        }
        let raw = String(item.unicodeScalars.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return try WorkspaceNoteCodec.decodeScalar(raw, key: "tags", path: path)
    }
}
