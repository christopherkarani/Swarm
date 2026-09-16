import Foundation

/// One note in a job's notes box.
public struct JobRecord: Sendable, Equatable {
    /// Caller-chosen kind, such as `"note"` or `"outline"`.
    public let kind: String

    /// Note body.
    public let text: String

    public init(kind: String, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Shared notes for a `Job`.
///
/// Swarm ships ``InMemoryJobStore``. Pass your own actor if you want files
/// or another backend. The adapter owns any disk; Job does not.
///
/// Stores hold records. Search and token truncation live on
/// ``JobSession/window(query:tokenLimit:)``, not the store.
public protocol JobStore: Actor, Sendable {
    /// Append a record.
    func ingest(_ record: JobRecord) async

    /// All records, ingest order.
    func records() async -> [JobRecord]

    /// Exact `kind` match, ingest order.
    func records(kind: String) async -> [JobRecord]
}

/// In-process notes box. Default store for ``Job``.
public actor InMemoryJobStore: JobStore {
    private var stored: [JobRecord] = []

    public init() {}

    public func ingest(_ record: JobRecord) async {
        stored.append(record)
    }

    public func records() async -> [JobRecord] {
        stored
    }

    public func records(kind: String) async -> [JobRecord] {
        stored.filter { $0.kind == kind }
    }
}
