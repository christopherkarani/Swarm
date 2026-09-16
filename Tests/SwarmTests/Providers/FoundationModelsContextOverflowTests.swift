import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models context overflow")
struct FoundationModelsContextOverflowTests {
    @Test func matchesAppleContextSizeExceeded() {
        #expect(FoundationModelsContextOverflow.matches(FakeError("model context size exceeded")))
        #expect(FoundationModelsContextOverflow.matches(FakeError("ExceededContextWindowSize")))
        #expect(FoundationModelsContextOverflow.matches(FakeError("boom")) == false)
    }

    @Test func mapsOverflowToContextWindowExceeded() {
        let error = FoundationModelsContextOverflow.map(FakeError("model context size exceeded"))
        guard case .contextWindowExceeded = error else {
            Issue.record("expected contextWindowExceeded, got \(error)")
            return
        }
    }

    private struct FakeError: Error, LocalizedError {
        let errorDescription: String?

        init(_ description: String) {
            errorDescription = description
        }
    }
}
