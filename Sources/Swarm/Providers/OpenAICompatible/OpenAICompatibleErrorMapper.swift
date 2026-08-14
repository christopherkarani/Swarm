// OpenAICompatibleErrorMapper.swift
// Swarm Framework
//
// HTTP status + error body → AgentError with Chunk J retryability.

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Maps OpenAI-compatible HTTP failures onto ``AgentError`` so
/// ``InferenceRetryability`` matches Chunk J's table:
/// 429 / 5xx / network are retryable; 400 / 401 / 403 are not.
enum OpenAICompatibleErrorMapper: Sendable {
    static func map(
        statusCode: Int,
        body: Data,
        headers: [AnyHashable: Any],
        model: String
    ) -> AgentError {
        let message = extractMessage(from: body)
        let code = extractErrorCode(from: body)

        if code == "context_length_exceeded" || message.localizedCaseInsensitiveContains("context length") {
            return .contextWindowExceeded(tokenCount: 0, limit: 0)
        }

        if code == "content_filter" || statusCode == 451 {
            return .contentFiltered(reason: message)
        }

        switch statusCode {
        case 429:
            return .rateLimitExceeded(retryAfter: parseRetryAfter(headers))
        case 400:
            return .invalidInput(reason: "OpenAI-compatible request rejected (400): \(message)")
        case 401:
            return .invalidInput(reason: "OpenAI-compatible authentication failed (401): \(message)")
        case 403:
            return .invalidInput(reason: "OpenAI-compatible request forbidden (403): \(message)")
        case 404:
            return .modelNotAvailable(model: model)
        case 408:
            return .generationFailed(reason: "OpenAI-compatible request timed out (408): \(message)")
        case 413:
            return .invalidInput(reason: "OpenAI-compatible payload too large (413): \(message)")
        case 500 ... 599:
            return .generationFailed(reason: "OpenAI-compatible server error (\(statusCode)): \(message)")
        default:
            if (400 ..< 500).contains(statusCode) {
                return .invalidInput(reason: "OpenAI-compatible client error (\(statusCode)): \(message)")
            }
            return .generationFailed(reason: "OpenAI-compatible HTTP \(statusCode): \(message)")
        }
    }

    static func mapTransport(_ error: Error) -> Error {
        if error is AgentError {
            return error
        }
        if error is CancellationError {
            return AgentError.cancelled
        }
        if error is URLError {
            return error
        }
        return AgentError.generationFailed(reason: String(describing: error))
    }

    static func extractMessage(from body: Data) -> String {
        guard !body.isEmpty else {
            return "empty error body"
        }
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    return message
                }
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }
        return String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "unreadable error body"
    }

    private static func extractErrorCode(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        if let code = error["code"] as? String {
            return code
        }
        if let type = error["type"] as? String {
            return type
        }
        return nil
    }

    private static func parseRetryAfter(_ headers: [AnyHashable: Any]) -> TimeInterval? {
        let value = headers.first { key, _ in
            String(describing: key).caseInsensitiveCompare("Retry-After") == .orderedSame
        }?.value
        guard let raw = value as? String ?? (value as? NSNumber).map(String.init(describing:)) else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return seconds
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
