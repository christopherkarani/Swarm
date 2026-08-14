// ZoniSearchTool.swift
// Swarm Framework
//
// Integration tool for Zoni RAG Framework.

import Foundation

// Note: Apps can inject a Zoni-backed search closure when the Zoni package is
// linked by the host app.

public struct ZoniSearchDocument: Sendable, Equatable {
    public let id: String
    public let title: String
    public let content: String
    public let collection: String?

    public init(id: String, title: String, content: String, collection: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.collection = collection
    }
}

/// A tool that uses the Zoni RAG framework to search through indexed documents.
///
/// This tool allows an agent to query a knowledge base (PDFs, Markdown, Web pages)
/// that has been indexed using Zoni's technical pipeline.
///
/// Implemented as ``AnyJSONTool`` so it compiles without the Macros trait.
/// Prefer ``FunctionTool`` or `@Tool` in application code.
public struct ZoniSearchTool: AnyJSONTool, Sendable {
    public enum Error: Swift.Error, LocalizedError, Sendable {
        case pipelineNotConfigured

        public var errorDescription: String? {
            switch self {
            case .pipelineNotConfigured:
                "ZoniSearchTool is not configured with a retrieval pipeline."
            }
        }
    }

    public let name = "zoni_search"
    public let description =
        "Searches a private knowledge base of documents to find specific, factual information."
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "query",
            description: "The specific question or information to look up in the documents",
            type: .string
        ),
        ToolParameter(
            name: "collection",
            description: "Optional category or collection to limit the search to",
            type: .string,
            isRequired: false
        ),
    ]

    /// The specific question or information to look up in the documents.
    public var query: String = ""

    /// Optional category or collection to limit the search to.
    public var collection: String?

    private let search: @Sendable (String, String?) async throws -> String

    public init() {
        self.init(documents: [])
    }

    public init(documents: [ZoniSearchDocument]) {
        self.init { query, collection in
            Self.searchDocuments(documents, query: query, collection: collection)
        }
    }

    public init(search: @escaping @Sendable (String, String?) async throws -> String) {
        self.query = ""
        self.collection = nil
        self.search = search
    }

    public func execute() async throws -> String {
        try await search(query, collection)
    }

    public func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let query = arguments["query"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'query'"
            )
        }
        var copy = self
        copy.query = query
        copy.collection = arguments["collection"]?.stringValue
        return .string(try await copy.execute())
    }

    private static func searchDocuments(
        _ documents: [ZoniSearchDocument],
        query: String,
        collection: String?
    ) -> String {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else {
            return "No query provided."
        }

        let collectionFilter = collection?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = documents.compactMap { document -> (document: ZoniSearchDocument, score: Int)? in
            if let collectionFilter, !collectionFilter.isEmpty {
                guard document.collection?.lowercased() == collectionFilter else {
                    return nil
                }
            }

            let haystack = "\(document.title) \(document.content)".lowercased()
            let score = tokens.reduce(into: 0) { total, token in
                if haystack.contains(token) {
                    total += document.title.lowercased().contains(token) ? 2 : 1
                }
            }
            return score > 0 ? (document, score) : nil
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                lhs.document.title < rhs.document.title
            } else {
                lhs.score > rhs.score
            }
        }
        .prefix(5)

        guard !matches.isEmpty else {
            return "No matching documents found."
        }

        let rendered = matches.map { match in
            let snippet = makeSnippet(from: match.document.content, tokens: tokens)
            return "- \(match.document.title): \(snippet)"
        }
        .joined(separator: "\n")

        return "Search results:\n\(rendered)"
    }

    private static func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private static func makeSnippet(from content: String, tokens: [String]) -> String {
        let sentences = content
            .split(whereSeparator: { ".?!".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let sentence = sentences.first(where: { sentence in
            let lowercased = sentence.lowercased()
            return tokens.contains { lowercased.contains($0) }
        }) {
            return sentence
        }

        return String(content.prefix(240))
    }
}
