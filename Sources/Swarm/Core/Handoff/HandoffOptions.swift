// HandoffOptions.swift
// Swarm Framework
//
// Modern, typed configuration surface for handoff APIs.

import Foundation

/// Strategy for how prior conversation history is carried into a handoff.
public enum HandoffHistory: Sendable, Equatable {
    /// Do not include source-agent conversation history.
    case none

    /// Include nested source-agent conversation history.
    case nested

    /// Include summarized history with a target budget.
    ///
    /// Current runtime behavior nests history and annotates metadata with the
    /// summary target budget for downstream handling.
    case summarized(maxTokens: Int = 600)

    var nestsHistory: Bool {
        switch self {
        case .none:
            false
        case .nested, .summarized:
            true
        }
    }
}

/// Opinionated defaults for handoff configuration.
public enum HandoffPolicy: Sendable, Equatable {
    /// Minimal transfer: no inherited history.
    case minimal

    /// Balanced transfer: nested history.
    case balanced

    /// Strict transfer: summarized history.
    case strict

    var defaultHistory: HandoffHistory {
        switch self {
        case .minimal:
            .none
        case .balanced:
            .nested
        case .strict:
            .summarized()
        }
    }
}

/// Typed metadata key for handoff payload metadata.
public struct HandoffMetadataKey<Value: Sendable>: Sendable {
    public let rawValue: String
    let encode: @Sendable (Value) -> SendableValue
    let decode: @Sendable (SendableValue) -> Value?

    public init(
        _ rawValue: String,
        encode: @escaping @Sendable (Value) -> SendableValue,
        decode: @escaping @Sendable (SendableValue) -> Value?
    ) {
        self.rawValue = rawValue
        self.encode = encode
        self.decode = decode
    }
}

public extension HandoffMetadataKey where Value == String {
    static func string(_ rawValue: String) -> Self {
        Self(
            rawValue,
            encode: { .string($0) },
            decode: { $0.stringValue }
        )
    }
}

public extension HandoffMetadataKey where Value == Int {
    static func int(_ rawValue: String) -> Self {
        Self(
            rawValue,
            encode: { .int($0) },
            decode: { $0.intValue }
        )
    }
}

public extension HandoffMetadataKey where Value == Bool {
    static func bool(_ rawValue: String) -> Self {
        Self(
            rawValue,
            encode: { .bool($0) },
            decode: { $0.boolValue }
        )
    }
}

public extension HandoffInputData {
    /// Reads typed metadata from handoff data.
    func metadata<Value: Sendable>(for key: HandoffMetadataKey<Value>) -> Value? {
        guard let value = metadata[key.rawValue] else { return nil }
        return key.decode(value)
    }

    /// Returns a copy with typed metadata set.
    func settingMetadata<Value: Sendable>(_ key: HandoffMetadataKey<Value>, _ value: Value) -> HandoffInputData {
        var copy = self
        copy.metadata[key.rawValue] = key.encode(value)
        return copy
    }
}

/// Typed, fluent configuration object for building handoffs.
public struct HandoffOptions<Target: AgentRuntime>: Sendable {
    let nameOverride: String?
    let descriptionText: String?
    let onTransferCallback: OnTransferCallback?
    let transformCallback: TransformCallback?
    let whenCallback: WhenCallback?
    let historyStrategy: HandoffHistory
    let appliedPolicy: HandoffPolicy?

    /// Creates default handoff options.
    public init() {
        nameOverride = nil
        descriptionText = nil
        onTransferCallback = nil
        transformCallback = nil
        whenCallback = nil
        historyStrategy = .none
        appliedPolicy = nil
    }

    /// Sets handoff tool name.
    public func name(_ value: String) -> Self {
        with { $0.nameOverride = value }
    }

    /// Sets handoff tool description.
    public func description(_ value: String) -> Self {
        with { $0.descriptionText = value }
    }

    /// Registers a pre-transfer callback.
    public func onTransfer(_ callback: @escaping OnTransferCallback) -> Self {
        with { $0.onTransferCallback = callback }
    }

    /// Registers an input transform callback.
    public func transform(_ callback: @escaping TransformCallback) -> Self {
        with { $0.transformCallback = callback }
    }

    /// Registers an enablement predicate.
    public func when(_ callback: @escaping WhenCallback) -> Self {
        with { $0.whenCallback = callback }
    }

    /// Sets history strategy.
    public func history(_ strategy: HandoffHistory) -> Self {
        with { $0.historyStrategy = strategy }
    }

    /// Applies a preset policy.
    ///
    /// Policy defaults can still be overridden by subsequent explicit options
    /// (for example, `.policy(.balanced).history(.none)`).
    public func policy(_ policy: HandoffPolicy) -> Self {
        with {
            $0.appliedPolicy = policy
            $0.historyStrategy = policy.defaultHistory
        }
    }

    func erasedConfiguration(for target: Target) -> AnyHandoffConfiguration {
        let normalizedTransform = composedTransform()
        return AnyHandoffConfiguration(
            targetAgent: target,
            toolNameOverride: nameOverride,
            toolDescription: descriptionText,
            onTransfer: onTransferCallback,
            transform: normalizedTransform,
            when: whenCallback,
            history: historyStrategy
        )
    }

    private func composedTransform() -> TransformCallback? {
        guard case let .summarized(maxTokens) = historyStrategy else {
            return transformCallback
        }

        let historyModeKey = HandoffMetadataKey<String>.string("swarm.handoff.history.mode")
        let historyMaxTokensKey = HandoffMetadataKey<Int>.int("swarm.handoff.history.maxTokens")

        if let transformCallback {
            return { data in
                transformCallback(data)
                    .settingMetadata(historyModeKey, "summarized")
                    .settingMetadata(historyMaxTokensKey, maxTokens)
            }
        }

        return { data in
            data
                .settingMetadata(historyModeKey, "summarized")
                .settingMetadata(historyMaxTokensKey, maxTokens)
        }
    }

    private func with(_ update: (inout MutableState) -> Void) -> Self {
        var state = MutableState(
            nameOverride: nameOverride,
            descriptionText: descriptionText,
            onTransferCallback: onTransferCallback,
            transformCallback: transformCallback,
            whenCallback: whenCallback,
            historyStrategy: historyStrategy,
            appliedPolicy: appliedPolicy
        )
        update(&state)
        return Self(state: state)
    }

    private init(state: MutableState) {
        nameOverride = state.nameOverride
        descriptionText = state.descriptionText
        onTransferCallback = state.onTransferCallback
        transformCallback = state.transformCallback
        whenCallback = state.whenCallback
        historyStrategy = state.historyStrategy
        appliedPolicy = state.appliedPolicy
    }

    private struct MutableState {
        var nameOverride: String?
        var descriptionText: String?
        var onTransferCallback: OnTransferCallback?
        var transformCallback: TransformCallback?
        var whenCallback: WhenCallback?
        var historyStrategy: HandoffHistory
        var appliedPolicy: HandoffPolicy?
    }
}

public extension AgentRuntime {
    /// Creates a handoff from this agent using default options.
    func asHandoff() -> AnyHandoffConfiguration {
        HandoffOptions<Self>().erasedConfiguration(for: self)
    }

    /// Creates a handoff from this agent with modern typed options.
    func asHandoff(
        _ configure: (HandoffOptions<Self>) -> HandoffOptions<Self>
    ) -> AnyHandoffConfiguration {
        configure(HandoffOptions()).erasedConfiguration(for: self)
    }
}
