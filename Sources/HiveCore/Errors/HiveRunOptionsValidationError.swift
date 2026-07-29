public enum HiveRunOptionsValidationError: Error, Sendable, Equatable {
    case invalidBounds(option: String, reason: String)
    case unsupportedCombination(reason: String)
    case missingRequiredComponent(component: String, reason: String)
}
