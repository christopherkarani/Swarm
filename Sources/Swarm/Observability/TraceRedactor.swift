// TraceRedactor.swift
// Swarm Framework
//
// Value-level PII scrubbing for text destined for logs.

import Foundation

/// Scrubs sensitive values from text destined for logs.
///
/// `TraceRedactor` complements Swarm's coarse trace redaction (which
/// replaces whole fields with `[redacted]`): it keeps the surrounding
/// text readable while replacing emails, phone numbers, API keys, and
/// other secret-shaped values with placeholders. Use it for any
/// application-level logging of transcripts, prompts, or errors.
///
/// ```swift
/// let redactor = TraceRedactor()
/// Log.agents.info("\(redactor.redact("call alice@example.com"))")
/// // "call [email]"
/// ```
///
/// Patterns are ICU regular expressions; replacements support `$1`-style
/// backreferences. Rules with invalid patterns are skipped, so redaction
/// never breaks logging.
public struct TraceRedactor: Sendable {
    /// One named find-and-replace rule.
    public struct Rule: Sendable, Equatable {
        /// Human-readable rule name, used for debugging only.
        public let name: String

        /// ICU regular-expression pattern.
        public let pattern: String

        /// Replacement template (`$1`-style backreferences allowed).
        public let replacement: String

        /// Creates a redaction rule.
        public init(name: String, pattern: String, replacement: String) {
            self.name = name
            self.pattern = pattern
            self.replacement = replacement
        }

        /// Conservative defaults: email, phone, SSN, API keys, labeled secrets.
        ///
        /// The phone rule requires separator grouping (it will not match
        /// bare digit runs like timestamps or token counts); extend
        /// ``TraceRedactor/init(rules:)`` with custom rules for other
        /// formats.
        public static var defaults: [Rule] {
            [
                Rule(
                    name: "email",
                    pattern: "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}",
                    replacement: "[email]"
                ),
                Rule(
                    name: "phone",
                    pattern: "(\\+\\d{1,3}[-. ]?)?\\(?\\d{3}\\)?[-. ]\\d{3}[-. ]\\d{4}",
                    replacement: "[phone]"
                ),
                Rule(
                    name: "ssn",
                    pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b",
                    replacement: "[ssn]"
                ),
                Rule(
                    name: "openai-key",
                    pattern: "\\bsk-[A-Za-z0-9]{8,}\\b",
                    replacement: "[api-key]"
                ),
                Rule(
                    name: "google-key",
                    pattern: "\\bAIza[A-Za-z0-9_-]{10,}\\b",
                    replacement: "[api-key]"
                ),
                Rule(
                    name: "labeled-secret",
                    pattern: "(?i)\\b(api[_-]?key|secret|token|password|passwd|pwd|bearer)\\b\\s*[:=]\\s*([^\\s,;]+)",
                    replacement: "$1=[redacted]"
                ),
            ]
        }
    }

    /// A redactor that leaves all text unchanged.
    public static let none = TraceRedactor(rules: [])

    /// Rules applied in order by ``redact(_:)``.
    public let rules: [Rule]

    /// Creates a redactor.
    ///
    /// - Parameter rules: Rules applied in order. Default: ``Rule/defaults``.
    public init(rules: [Rule] = Rule.defaults) {
        self.rules = rules
    }

    /// Returns `text` with every rule applied in order.
    public func redact(_ text: String) -> String {
        guard !text.isEmpty, !rules.isEmpty else {
            return text
        }
        return rules.reduce(text) { current, rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else {
                return current
            }
            let range = NSRange(current.startIndex..., in: current)
            return regex.stringByReplacingMatches(
                in: current,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
    }
}
