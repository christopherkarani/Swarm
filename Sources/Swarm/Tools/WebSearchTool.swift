// WebSearchTool.swift
// Swarm Framework
//
// A tool for performing web searches using the Tavily API.

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A tool that performs web searches using the Tavily Search API.
///
/// Requires a valid Tavily API key from https://tavily.com
///
/// Example:
/// ```swift
/// let searchTool = WebSearchTool(apiKey: "tvly-...")
/// let result = try await searchTool.execute(arguments: ["query": "latest Swift news"])
/// ```
@Tool("Performs a web search to find information on a topic.")
public struct WebSearchTool {
    // MARK: - Parameters
    
    @Parameter("The search query or topic to find information about")
    var query: String
    
    @Parameter("Maximum number of results to return", default: 5)
    var maxResults: Int = 5
    
    @Parameter("Whether to include the raw content of the pages", default: false)
    var includeRawContent: Bool = false
    
    // MARK: - Properties
    
    private let apiKey: String
    private let decoder = JSONDecoder()
    
    // MARK: - API Response Types
    
    private struct TavilyResponse: Decodable {
        let results: [TavilyResult]
    }
    
    private struct TavilyResult: Decodable {
        let title: String
        let url: String
        let content: String
        let score: Double
    }
    
    // MARK: - Initialization
    
    /// Creates a new web search tool.
    ///
    /// - Parameter apiKey: Your Tavily API key.
    public init(apiKey: String) {
        // Initialize @Parameter properties with defaults
        self.query = ""
        self.maxResults = 5
        self.includeRawContent = false
        
        self.apiKey = apiKey
    }
    
    // MARK: - Execution
    
    /// Executes the web search using the Tavily API.
    ///
    /// Validates the query, makes the API request, and formats the results.
    ///
    /// - Returns: A formatted string containing search results with titles, URLs, and snippets.
    /// - Throws: `AgentError.toolExecutionFailed` if the API request fails or returns an error.
    /// - Throws: `AgentError.invalidToolArguments` if the query is too long (exceeds 2000 characters).
    public func execute() async throws -> String {
        guard !apiKey.isEmpty else {
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Missing API Key. Initialize WebSearchTool with a valid Tavily API key."
            )
        }

        // Validate query length to prevent abuse
        guard query.count <= 2000 else {
            throw AgentError.invalidToolArguments(
                toolName: "websearch",
                reason: "Query too long (max 2000 characters)"
            )
        }
        
        // Prepare URL
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Invalid API URL"
            )
        }
        
        // Prepare Request Body
        let body: [String: Any?] = [
            "api_key": apiKey,
            "query": query,
            "max_results": maxResults,
            "include_raw_content": includeRawContent,
            "search_depth": "ultra-fast"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // 30 second timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })
        
        // Execute Request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Invalid response type"
            )
        }
        
        guard httpResponse.statusCode == 200 else {
            // Log details internally, expose only status code to caller
            let errorDetail = String(data: data, encoding: .utf8) ?? "<no body>"
            Log.agents.error("WebSearchTool API error (HTTP \(httpResponse.statusCode)): \(errorDetail.prefix(500))")
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "API request failed (HTTP \(httpResponse.statusCode))"
            )
        }
        
        // Parse Response
        do {
            let tavilyResponse = try decoder.decode(TavilyResponse.self, from: data)
            return formatResponse(tavilyResponse)
        } catch {
            throw AgentError.toolExecutionFailed(
                toolName: "websearch",
                underlyingError: "Failed to parse API response: \(error.localizedDescription)"
            )
        }
    }
    
    private func formatResponse(_ response: TavilyResponse) -> String {
        guard !response.results.isEmpty else {
            return "No results found for '\(query)'."
        }
        
        var output = "Found \(response.results.count) results for '\(query)':\n\n"
        
        for (index, result) in response.results.enumerated() {
            output += "\(index + 1). [\(result.title)](\(result.url))\n"
            output += "   \(result.content)\n\n"
        }
        
        return output
    }
}
