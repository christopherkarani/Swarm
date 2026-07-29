import Foundation

struct SessionStore: Codable, Sendable {
    var currentSessionID: UUID?
    var systemPrompt: String?
    var recentTurns: [Turn]
    var totalSessions: Int

    init(
        currentSessionID: UUID? = nil,
        systemPrompt: String? = nil,
        recentTurns: [Turn] = [],
        totalSessions: Int = 0
    ) {
        self.currentSessionID = currentSessionID
        self.systemPrompt = systemPrompt
        self.recentTurns = recentTurns
        self.totalSessions = totalSessions
    }

    var isSessionActive: Bool {
        currentSessionID != nil
    }

    mutating func begin(id: UUID, systemPrompt: String?) {
        currentSessionID = id
        self.systemPrompt = systemPrompt
        recentTurns.removeAll(keepingCapacity: true)
        totalSessions += 1
    }

    mutating func end() {
        currentSessionID = nil
        systemPrompt = nil
        recentTurns.removeAll(keepingCapacity: true)
    }

    mutating func appendRecent(_ turn: Turn, maxBufferSize: Int) {
        recentTurns.append(turn)
        if recentTurns.count > maxBufferSize {
            recentTurns.removeFirst(recentTurns.count - maxBufferSize)
        }
    }

    func guaranteedRecentTurns(count: Int) -> [Turn] {
        guard count > 0 else {
            return []
        }
        return Array(recentTurns.suffix(count))
    }
}
