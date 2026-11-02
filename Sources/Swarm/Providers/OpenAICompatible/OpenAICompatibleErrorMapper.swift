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

        // 429 carries header-derived retry state; 404 names the model instead of
        // the message. Both bypass the label table below.
        if statusCode == 429 {
            if code == "insufficient_quota" {
                return .invalidInput(reason: "OpenAI-compatible quota exhausted (429 insufficient_quota): \(message). Check plan and billing details.")
            }
            return .rateLimitExceeded(retryAfter: AgentErrorCauseFactory.retryAfter(fromHeaders: headers))
        }
        if statusCode == 404 {
            return .modelNotAvailable(model: model)
        }
        if let cause = statusCauseTable[statusCode]
            ?? statusRangeCauseTable.first(where: { $0.range.contains(statusCode) })?.cause
        {
            return cause.make(statusCode: statusCode, message: message)
        }
        return .generationFailed(reason: "OpenAI-compatible HTTP \(statusCode): \(message)")
    }

    /// One row of the status→`AgentError` cause table.
    ///
    /// Every row renders `OpenAI-compatible {label} ({code}): {message}`,
    /// plus a billing suffix for payment rows.
    private struct StatusCause: Sendable {
        enum Kind: Sendable {
            case invalidInput
            case authenticationFailed
            case generationFailed
        }

        let kind: Kind
        let label: String
        let mentionsBilling: Bool

        init(kind: Kind, label: String, mentionsBilling: Bool = false) {
            self.kind = kind
            self.label = label
            self.mentionsBilling = mentionsBilling
        }

        func make(statusCode: Int, message: String) -> AgentError {
            var text = "OpenAI-compatible \(label) (\(statusCode)): \(message)"
            if mentionsBilling {
                text += ". Check plan and billing details."
            }
            switch kind {
            case .invalidInput:
                return .invalidInput(reason: text)
            case .authenticationFailed:
                return .authenticationFailed(reason: text)
            case .generationFailed:
                return .generationFailed(reason: text)
            }
        }
    }

    /// Exact-status cause rows.
    private static let statusCauseTable: [Int: StatusCause] = [
        400: StatusCause(kind: .invalidInput, label: "request rejected"),
        401: StatusCause(kind: .authenticationFailed, label: "authentication failed"),
        402: StatusCause(kind: .invalidInput, label: "payment required", mentionsBilling: true),
        403: StatusCause(kind: .authenticationFailed, label: "request forbidden"),
        408: StatusCause(kind: .generationFailed, label: "request timed out"),
        413: StatusCause(kind: .invalidInput, label: "payload too large"),
    ]

    /// Range-fallback cause rows, consulted after the exact-status table.
    private static let statusRangeCauseTable: [(range: Range<Int>, cause: StatusCause)] = [
        (500 ..< 600, StatusCause(kind: .generationFailed, label: "server error")),
        (400 ..< 500, StatusCause(kind: .invalidInput, label: "client error")),
    ]

    static func mapTransport(_ error: Error) -> Error {
        if error is AgentError {
            return error
        }
        if let cancelled = AgentErrorCauseFactory.cancelledIfApplicable(error) {
            return cancelled
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
