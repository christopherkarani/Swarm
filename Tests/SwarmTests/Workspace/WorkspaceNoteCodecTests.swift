import Foundation
@testable import Swarm
import Testing

@Suite("Workspace Note Codec")
struct WorkspaceNoteCodecTests {
    static let trickyScalars: [String] = [
        "[WIP]",
        "[]",
        "[a, b]",
        "{x: 1}",
        "a: b",
        "#tag",
        #"say "hi""#,
        "\"",
        "it's",
        #"back\slash"#,
        #"C:\path\n"#,
        #"trailing\"#,
        "line1\nline2",
        "key\nstatus: injected",
        "cr\r\nlf",
        "tab\there",
        "  padded  ",
        "   ",
        "-leading",
        "- item",
        "*star",
        "&anchor",
        "!bang",
        "|pipe",
        ">fold",
        "%pct",
        "@at",
        "---",
        "007",
        "true",
        "plain title",
        "日本語 café",
        "🚀 launch",
        "\u{301}combining",
        "nbsp\u{00A0}",
        "line\u{2028}separator",
    ]

    @Test("Titles, tags, and status round-trip", arguments: trickyScalars)
    func scalarFieldsRoundTrip(value: String) throws {
        let fields = WorkspaceNoteFields(
            kind: .task,
            title: value,
            body: "Body text.",
            tags: [value, "plain", value],
            status: value,
            revision: 3
        )

        let decoded = try roundTrip(fields, id: "note-1")

        #expect(decoded == WorkspaceNoteCodec.Decoded(id: "note-1", fields: fields))
    }

    @Test("Ids that need quoting round-trip", arguments: ["[id]", "a: b", "  spaced", "123"])
    func idsRoundTrip(id: String) throws {
        let fields = WorkspaceNoteFields(kind: .fact, title: "Title", body: "", tags: [], status: nil, revision: 1)

        #expect(try roundTrip(fields, id: id).id == id)
    }

    @Test("Empty tags and status round-trip")
    func emptyTagAndStatusRoundTrip() throws {
        let fields = WorkspaceNoteFields(kind: .lesson, title: "T", body: "B", tags: [""], status: "", revision: 1)

        #expect(try roundTrip(fields, id: "n").fields == fields)
    }

    @Test("Absent tags and status stay absent")
    func absentOptionalFieldsRoundTrip() throws {
        let fields = WorkspaceNoteFields(kind: .handoff, title: "T", body: "B", tags: [], status: nil, revision: 1)

        let text = WorkspaceNoteCodec.encode(fields, id: "n", updatedAt: Self.fixedDate)

        #expect(!text.contains("tags:"))
        #expect(!text.contains("status:"))
        #expect(try roundTrip(fields, id: "n").fields == fields)
    }

    @Test("Newlines are escaped inside quotes, never emitted raw")
    func newlinesCannotInjectKeys() {
        let fields = WorkspaceNoteFields(
            kind: .fact,
            title: "x\nstatus: hacked",
            body: "",
            tags: ["a\nrevision: 99"],
            status: nil,
            revision: 1
        )

        let text = WorkspaceNoteCodec.encode(fields, id: "n", updatedAt: Self.fixedDate)
        let frontMatter = text.components(separatedBy: "\n").dropFirst().prefix { $0 != "---" }

        #expect(frontMatter.contains(#"title: "x\nstatus: hacked""#))
        #expect(frontMatter.contains(#"  - "a\nrevision: 99""#))
        #expect(!frontMatter.contains { $0.hasPrefix("status:") })
        #expect(frontMatter.filter { $0.hasPrefix("revision:") } == ["revision: 1"])
    }

    @Test("Encoding is deterministic for its inputs")
    func encodingIsDeterministic() {
        let fields = WorkspaceNoteFields(kind: .task, title: "Ship it", body: "Do it.", tags: ["release"], status: "open", revision: 1)

        let text = WorkspaceNoteCodec.encode(fields, id: "abc", updatedAt: Self.fixedDate)

        #expect(text == """
        ---
        schema_version: 2
        id: abc
        kind: task
        title: Ship it
        updated_at: "2027-01-15T08:00:00Z"
        revision: 1
        tags:
          - release
        status: open
        ---
        Do it.
        """)
    }

    /// Releases before schema 2 ignore `schema_version` on memory notes and
    /// quarantine any note whose `id`, `title`, or `kind` is not a non-empty
    /// string. Schema-2 output must satisfy that check so a downgrade never
    /// moves notes away.
    @Test("Schema 2 notes stay readable by the pre-schema-2 parser", arguments: trickyScalars)
    func schema2NotesPassPreSchema2Parser(value: String) throws {
        let fields = WorkspaceNoteFields(kind: .task, title: value, body: "B", tags: [value], status: value, revision: 1)
        let text = WorkspaceNoteCodec.encode(fields, id: "note-1", updatedAt: Self.fixedDate)

        let document = try WorkspaceMarkdownDocument.parse(text, requireFrontMatterClosure: true)

        #expect(document.string("id") == "note-1")
        #expect(document.string("kind") == "task")
        #expect(document.string("title")?.isEmpty == false)
        #expect(document.stringArray("tags")?.count == 1)
    }

    // MARK: Backward compatibility (schema_version 1)

    struct LegacyCase: Sendable, CustomTestStringConvertible {
        let label: String
        let text: String
        let expected: WorkspaceNoteCodec.Decoded
        var testDescription: String { label }
    }

    /// Notes as earlier releases wrote them, with the values the earlier parser read back.
    static let legacyCases: [LegacyCase] = [
        LegacyCase(
            label: "plain task with tags",
            text: """
            ---
            schema_version: 1
            id: 1b2c
            kind: task
            title: Ship it
            updated_at: 2026-01-01T00:00:00Z
            revision: 2
            tags:
              - release
              - "area: io"
            status: open
            ---
            Body line

            """,
            expected: decoded(id: "1b2c", kind: .task, title: "Ship it", body: "Body line", tags: ["release", "area: io"], status: "open", revision: 2)
        ),
        LegacyCase(
            label: "quoted title keeps the earlier un-unescaped value",
            text: """
            ---
            schema_version: 1
            id: 1b2c
            kind: fact
            title: "say \\"hi\\": now"
            updated_at: 2026-01-01T00:00:00Z
            revision: 1
            ---
            Body
            """,
            expected: decoded(id: "1b2c", kind: .fact, title: #"say \"hi\": now"#, body: "Body", tags: [], status: nil, revision: 1)
        ),
        LegacyCase(
            label: "backslashes in a quoted title are literal",
            text: """
            ---
            schema_version: 1
            id: 1b2c
            kind: fact
            title: "C:\\new\\temp"
            updated_at: 2026-01-01T00:00:00Z
            revision: 1
            ---
            Body
            """,
            expected: decoded(id: "1b2c", kind: .fact, title: #"C:\new\temp"#, body: "Body", tags: [], status: nil, revision: 1)
        ),
        LegacyCase(
            label: "integer-looking title reads as the earlier parser did",
            text: """
            ---
            schema_version: 1
            id: 1b2c
            kind: fact
            title: 007
            updated_at: 2026-01-01T00:00:00Z
            revision: 1
            ---
            Body
            """,
            expected: decoded(id: "1b2c", kind: .fact, title: "7", body: "Body", tags: [], status: nil, revision: 1)
        ),
        LegacyCase(
            label: "hand-written inline tags and missing revision",
            text: """
            ---
            id: 1b2c
            kind: decision
            title: Use SQLite
            tags: [storage, 'db']
            ---
            Because.
            """,
            expected: decoded(id: "1b2c", kind: .decision, title: "Use SQLite", body: "Because.", tags: ["storage", "db"], status: nil, revision: 1)
        ),
        LegacyCase(
            label: "unquoted bracketed title is recovered",
            text: """
            ---
            schema_version: 1
            id: 1b2c
            kind: fact
            title: [WIP]
            updated_at: 2026-01-01T00:00:00Z
            revision: 1
            ---
            Body
            """,
            expected: decoded(id: "1b2c", kind: .fact, title: "[WIP]", body: "Body", tags: [], status: nil, revision: 1)
        ),
    ]

    @Test("Schema 1 notes decode to the values earlier releases read", arguments: legacyCases)
    func legacyNotesDecode(testCase: LegacyCase) throws {
        let decoded = try WorkspaceNoteCodec.decode(testCase.text, expectedKind: testCase.expected.fields.kind, path: "note.md")

        #expect(decoded == testCase.expected)
    }

    // MARK: Malformed input

    struct MalformedCase: Sendable, CustomTestStringConvertible {
        let label: String
        let text: String
        let field: String
        var testDescription: String { label }
    }

    static let malformedCases: [MalformedCase] = [
        MalformedCase(label: "missing title", text: "---\nschema_version: 2\nid: a\nkind: fact\n---\nB", field: "title"),
        MalformedCase(label: "empty title", text: "---\nschema_version: 2\nid: a\nkind: fact\ntitle: \"\"\n---\nB", field: "title"),
        MalformedCase(label: "missing id", text: "---\nschema_version: 1\nkind: fact\ntitle: T\n---\nB", field: "id"),
        MalformedCase(label: "unterminated quote", text: "---\nschema_version: 2\nid: a\nkind: fact\ntitle: \"abc\n---\nB", field: "title"),
        MalformedCase(label: "escaped closing quote", text: "---\nschema_version: 2\nid: a\nkind: fact\ntitle: \"abc\\\"\n---\nB", field: "title"),
        MalformedCase(label: "unsupported escape", text: "---\nschema_version: 2\nid: a\nkind: fact\ntitle: \"a\\qb\"\n---\nB", field: "title"),
        MalformedCase(label: "text after closing quote", text: "---\nschema_version: 2\nid: a\nkind: fact\ntitle: \"a\" b\n---\nB", field: "title"),
    ]

    @Test("Malformed notes throw an invalid-field error naming the field", arguments: malformedCases)
    func malformedNotesThrow(testCase: MalformedCase) {
        let error = #expect(throws: AgentWorkspaceError.self) {
            try WorkspaceNoteCodec.decode(testCase.text, expectedKind: .fact, path: "facts/x.md")
        }

        guard case .invalidField(let path, let field, _)? = error else {
            Issue.record("Expected invalidField, got \(String(describing: error))")
            return
        }
        #expect(path == "facts/x.md")
        #expect(field == testCase.field)
    }

    @Test("Kind mismatch throws")
    func kindMismatchThrows() {
        let fields = WorkspaceNoteFields(kind: .fact, title: "T", body: "B", tags: [], status: nil, revision: 1)
        let text = WorkspaceNoteCodec.encode(fields, id: "n", updatedAt: Self.fixedDate)

        let error = #expect(throws: AgentWorkspaceError.self) {
            try WorkspaceNoteCodec.decode(text, expectedKind: .task, path: "tasks/x.md")
        }

        guard case .invalidMemoryNote(let path, _)? = error else {
            Issue.record("Expected invalidMemoryNote, got \(String(describing: error))")
            return
        }
        #expect(path == "tasks/x.md")
    }

    @Test("Unclosed front matter reports the note path")
    func unclosedFrontMatterReportsPath() {
        let error = #expect(throws: AgentWorkspaceError.self) {
            try WorkspaceNoteCodec.decode("---\nid: a\n", expectedKind: .fact, path: "facts/x.md")
        }

        guard case .invalidFrontMatter(let path, _)? = error else {
            Issue.record("Expected invalidFrontMatter, got \(String(describing: error))")
            return
        }
        #expect(path == "facts/x.md")
    }
}

private extension WorkspaceNoteCodecTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func roundTrip(_ fields: WorkspaceNoteFields, id: String) throws -> WorkspaceNoteCodec.Decoded {
        let text = WorkspaceNoteCodec.encode(fields, id: id, updatedAt: Self.fixedDate)
        return try WorkspaceNoteCodec.decode(text, expectedKind: fields.kind, path: "note.md")
    }
}

private func decoded(
    id: String,
    kind: WorkspaceMemoryNote.Kind,
    title: String,
    body: String,
    tags: [String],
    status: String?,
    revision: Int
) -> WorkspaceNoteCodec.Decoded {
    WorkspaceNoteCodec.Decoded(
        id: id,
        fields: WorkspaceNoteFields(kind: kind, title: title, body: body, tags: tags, status: status, revision: revision)
    )
}
