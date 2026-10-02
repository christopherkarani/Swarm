import Foundation
@testable import Swarm
import Testing

@Suite("Foundation Models context overflow")
struct FoundationModelsContextOverflowTests {
    @Test("Overflow needles match; unrelated text does not")
    func needleTable() {
        for needle in FoundationModelsContextOverflow.needles {
            #expect(
                FoundationModelsContextOverflow.matches(FakeError("host wrapper: \(needle)!")),
                "needle \(needle)"
            )
            #expect(
                FoundationModelsContextOverflow.matches(FakeError("HOST: \(needle.uppercased())")),
                "needle \(needle) matches case-insensitively"
            )
        }
        #expect(FoundationModelsContextOverflow.matches(FakeError("boom")) == false)
        #expect(FoundationModelsContextOverflow.matches(FakeError("")) == false)
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
