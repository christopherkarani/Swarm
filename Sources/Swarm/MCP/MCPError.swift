// MCPError.swift
// Swarm Framework
//
// JSON-RPC 2.0 error types for Model Context Protocol (MCP) operations.

import Foundation

// MARK: - MCPError

/// A JSON-RPC 2.0 compliant error for MCP operations.
///
/// This error type follows the JSON-RPC 2.0 specification for error objects,
/// including standard error codes and optional structured data.
///
/// ## Standard Error Codes
/// - `-32700`: Parse error - Invalid JSON was received
/// - `-32600`: Invalid Request - The JSON sent is not a valid Request object
/// - `-32601`: Method not found - The method does not exist or is not available
/// - `-32602`: Invalid params - Invalid method parameter(s)
/// - `-32603`: Internal error - Internal JSON-RPC error
///
/// ## Example Usage
/// ```swift
/// // Using static factory methods
/// let error = MCPError.methodNotFound("tool.execute")
///
/// // Custom error
/// let customError = MCPError(
///     code: -32001,
///     message: "Server unavailable",
///     data: ["retryAfter": 30]
/// )
/// ```
public struct MCPError: Error, Sendable, Equatable {
    /// The error code as defined by JSON-RPC 2.0.
    ///
    /// Standard codes are in the range -32700 to -32600.
    /// Application-defined codes should be outside this range.
    public let code: Int

    /// A short description of the error.
    ///
    /// This should be a concise, human-readable message.
    public let message: String

    /// Optional structured data containing additional information about the error.
    ///
    /// The value can be any JSON-serializable data that provides
    /// additional context about the error.
    public let data: SendableValue?

    // MARK: - Initialization

    /// Creates a new MCP error with the specified code, message, and optional data.
    ///
    /// - Parameters:
    ///   - code: The error code as defined by JSON-RPC 2.0.
    ///   - message: A short description of the error.
    ///   - data: Optional structured data containing additional information.
    public init(code: Int, message: String, data: SendableValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Standard JSON-RPC 2.0 Error Codes

public extension MCPError {
    /// Error code for parse errors (-32700).
    static let parseErrorCode: Int = -32700

    /// Error code for invalid request (-32600).
    static let invalidRequestCode: Int = -32600

    /// Error code for method not found (-32601).
    static let methodNotFoundCode: Int = -32601

    /// Error code for invalid params (-32602).
    static let invalidParamsCode: Int = -32602

    /// Error code for internal errors (-32603).
    static let internalErrorCode: Int = -32603
}

// MARK: - Factory Methods

public extension MCPError {
    /// Creates a parse error indicating invalid JSON was received.
    ///
    /// - Parameter details: Optional details about the parse failure.
    /// - Returns: An MCPError with code -32700.
    static func parseError(_ details: String? = nil) -> MCPError {
        MCPError(
            code: parseErrorCode,
            message: details ?? "Parse error: Invalid JSON was received by the server"
        )
    }

    /// Creates an invalid request error indicating the JSON is not a valid Request object.
    ///
    /// - Parameter details: Optional details about why the request is invalid.
    /// - Returns: An MCPError with code -32600.
    static func invalidRequest(_ details: String? = nil) -> MCPError {
        MCPError(
            code: invalidRequestCode,
            message: details ?? "Invalid Request: The JSON sent is not a valid Request object"
        )
    }

    /// Creates a method not found error indicating the requested method does not exist.
    ///
    /// - Parameter method: The name of the method that was not found.
    /// - Returns: An MCPError with code -32601.
    static func methodNotFound(_ method: String? = nil) -> MCPError {
        let message = if let method {
            "Method not found: '\(method)' does not exist or is not available"
        } else {
            "Method not found: The method does not exist or is not available"
        }
        return MCPError(code: methodNotFoundCode, message: message)
    }

    /// Creates an invalid params error indicating the method parameters are invalid.
    ///
    /// - Parameter details: Optional details about which parameters are invalid.
    /// - Returns: An MCPError with code -32602.
    static func invalidParams(_ details: String? = nil) -> MCPError {
        MCPError(
            code: invalidParamsCode,
            message: details ?? "Invalid params: Invalid method parameter(s)"
        )
    }

    /// Creates an internal error indicating an internal JSON-RPC error occurred.
    ///
    /// - Parameter details: Optional details about the internal error.
    /// - Returns: An MCPError with code -32603.
    static func internalError(_ details: String? = nil) -> MCPError {
        MCPError(
            code: internalErrorCode,
            message: details ?? "Internal error: Internal JSON-RPC error"
        )
    }

    /// Creates an invalid-request error for an unsupported MCP protocol version.
    ///
    /// Swarm never silently assumes compatibility with an unknown server
    /// revision. The message lists every version this client will accept.
    ///
    /// - Parameter version: The version string reported by the server, or
    ///   empty when the initialize result omitted `protocolVersion`.
    /// - Returns: An MCPError with code -32600.
    static func unsupportedProtocolVersion(_ version: String) -> MCPError {
        let reported = version.isEmpty ? "<missing>" : version
        let supported = MCPProtocolVersion.supported.sorted().joined(separator: ", ")
        return MCPError(
            code: invalidRequestCode,
            message: "Unsupported MCP protocol version '\(reported)'. Swarm supports: \(supported)."
        )
    }
}

// MARK: LocalizedError

extension MCPError: LocalizedError {
    public var errorDescription: String? {
        if let data {
            "\(message) (code: \(code), data: \(data))"
        } else {
            "\(message) (code: \(code))"
        }
    }
}

// MARK: CustomDebugStringConvertible

extension MCPError: CustomDebugStringConvertible {
    public var debugDescription: String {
        if let data {
            "MCPError(code: \(code), message: \"\(message)\", data: \(data.debugDescription))"
        } else {
            "MCPError(code: \(code), message: \"\(message)\")"
        }
    }
}

// MARK: Codable

extension MCPError: Codable {
    // MARK: Public

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        data = try container.decodeIfPresent(SendableValue.self, forKey: .data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}
