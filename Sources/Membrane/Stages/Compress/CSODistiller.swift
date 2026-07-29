import Foundation
import MembraneCore

/// Stage 3 compressor: distills older conversation turns into a bounded
/// Context State Object (CSO) while keeping recent turns verbatim.
public actor CSODistiller: CompressStage {
    private var currentCSO: ContextStateObject
    private let keepRecentTurns: Int

    public init(keepRecentTurns: Int = 3) {
        self.keepRecentTurns = max(keepRecentTurns, 0)
        self.currentCSO = ContextStateObject()
    }

    public func process(_ input: BudgetedContext, budget: ContextBudget) async throws -> CompressedContext {
        let history = input.window.history
        let originalTokens = history.reduce(0) { $0 + $1.tokenCount }

        guard history.count > keepRecentTurns else {
            return CompressedContext(
                window: input.window,
                budget: budget,
                compressionReport: CompressionReport(
                    originalTokens: originalTokens,
                    compressedTokens: originalTokens,
                    techniquesApplied: []
                )
            )
        }

        let olderTurns = Array(history.dropLast(keepRecentTurns))
        let recentTurns = Array(history.suffix(keepRecentTurns))

        let distilled = distill(turns: olderTurns.map(\.content), existing: currentCSO)
        currentCSO = distilled

        let csoSlice = ContextSlice(
            content: distilled.formatted(),
            tokenCount: distilled.estimatedTokenCount,
            importance: 0.9,
            source: .history,
            tier: .gist,
            timestamp: .now
        )

        var window = input.window
        window.history = [csoSlice] + recentTurns

        let compressedTokens = window.history.reduce(0) { $0 + $1.tokenCount }
        return CompressedContext(
            window: window,
            budget: budget,
            compressionReport: CompressionReport(
                originalTokens: originalTokens,
                compressedTokens: compressedTokens,
                techniquesApplied: ["CSO"]
            )
        )
    }

    func distill(turns: [String], existing: ContextStateObject? = nil) -> ContextStateObject {
        var cso = existing ?? ContextStateObject()

        for rawTurn in turns {
            let turn = rawTurn.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !turn.isEmpty else {
                continue
            }

            extractEntities(from: turn, into: &cso)
            extractDecisions(from: turn, into: &cso)
            extractQuestions(from: turn, into: &cso)
            extractFacts(from: turn, into: &cso)
        }

        cso.turnCount += turns.count
        cso.trimBounds()
        return cso
    }

    private func extractEntities(from turn: String, into cso: inout ContextStateObject) {
        let ignored = Set(["User", "Assistant", "The", "This", "That", "When", "Where", "What", "Why", "How", "Turn"])

        for part in turn.split(separator: " ") {
            let token = part.trimmingCharacters(in: .punctuationCharacters)
            guard token.count >= 2,
                  token.first?.isUppercase == true,
                  !ignored.contains(token),
                  !token.allSatisfy({ $0.isNumber }) else {
                continue
            }
            cso.addEntity(token)
        }
    }

    private func extractDecisions(from turn: String, into cso: inout ContextStateObject) {
        let lower = turn.lowercased()
        let markers = ["decided", "chose", "selected", "will use", "going with", "picked", "using"]
        guard markers.contains(where: { lower.contains($0) }) else {
            return
        }

        if !cso.decisions.contains(turn) {
            cso.decisions.append(turn)
        }
    }

    private func extractQuestions(from turn: String, into cso: inout ContextStateObject) {
        guard turn.contains("?") else {
            return
        }

        let fragments = turn
            .split(separator: "?")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for fragment in fragments {
            if !cso.openQuestions.contains(fragment) {
                cso.openQuestions.append(fragment)
            }
        }
    }

    private func extractFacts(from turn: String, into cso: inout ContextStateObject) {
        let markers = [" is ", " are ", " contains ", " includes "]
        guard markers.contains(where: { turn.localizedCaseInsensitiveContains($0) }) else {
            return
        }

        if !cso.keyFacts.contains(turn) {
            cso.keyFacts.append(turn)
        }
    }
}
