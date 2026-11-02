// AgentErrorCauseFactory.swift
// Swarm Framework
//
// Single inference-path factory mapping failure causes to AgentError.

import Foundation

/// Maps inference-path failure causes onto ``AgentError``.
///
/// This is the inference-path counterpart to the turn-path ``ToolFailureCause``
/// factory: provider adapters keep their per-adapter cause tables local and
/// route shared mechanics through this factory so the derivations cannot drift:
///
/// - ``FoundationModelsErrorMapping`` — typed OS 26/27 arms plus its
///   string-fallback cause table.
/// - ``OpenAICompatibleErrorMapper`` — its HTTP status cause table.
/// - ``InferenceRetryability`` — its retryable `URLError` code table.
///
/// Shared mechanics owned here:
///
/// - ``cancelledIfApplicable(_:)`` — every adapter maps `CancellationError` to
///   `.cancelled` before consulting its table.
/// - ``retryAfter(fromResetDate:)`` / ``rateLimitExceeded(resetDate:)`` — one
///   reset-date→delay derivation for every rate-limit arm.
/// - ``retryAfter(fromHeaders:)`` — one `Retry-After` header parser (delay
///   seconds or HTTP-date).
/// - ``descriptionMatches(_:needles:)`` — one case-insensitive description
///   matcher for string-fallback cause rows.
///
/// Direct `AgentError` construction stays at the adapter call sites; only the
/// shared derivations live here.
enum AgentErrorCauseFactory: Sendable {
    /// Returns `.cancelled` when `cause` is cooperative cancellation.
    ///
    /// Returns `nil` otherwise so callers fall through to their cause table.
    static func cancelledIfApplicable(_ cause: any Error) -> AgentError? {
        cause is CancellationError ? .cancelled : nil
    }

    /// Derives a non-negative retry delay from a provider reset date.
    ///
    /// Returns `nil` when the provider named no date; clamps past dates to zero.
    static func retryAfter(fromResetDate resetDate: Date?) -> TimeInterval? {
        resetDate.map { max(0, $0.timeIntervalSinceNow) }
    }

    /// Builds `.rateLimitExceeded` from a provider reset date.
    static func rateLimitExceeded(resetDate: Date?) -> AgentError {
        .rateLimitExceeded(retryAfter: retryAfter(fromResetDate: resetDate))
    }

    /// Parses a `Retry-After` header value (delay seconds or HTTP-date).
    ///
    /// Returns `nil` when the header is missing or unparsable; clamps past
    /// dates and negative delays to zero.
    static func retryAfter(fromHeaders headers: [AnyHashable: Any]) -> TimeInterval? {
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

    /// Returns whether the cause description contains any needle.
    ///
    /// Matches against `"\(cause.localizedDescription) \(String(describing: cause))"`,
    /// lowercased. Needles must already be lowercase.
    static func descriptionMatches(_ cause: any Error, needles: [String]) -> Bool {
        let text = "\(cause.localizedDescription) \(String(describing: cause))".lowercased()
        return needles.contains { text.contains($0) }
    }

    private static let retryAfterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}
