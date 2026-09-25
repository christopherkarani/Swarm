// SecretRedaction.swift
// Swarm Framework
//
// Helpers that keep secrets out of logs and debug output.

import Foundation

/// Helpers that keep secrets out of logs and debug output.
///
/// Configuration debug descriptions use ``redactedSensitiveValues(_:)`` so `print`
/// and log SDKs never capture API keys, and ``redactingKnownSecrets(in:secrets:)``
/// scrubs resolved secret values from free-form text before it is logged.
public enum SecretRedaction: Sendable {
    /// Placeholder substituted for redacted values.
    public static let placeholder = "[redacted]"

    private static let sensitiveNameTokens = [
        "authorization",
        "api-key",
        "apikey",
        "api_key",
        "token",
        "secret",
        "password",
        "credential",
        "cookie",
        "auth",
        "session",
    ]

    /// Returns whether a header field or query item name carries a credential.
    ///
    /// Matches case-insensitively when the name contains one of
    /// `authorization`, `api-key`, `apikey`, `api_key`, `token`, `secret`,
    /// `password`, `credential`, `cookie`, `auth`, or `session`.
    ///
    /// - Parameter name: Header field or query item name.
    /// - Returns: `true` when the value must be treated as a secret.
    public static func isSensitiveName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return sensitiveNameTokens.contains { lowercased.contains($0) }
    }

    /// Returns `values` with sensitive entries replaced by ``placeholder``.
    ///
    /// Names such as `Content-Type` or `api-version` keep their values so
    /// debug output stays useful; only ``isSensitiveName(_:)`` matches are
    /// redacted.
    ///
    /// - Parameter values: Header or query item mapping.
    /// - Returns: Mapping with the same keys and sensitive values redacted.
    public static func redactedSensitiveValues(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { redacted, element in
            redacted[element.key] = isSensitiveName(element.key) ? placeholder : element.value
        }
    }

    /// Replaces every occurrence of a known secret in `text` with ``placeholder``.
    ///
    /// Empty and `nil` entries are ignored so callers can pass optional
    /// credentials directly. Matching is a literal substring search.
    ///
    /// - Parameters:
    ///   - text: Free-form text that may embed secret values.
    ///   - secrets: Secret values to scrub.
    /// - Returns: `text` with each non-empty secret replaced.
    public static func redactingKnownSecrets(in text: String, secrets: [String?]) -> String {
        var scrubbed = text
        for secret in secrets {
            guard let secret, !secret.isEmpty else { continue }
            scrubbed = scrubbed.replacingOccurrences(of: secret, with: placeholder)
        }
        return scrubbed
    }
}
