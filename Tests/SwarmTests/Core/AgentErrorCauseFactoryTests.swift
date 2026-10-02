import Foundation
import Testing
@testable import Swarm

@Suite("AgentError cause factory")
struct AgentErrorCauseFactoryTests {
    @Test("CancellationError maps to cancelled; other errors fall through")
    func cancellationGuard() {
        struct Boom: Error {}
        #expect(AgentErrorCauseFactory.cancelledIfApplicable(CancellationError()) == .cancelled)
        #expect(AgentErrorCauseFactory.cancelledIfApplicable(Boom()) == nil)
        #expect(AgentErrorCauseFactory.cancelledIfApplicable(URLError(.timedOut)) == nil)
        #expect(AgentErrorCauseFactory.cancelledIfApplicable(AgentError.generationFailed(reason: "x")) == nil)
    }

    @Test("Reset-date delays clamp the past and preserve nil")
    func resetDateDelayTable() {
        #expect(AgentErrorCauseFactory.retryAfter(fromResetDate: nil) == nil)
        #expect(AgentErrorCauseFactory.retryAfter(fromResetDate: Date().addingTimeInterval(-60)) == 0)
        #expect(AgentErrorCauseFactory.retryAfter(fromResetDate: Date()) ?? -1 >= 0)
        let delay = AgentErrorCauseFactory.retryAfter(fromResetDate: Date().addingTimeInterval(60))
        #expect(delay != nil)
        #expect(delay ?? -1 > 0)
        #expect(delay ?? 999 <= 60)
    }

    @Test("Reset-date rate limits build through the shared derivation")
    func rateLimitFromResetDate() {
        #expect(AgentErrorCauseFactory.rateLimitExceeded(resetDate: nil) == .rateLimitExceeded(retryAfter: nil))
        let mapped = AgentErrorCauseFactory.rateLimitExceeded(resetDate: Date().addingTimeInterval(30))
        guard case let .rateLimitExceeded(delay) = mapped else {
            Issue.record("expected rateLimitExceeded, got \(mapped)")
            return
        }
        #expect(delay != nil)
        #expect(delay ?? -1 > 0)
        #expect(delay ?? 999 <= 30)
    }

    @Test("Retry-After header table parses seconds and failures")
    func retryAfterHeaderTable() {
        let rows: [(headers: [String: String], expected: TimeInterval?)] = [
            (["Retry-After": "2"], 2),
            (["Retry-After": "0"], 0),
            (["Retry-After": "-5"], 0),
            (["Retry-After": "  3  "], 3),
            (["retry-after": "4"], 4),
            (["RETRY-AFTER": "5"], 5),
            (["Retry-After": "soon"], nil),
            (["Retry-After": ""], nil),
            (["Retry-After": "   "], nil),
            ([:], nil),
            (["Other": "7"], nil),
        ]
        for row in rows {
            #expect(
                AgentErrorCauseFactory.retryAfter(fromHeaders: row.headers) == row.expected,
                "headers \(row.headers) should parse to \(String(describing: row.expected))"
            )
        }
        #expect(AgentErrorCauseFactory.retryAfter(fromHeaders: ["Retry-After": NSNumber(value: 6)]) == 6)
    }

    @Test("Retry-After HTTP dates map to a positive bounded delay")
    func retryAfterHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let delay = AgentErrorCauseFactory.retryAfter(fromHeaders: [
            "Retry-After": formatter.string(from: Date().addingTimeInterval(30)),
        ])
        #expect(delay != nil)
        #expect(delay ?? -1 > 0)
        #expect(delay ?? 999 <= 30)
        let past = AgentErrorCauseFactory.retryAfter(fromHeaders: [
            "Retry-After": formatter.string(from: Date().addingTimeInterval(-30)),
        ])
        #expect(past == 0)
    }

    @Test("Description matching is case-insensitive over message and type")
    func descriptionMatchingTable() {
        struct Boom: Error, LocalizedError {
            let errorDescription: String?
        }
        let rows: [(description: String, needles: [String], expected: Bool)] = [
            ("Model CONTEXT SIZE EXCEEDED on device", ["context size exceeded"], true),
            ("quotaLimitReached", ["quotalimitreached"], true),
            ("Usage Limit Reached for today", ["usage limit reached"], true),
            ("plain boom", ["quota limit"], false),
            ("plain boom", [], false),
        ]
        for row in rows {
            #expect(
                AgentErrorCauseFactory.descriptionMatches(
                    Boom(errorDescription: row.description),
                    needles: row.needles
                ) == row.expected,
                "description \(row.description) with needles \(row.needles)"
            )
        }
        struct QuotaLimitBlowup: Error {}
        #expect(AgentErrorCauseFactory.descriptionMatches(QuotaLimitBlowup(), needles: ["quotalimit"]))
    }
}
