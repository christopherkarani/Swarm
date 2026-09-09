import Testing
@testable import Swarm

@Suite("StoreBackedComposition Job notes window")
struct StoreBackedCompositionJobNotesWindowTests {
    @Test("empty query returns empty text")
    func emptyQueryReturnsEmptyText() {
        let text = JobNotesWindow.render(
            records: [JobRecord(kind: "note", text: "alpha body")],
            query: "",
            tokenLimit: 100
        )
        #expect(text == "")
    }

    @Test("matching query returns kind and text")
    func matchingQueryReturnsKindAndText() {
        let text = JobNotesWindow.render(
            records: [JobRecord(kind: "note", text: "alpha body")],
            query: "alpha",
            tokenLimit: 100
        )
        #expect(text == "note: alpha body")
    }

    @Test("oversized first match is truncated to the token budget")
    func oversizedFirstMatchIsTruncated() {
        let text = JobNotesWindow.render(
            records: [JobRecord(kind: "note", text: "alpha body")],
            query: "alpha",
            tokenLimit: 1
        )
        #expect(text == "note")
    }

    @Test("later matches are dropped when the budget is already full")
    func laterMatchesDroppedWhenBudgetFull() {
        let records = [
            JobRecord(kind: "note", text: "alpha first"),
            JobRecord(kind: "note", text: "alpha second"),
        ]
        let text = JobNotesWindow.render(records: records, query: "alpha", tokenLimit: 4)
        #expect(text == "note: alpha first")
        #expect(text.contains("second") == false)
    }

    @Test("query isolates matching records")
    func queryIsolatesMatchingRecords() {
        let records = [
            JobRecord(kind: "note", text: "alpha body"),
            JobRecord(kind: "note", text: "beta body"),
        ]
        let alpha = JobNotesWindow.render(records: records, query: "alpha", tokenLimit: 400)
        let beta = JobNotesWindow.render(records: records, query: "beta", tokenLimit: 400)
        #expect(alpha.contains("alpha body"))
        #expect(alpha.contains("beta body") == false)
        #expect(beta.contains("beta body"))
        #expect(beta.contains("alpha body") == false)
    }
}
