import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models quota limit")
struct FoundationModelsQuotaLimitTests {
    @Test("Quota needles match; unrelated text does not")
    func needleTable() {
        for needle in FoundationModelsQuotaLimit.needles {
            #expect(
                FoundationModelsQuotaLimit.stringMatches(FakeError("host wrapper: \(needle)!")),
                "needle \(needle)"
            )
            #expect(
                FoundationModelsQuotaLimit.stringMatches(FakeError("HOST: \(needle.uppercased())")),
                "needle \(needle) matches case-insensitively"
            )
        }
        #expect(FoundationModelsQuotaLimit.stringMatches(FakeError("boom")) == false)
        #expect(FoundationModelsQuotaLimit.stringMatches(FakeError("")) == false)
    }

    #if canImport(FoundationModels)
    @Test("Quota host strings map onto rateLimitExceeded without retryAfter")
    func quotaStringsMap() {
        for needle in FoundationModelsQuotaLimit.needles {
            let mapped = FoundationModelsErrorMapping.map(FakeError("host: \(needle)"))
            guard case .rateLimitExceeded(let retryAfter) = mapped else {
                Issue.record("expected rateLimitExceeded for needle \(needle), got \(mapped)")
                continue
            }
            #expect(retryAfter == nil)
        }
    }

    @Test("Context row precedes quota row in the string-fallback table")
    func contextPrecedesQuota() {
        let mapped = FoundationModelsErrorMapping.map(FakeError("exceeded context window; quota limit reached"))
        guard case .contextWindowExceeded = mapped else {
            Issue.record("expected contextWindowExceeded, got \(mapped)")
            return
        }
    }

    @Test("CancellationError maps to cancelled before the cause table")
    func cancellationMapsFirst() {
        #expect(FoundationModelsErrorMapping.map(CancellationError()) == .cancelled)
    }

    @Test("Unknown descriptions fall through to generationFailed")
    func unknownDescriptionsFallThrough() {
        let mapped = FoundationModelsErrorMapping.map(FakeError("plain host boom"))
        guard case let .generationFailed(reason) = mapped else {
            Issue.record("expected generationFailed, got \(mapped)")
            return
        }
        #expect(reason.contains("plain host boom"))
    }
    #endif

    private struct FakeError: Error, LocalizedError {
        let errorDescription: String?

        init(_ description: String) {
            errorDescription = description
        }
    }
}
