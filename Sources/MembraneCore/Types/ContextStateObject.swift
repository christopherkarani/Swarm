public struct ContextStateObject: Sendable, Codable {
    public private(set) var entities: [String]
    public var decisions: [String]
    public var openQuestions: [String]
    public var keyFacts: [String]
    public var turnCount: Int

    public init(
        entities: [String] = [],
        decisions: [String] = [],
        openQuestions: [String] = [],
        keyFacts: [String] = [],
        turnCount: Int = 0
    ) {
        self.entities = []
        self.decisions = decisions
        self.openQuestions = openQuestions
        self.keyFacts = keyFacts
        self.turnCount = turnCount
        for entity in entities {
            addEntity(entity)
        }
        trimBounds()
    }

    public mutating func addEntity(_ entity: String) {
        guard !entity.isEmpty else {
            return
        }

        if !entities.contains(entity) {
            entities.append(entity)
        }

        if entities.count > 50 {
            entities = Array(entities.suffix(50))
        }
    }

    public mutating func merge(with other: ContextStateObject) {
        for entity in other.entities {
            addEntity(entity)
        }

        decisions.append(contentsOf: other.decisions)
        openQuestions.append(contentsOf: other.openQuestions)
        keyFacts.append(contentsOf: other.keyFacts)
        turnCount = max(turnCount, other.turnCount)
        trimBounds()
    }

    public func formatted() -> String {
        var lines: [String] = []
        if !entities.isEmpty {
            lines.append("Entities: \(entities.joined(separator: ", "))")
        }
        if !decisions.isEmpty {
            lines.append("Decisions: \(decisions.joined(separator: "; "))")
        }
        if !openQuestions.isEmpty {
            lines.append("OpenQuestions: \(openQuestions.joined(separator: "; "))")
        }
        if !keyFacts.isEmpty {
            lines.append("KeyFacts: \(keyFacts.joined(separator: "; "))")
        }
        lines.append("TurnCount: \(turnCount)")
        return lines.joined(separator: "\n")
    }

    public var estimatedTokenCount: Int {
        max(formatted().count / 4, 1)
    }

    package mutating func trimBounds() {
        if decisions.count > 20 {
            decisions = Array(decisions.suffix(20))
        }
        if openQuestions.count > 10 {
            openQuestions = Array(openQuestions.suffix(10))
        }
        if keyFacts.count > 30 {
            keyFacts = Array(keyFacts.suffix(30))
        }
    }
}
