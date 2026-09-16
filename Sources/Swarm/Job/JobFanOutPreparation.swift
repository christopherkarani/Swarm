import Foundation

struct PreparedJobChild: Sendable {
    let name: String
    let child: JobChild
}

enum JobFanOutPreparation: Sendable {
    static func prepare(_ children: [JobChild]) throws -> [PreparedJobChild] {
        guard !children.isEmpty else {
            throw JobError.emptyFanOut
        }

        var prepared: [PreparedJobChild] = []
        var seen: Set<String> = []
        for child in children {
            let name = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw JobError.emptyChildName
            }
            if seen.contains(name) {
                throw JobError.duplicateChildName(name)
            }
            seen.insert(name)
            prepared.append(PreparedJobChild(name: name, child: child))
        }
        return prepared
    }
}
