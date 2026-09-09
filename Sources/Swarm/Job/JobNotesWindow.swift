import Foundation

/// Pure notes-window policy. Stores hold records; only this type truncates.
enum JobNotesWindow: Sendable {
    static func render(
        records: [JobRecord],
        query: String,
        tokenLimit: Int,
        tokenEstimator: some TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        guard tokenLimit > 0 else { return "" }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return "" }

        let matches = records.filter { record in
            record.kind.range(of: needle, options: .caseInsensitive) != nil
                || record.text.range(of: needle, options: .caseInsensitive) != nil
        }
        guard !matches.isEmpty else { return "" }

        var pieces: [String] = []
        for record in matches {
            let line = "\(record.kind): \(record.text)"
            let candidate = pieces.isEmpty ? line : pieces.joined(separator: "\n") + "\n" + line
            if tokenEstimator.estimateTokens(for: candidate) <= tokenLimit {
                pieces.append(line)
                continue
            }
            if pieces.isEmpty {
                let maxChars = tokenLimit * 4
                return String(line.prefix(maxChars))
            }
            break
        }
        return pieces.joined(separator: "\n")
    }
}
