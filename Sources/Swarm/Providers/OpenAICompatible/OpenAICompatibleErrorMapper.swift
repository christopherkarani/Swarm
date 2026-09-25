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
            if code == "insufficient_quota" {
                return .invalidInput(reason: "OpenAI-compatible quota exhausted (429 insufficient_quota): \(message). Check plan and billing details.")
            }
            return .rateLimitExceeded(retryAfter: parseRetryAfter(headers))
        case 400:
            return .invalidInput(reason: "OpenAI-compatible request rejected (400): \(message)")
        case 401:
            return .authenticationFailed(reason: "OpenAI-compatible authentication failed (401): \(message)")
        case 402:
            return .invalidInput(reason: "OpenAI-compatible payment required (402): \(message). Check plan and billing details.")
        case 403:
            return .authenticationFailed(reason: "OpenAI-compatible request forbidden (403): \(message)")
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
        if let json = try? JSONSerialization.jsonObject(with: body) {
            if let object = json as? [String: Any] {
                if let message = messageFromObject(object) {
                    return message
                }
            } else if let array = json as? [Any] {
                if let message = array.lazy.compactMap(messageFromErrorValue).first {
                    return message
                }
            }
        }
        return String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "unreadable error body"
    }

    /// Extracts a message from a top-level error object.
    ///
    /// Shapes, in priority order: `{"error": {"message"}}` (OpenAI),
    /// `{"error": {"errors": [{"message"}]}}` (Google), `{"error": "…"}`,
    /// top-level `{"message"}`, then FastAPI-style `{"detail"}` / `{"details"}`.
    private static func messageFromObject(_ object: [String: Any]) -> String? {
        if let error = object["error"], let message = messageFromErrorValue(error) {
            return message
        }
        if let message = nonEmptyString(object["message"]) {
            return message
        }
        // FastAPI-style validation errors use detail (string or items).
        let detailKeys = ["detail", "details"]
        for key in detailKeys {
            let match = object.keys.first { $0.lowercased() == key }
            if let match, let message = messageFromErrorValue(object[match]) {
                return message
            }
        }
        return nil
    }

    /// Extracts a message from an `error`/`detail` value of unknown shape.
    private static func messageFromErrorValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let message = nonEmptyString(value) {
            return message
        }
        if let object = value as? [String: Any] {
            if let message = nonEmptyString(object["message"]) {
                return message
            }
            if let errors = object["errors"] as? [Any],
               let nested = errors.lazy.compactMap(messageFromErrorValue).first
            {
                return nested
            }
            // FastAPI validation items carry `msg`.
            if let message = nonEmptyString(object["msg"]) {
                return message
            }
            return nil
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap(messageFromErrorValue).first
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractErrorCode(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        if let code = error["code"] as? String, !code.isEmpty {
            return code
        }
        // Google-style numeric codes (e.g. `"code": 429`).
        if let code = error["code"] as? NSNumber {
            return code.stringValue
        }
        if let type = error["type"] as? String, !type.isEmpty {
            return type
        }
        if let status = error["status"] as? String, !status.isEmpty {
            return status
        }
        return nil
    }

    private static func parseRetryAfter(_ headers: [AnyHashable: Any]) -> TimeInterval? {
        let value = headers.first { key, _ in
            String(describing: key).caseInsensitiveCompare("Retry-After") == .orderedSame
        }?.value
        guard let raw = (value as? String ?? (value as? NSNumber).map { $0.stringValue })?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return max(0, seconds)
        }
        // HTTP-date form (RFC 9110 §13.1.1): delay until the named instant.
        if let date = Self.retryAfterDateFormatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private static let retryAfterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
