#if SWARM_INTEGRATIONS
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal struct TavilySearchBackend: Sendable {
    let configuration: WebSearchTool.Configuration
    let secretStore: (any SecretStore)?

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let title: String
        let url: String
        let content: String
        let score: Double
    }

    func search(
        query: String,
        maxResults: Int,
        domains: [String],
        recencyDays: Int?
    ) async throws -> [WebSearchHit] {
        let resolved = try await configuration.resolveAPIKey(using: secretStore)
        guard let apiKey = resolved?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            Log.agents.warning("[TavilySearchBackend] API key is empty — returning 0 hits")
            return []
        }

        Log.agents.debug("[TavilySearchBackend] POST api.tavily.com/search — query=\(redactedQuery(query)), maxResults=\(maxResults)")

        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw AgentError.toolFailure(toolName: "websearch", message: "Invalid Tavily URL", cause: nil)
        }

        var body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": max(1, maxResults),
            "search_depth": "advanced",
            "include_raw_content": false,
        ]
        if !domains.isEmpty {
            body["include_domains"] = domains
        }
        if let recencyDays {
            body["days"] = recencyDays
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.fetchTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        TraceContextHeaders.applyCurrent(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.toolFailure(toolName: "websearch", message: "Tavily returned a non-HTTP response", cause: nil)
        }
        guard http.statusCode == 200 else {
            // The body can echo the query or the API key, so the model only
            // sees the status and the log only a redacted, truncated excerpt.
            let errorBody = Self.sanitizedErrorBody(data, apiKey: apiKey)
            Log.agents.error("[TavilySearchBackend] HTTP \(http.statusCode) — \(errorBody)")
            throw AgentError.toolFailure(
                toolName: "websearch",
                message: Self.failureMessage(statusCode: http.statusCode),
                cause: nil
            )
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        Log.agents.info("[TavilySearchBackend] Decoded \(decoded.results.count) results from Tavily")
        return decoded.results.enumerated().map { index, result in
            WebSearchHit(
                id: "tavily-\(index)-\(abs(result.url.hashValue))",
                title: result.title,
                url: result.url,
                snippet: trimmedSnippet(result.content),
                score: result.score,
                source: "tavily",
                cached: false
            )
        }
    }

    /// Longest error-body excerpt written to the log.
    static let maxLoggedErrorBodyLength = 200

    /// Tool-failure text for a non-200 Tavily response: status only, never the body.
    static func failureMessage(statusCode: Int) -> String {
        let reason: String? = switch statusCode {
        case 400: "bad request"
        case 401, 403: "authentication failed"
        case 429: "rate limited"
        case 432, 433: "plan limit exceeded"
        case 500 ... 599: "server error"
        default: nil
        }
        guard let reason else {
            return "Tavily request failed (HTTP \(statusCode))"
        }
        return "Tavily request failed (HTTP \(statusCode): \(reason))"
    }

    /// A single-line, secret-redacted, truncated excerpt of an error body for logs.
    static func sanitizedErrorBody(_ data: Data, apiKey: String) -> String {
        guard !data.isEmpty else {
            return "(no body)"
        }
        guard var text = String(validating: data, as: UTF8.self) else {
            return "(\(data.count)-byte non-UTF-8 body)"
        }
        if !apiKey.isEmpty {
            text = text.replacingOccurrences(of: apiKey, with: "[api-key]")
        }
        text = text.replacingOccurrences(of: "tvly-[A-Za-z0-9_-]+", with: "[api-key]", options: .regularExpression)
        text = TraceRedactor().redact(text)
        text = String(text.map { $0.isNewline || ($0.asciiValue ?? 0x20) < 0x20 ? " " : $0 })
        guard text.count > maxLoggedErrorBodyLength else {
            return text
        }
        return String(text.prefix(maxLoggedErrorBodyLength)) + "…"
    }
}

/// A log-safe stand-in for a search query: its length, never its text.
internal func redactedQuery(_ query: String) -> String {
    "<redacted, \(query.count) chars>"
}
#endif
