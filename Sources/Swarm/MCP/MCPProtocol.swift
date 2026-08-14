// MCPProtocol.swift
// Swarm Framework
//
// JSON-RPC 2.0 request/response types for Model Context Protocol (MCP) operations.

import Foundation

// MARK: - MCPRequest

/// A JSON-RPC 2.0 request object for MCP operations.
///
/// This struct represents a JSON-RPC 2.0 compliant request that can be sent
/// to an MCP server. Every request includes the protocol version, a unique
/// identifier, the method to invoke, and optional parameters.
///
/// ## JSON-RPC 2.0 Compliance
/// - `jsonrpc` is always "2.0"
/// - `id` uniquely identifies the request for correlating responses
/// - `method` specifies the remote procedure to call
/// - `params` contains optional structured arguments
///
/// ## Example Usage
/// ```swift
/// // Simple request without parameters
/// let request = try MCPRequest(method: "tools/list")
///
/// // Request with parameters
/// let callRequest = try MCPRequest(
///     method: "tools/call",
///     params: [
///         "name": .string("calculator"),
///         "arguments": .dictionary(["expression": .string("2 + 2")])
///     ]
/// )
///
/// // Request with custom ID
/// let customRequest = try MCPRequest(
///     id: "request-001",
///     method: "resources/read",
///     params: ["uri": .string("file:///example.txt")]
/// )
/// ```
package struct MCPRequest: Sendable, Codable, Equatable {
    // MARK: Package

    /// The JSON-RPC protocol version. Always "2.0".
    package let jsonrpc: String

    /// A unique identifier for this request.
    ///
    /// Used to correlate responses with their corresponding requests.
    /// Defaults to a new UUID string if not specified.
    package let id: String

    /// The name of the method to invoke.
    ///
    /// MCP defines standard methods such as:
    /// - `initialize` - Initialize the connection
    /// - `tools/list` - List available tools
    /// - `tools/call` - Execute a tool
    /// - `resources/list` - List available resources
    /// - `resources/read` - Read a resource
    /// - `prompts/list` - List available prompts
    /// - `prompts/get` - Get a prompt
    package let method: String

    /// Optional parameters for the method.
    ///
    /// The structure of parameters depends on the method being called.
    /// Use `nil` for methods that do not require parameters.
    package let params: [String: SendableValue]?

    // MARK: - Initialization

    /// Creates a new JSON-RPC 2.0 request.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for the request. Defaults to a new UUID string.
    ///         An empty string is replaced with a fresh UUID automatically.
    ///   - method: The name of the method to invoke. Must be non-empty.
    ///   - params: Optional parameters for the method. Defaults to `nil`.
    /// - Throws: `MCPError.invalidRequest` if `method` is empty.
    package init(
        id: String = UUID().uuidString,
        method: String,
        params: [String: SendableValue]? = nil
    ) throws {
        // Validate id — generate a fresh UUID if caller passed empty string.
        let validatedId = id.isEmpty ? UUID().uuidString : id

        // Validate method — empty method is invalid per JSON-RPC 2.0.
        guard !method.isEmpty else {
            throw MCPError.invalidRequest("MCPRequest: method must be non-empty per JSON-RPC 2.0")
        }

        jsonrpc = "2.0"
        self.id = validatedId
        self.method = method
        self.params = params
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Validate jsonrpc version
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == "2.0" else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.jsonrpc],
                    debugDescription: "Invalid JSON-RPC version: expected '2.0', got '\(version)'"
                )
            )
        }
        jsonrpc = version

        let decodedId = try container.decode(String.self, forKey: .id)
        guard !decodedId.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.id],
                    debugDescription: "Request ID cannot be empty"
                )
            )
        }
        id = decodedId

        let decodedMethod = try container.decode(String.self, forKey: .method)
        guard !decodedMethod.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.method],
                    debugDescription: "Method name cannot be empty"
                )
            )
        }
        method = decodedMethod

        params = try container.decodeIfPresent([String: SendableValue].self, forKey: .params)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }

    // MARK: Private

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
    }
}

// MARK: - MCPResponse

/// A JSON-RPC 2.0 response object for MCP operations.
///
/// This struct represents a JSON-RPC 2.0 compliant response received from
/// an MCP server. A response contains either a result (on success) or an
/// error (on failure), but never both.
///
/// ## JSON-RPC 2.0 Compliance
/// - `jsonrpc` is always "2.0"
/// - `id` matches the request that triggered this response
/// - `result` is present on success, absent on error
/// - `error` is present on failure, absent on success
///
/// ## Example Usage
/// ```swift
/// // Decoding a response
/// let response = try JSONDecoder().decode(MCPResponse.self, from: data)
///
/// if let error = response.error {
///     print("Error: \(error.message)")
/// } else if let result = response.result {
///     print("Success: \(result)")
/// }
/// ```
package struct MCPResponse: Sendable, Codable, Equatable {
    // MARK: Package

    /// The JSON-RPC protocol version. Always "2.0".
    package let jsonrpc: String

    /// The identifier matching the corresponding request.
    package let id: String

    /// The result of the method invocation, if successful.
    ///
    /// Present when the request was processed successfully.
    /// `nil` when an error occurred.
    package let result: SendableValue?

    /// The error object, if the request failed.
    ///
    /// Present when an error occurred during processing.
    /// `nil` when the request was successful.
    package let error: MCPErrorObject?

    // MARK: - Initialization

    /// Creates a new JSON-RPC 2.0 response.
    ///
    /// According to JSON-RPC 2.0, a response must contain either a `result`
    /// (on success) or an `error` (on failure), but not both. This initializer
    /// enforces this constraint by throwing an error.
    ///
    /// - Parameters:
    ///   - jsonrpc: The protocol version. Should always be "2.0".
    ///   - id: The identifier matching the corresponding request.
    ///   - result: The result of successful execution, or `nil` on error.
    ///   - error: The error object on failure, or `nil` on success.
    ///
    /// - Throws: `MCPError.invalidRequest` if both `result` and `error` are `nil`,
    ///   or if both are non-nil, which violates JSON-RPC 2.0 specification.
    package init(
        jsonrpc: String = "2.0",
        id: String,
        result: SendableValue? = nil,
        error: MCPErrorObject? = nil
    ) throws {
        guard jsonrpc == "2.0" else {
            throw MCPError.invalidRequest("Invalid JSON-RPC version: expected '2.0', got '\(jsonrpc)'")
        }
        guard !id.isEmpty else {
            throw MCPError.invalidRequest("Response ID cannot be empty")
        }
        guard (result == nil) != (error == nil) else {
            throw MCPError.invalidRequest(
                "MCPResponse must have exactly one of result or error set, not both or neither"
            )
        }
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }

    // MARK: - Codable

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        guard jsonrpc == "2.0" else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.jsonrpc],
                    debugDescription: "Invalid JSON-RPC version: expected '2.0', got '\(jsonrpc)'"
                )
            )
        }
        let id: String
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.id],
                    debugDescription: "Response ID must be a string or number"
                )
            )
        }
        guard !id.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.id],
                    debugDescription: "Response ID cannot be empty"
                )
            )
        }
        let result = try container.decodeIfPresent(SendableValue.self, forKey: .result)
        let error = try container.decodeIfPresent(MCPErrorObject.self, forKey: .error)

        // Validate JSON-RPC 2.0 mutual exclusivity
        guard (result == nil) != (error == nil) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "MCPResponse must have exactly one of result or error, not both or neither"
                )
            )
        }

        // Use private initializer that bypasses the throwing check
        // since we've already validated above
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }

    // MARK: Private

    /// Internal initializer for validated response construction.
    /// Callers must ensure exactly one of result or error is set.
    private init(
        id: String,
        result: SendableValue?,
        error: MCPErrorObject?
    ) {
        assert(
            (result == nil) != (error == nil),
            "MCPResponse invariant violated: exactly one of result/error must be set"
        )
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case result
        case error
    }
}

// MARK: - MCPResponse Factory Methods

package extension MCPResponse {
    /// Creates a successful response with the given result.
    ///
    /// - Parameters:
    ///   - id: The identifier matching the corresponding request. Must be non-empty.
    ///   - result: The result value to include in the response.
    /// - Returns: An MCPResponse with the result set and error as `nil`.
    ///
    /// - Throws: `MCPError.invalidRequest` when `id` is empty.
    static func success(id: String, result: SendableValue) throws -> MCPResponse {
        guard !id.isEmpty else {
            throw MCPError.invalidRequest("MCPResponse.success requires a non-empty id")
        }
        return MCPResponse(
            id: id,
            result: result,
            error: nil
        )
    }

    /// Creates an error response with the given error object.
    ///
    /// - Parameters:
    ///   - id: The identifier matching the corresponding request. Must be non-empty.
    ///   - error: The error object describing what went wrong.
    /// - Returns: An MCPResponse with the error set and result as `nil`.
    ///
    /// - Throws: `MCPError.invalidRequest` when `id` is empty.
    static func failure(id: String, error: MCPErrorObject) throws -> MCPResponse {
        guard !id.isEmpty else {
            throw MCPError.invalidRequest("MCPResponse.failure requires a non-empty id")
        }
        return MCPResponse(
            id: id,
            result: nil,
            error: error
        )
    }
}

// MARK: - MCPErrorObject

/// A JSON-RPC 2.0 error object for MCP responses.
///
/// This struct represents the error object within a JSON-RPC 2.0 response.
/// It contains a numeric error code, a human-readable message, and optional
/// additional data about the error.
///
/// ## Standard Error Codes
/// The following error codes are defined by JSON-RPC 2.0:
/// - `-32700`: Parse error - Invalid JSON was received
/// - `-32600`: Invalid Request - The JSON sent is not a valid Request object
/// - `-32601`: Method not found - The method does not exist or is not available
/// - `-32602`: Invalid params - Invalid method parameter(s)
/// - `-32603`: Internal error - Internal JSON-RPC error
///
/// Server-defined errors should use codes in the range -32000 to -32099.
/// Application-defined errors should use codes outside the reserved ranges.
///
/// ## Example Usage
/// ```swift
/// // Create an error object
/// let error = MCPErrorObject(
///     code: MCPError.methodNotFoundCode,
///     message: "Method 'unknown' not found"
/// )
///
/// // Create from MCPError
/// let mcpError = MCPError.invalidParams("Missing required parameter 'name'")
/// let errorObject = MCPErrorObject.from(mcpError)
/// ```
package struct MCPErrorObject: Sendable, Codable, Equatable {
    /// The error code as defined by JSON-RPC 2.0.
    ///
    /// Standard codes are in the range -32700 to -32600.
    /// Server-defined codes are in the range -32000 to -32099.
    /// Application-defined codes should be outside these ranges.
    package let code: Int

    /// A short description of the error.
    ///
    /// This should be a concise, human-readable message describing
    /// the error condition.
    package let message: String

    /// Optional structured data containing additional information about the error.
    ///
    /// This can contain any JSON-serializable data that provides
    /// additional context about the error, such as stack traces,
    /// validation details, or retry information.
    package let data: SendableValue?

    // MARK: - Initialization

    /// Creates a new error object with the specified code, message, and optional data.
    ///
    /// - Parameters:
    ///   - code: The error code as defined by JSON-RPC 2.0.
    ///   - message: A short description of the error.
    ///   - data: Optional structured data containing additional information.
    package init(code: Int, message: String, data: SendableValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // MARK: - Factory Methods

    /// Creates an MCPErrorObject from an MCPError.
    ///
    /// This factory method converts the framework's `MCPError` type into
    /// the JSON-RPC 2.0 error object format suitable for responses.
    ///
    /// - Parameter error: The MCPError to convert.
    /// - Returns: An MCPErrorObject with the same code, message, and data.
    package static func from(_ error: MCPError) -> MCPErrorObject {
        MCPErrorObject(
            code: error.code,
            message: error.message,
            data: error.data
        )
    }
}

// MARK: MCPErrorObject.CodingKeys

extension MCPErrorObject {
    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}

// MARK: CustomDebugStringConvertible

extension MCPErrorObject: CustomDebugStringConvertible {
    package var debugDescription: String {
        if let data {
            "MCPErrorObject(code: \(code), message: \"\(message)\", data: \(data.debugDescription))"
        } else {
            "MCPErrorObject(code: \(code), message: \"\(message)\")"
        }
    }
}
