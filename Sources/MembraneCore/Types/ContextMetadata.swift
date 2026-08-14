public struct ContextMetadata: Sendable, Equatable {
    public var turnNumber: Int
    public var sessionID: String
    public var modelProfile: BudgetProfile

    public init(
        turnNumber: Int = 0,
        sessionID: String = "",
        modelProfile: BudgetProfile = .foundationModels4K
    ) {
        self.turnNumber = turnNumber
        self.sessionID = sessionID
        self.modelProfile = modelProfile
    }
}
