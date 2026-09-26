// TraceRedactorTests.swift
// SwarmTests
//
// Tests for value-level PII scrubbing.

import Foundation
@testable import Swarm
import Testing

@Suite("TraceRedactor")
struct TraceRedactorTests {
    @Test("Email addresses are redacted")
    func emailIsRedacted() {
        #expect(TraceRedactor().redact("call alice@example.com today") == "call [email] today")
    }

    @Test("Phone numbers are redacted")
    func phoneIsRedacted() {
        #expect(TraceRedactor().redact("call 415-555-0199 now") == "call [phone] now")
        #expect(TraceRedactor().redact("call +1 (415) 555-0199 now") == "call [phone] now")
    }

    @Test("SSNs are redacted")
    func ssnIsRedacted() {
        #expect(TraceRedactor().redact("SSN 123-45-6789 here") == "SSN [ssn] here")
    }

    @Test("API keys are redacted")
    func apiKeysAreRedacted() {
        #expect(TraceRedactor().redact("key sk-abc123XYZ789") == "key [api-key]")
        #expect(TraceRedactor().redact("key AIzaSyD_r1pX_qGQI8") == "key [api-key]")
    }

    @Test("Labeled secrets keep the label")
    func labeledSecretsKeepLabel() {
        #expect(TraceRedactor().redact("token: hunter2 ok") == "token=[redacted] ok")
        #expect(TraceRedactor().redact("api_key=sk-abc ok") == "api_key=[redacted] ok")
    }

    @Test("Ordinary text is untouched")
    func ordinaryTextUntouched() {
        let redactor = TraceRedactor()
        #expect(redactor.redact("Rate limit exceeded, retry after 6 seconds") == "Rate limit exceeded, retry after 6 seconds")
        #expect(redactor.redact("version 1.2.3 built") == "version 1.2.3 built")
        #expect(redactor.redact("2026-09-24T23:01:02Z") == "2026-09-24T23:01:02Z")
        #expect(redactor.redact("token count: 5") == "token count: 5")
        #expect(redactor.redact("") == "")
    }

    @Test("Custom rules apply in order")
    func customRulesApplyInOrder() {
        let redactor = TraceRedactor(rules: [
            TraceRedactor.Rule(name: "code", pattern: "A\\d+", replacement: "[code]"),
        ])
        #expect(redactor.redact("booking A248 done") == "booking [code] done")
        // Defaults are replaced, not merged.
        #expect(redactor.redact("a@b.com") == "a@b.com")
    }

    @Test("Invalid patterns are skipped")
    func invalidPatternsSkipped() {
        let redactor = TraceRedactor(rules: [
            TraceRedactor.Rule(name: "bad", pattern: "([", replacement: "x"),
        ])
        #expect(redactor.redact("unchanged 123") == "unchanged 123")
    }

    @Test("None redactor leaves text unchanged")
    func noneLeavesTextUnchanged() {
        #expect(TraceRedactor.none.redact("a@b.com 415-555-0199") == "a@b.com 415-555-0199")
    }
}
