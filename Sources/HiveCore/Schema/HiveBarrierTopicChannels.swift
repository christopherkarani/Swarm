/// Stable identifier for a barrier instance within barrier channel state.
public struct HiveBarrierKey: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Stable token value recorded for a producer within a barrier.
public struct HiveBarrierToken: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Barrier channel update operations.
public enum HiveBarrierUpdate: Sendable, Hashable, Codable {
    case markSeen(barrier: HiveBarrierKey, producer: HiveNodeID, token: HiveBarrierToken)
    case consume(barrier: HiveBarrierKey, expectedProducers: [HiveNodeID])
}

/// Deterministic barrier channel state.
///
/// The internal representation uses string keys to avoid non-canonical encoding pitfalls.
public struct HiveBarrierState: Sendable, Hashable, Codable {
    private var tokensByBarrierID: [String: [String: HiveBarrierToken]]

    public init(tokensByBarrierID: [String: [String: HiveBarrierToken]] = [:]) {
        self.tokensByBarrierID = tokensByBarrierID
    }

    public static var empty: Self { Self() }

    public func token(for barrier: HiveBarrierKey, producer: HiveNodeID) -> HiveBarrierToken? {
        tokensByBarrierID[barrier.rawValue]?[producer.rawValue]
    }

    public func tokens(for barrier: HiveBarrierKey) -> [HiveNodeID: HiveBarrierToken] {
        guard let raw = tokensByBarrierID[barrier.rawValue] else { return [:] }
        var result: [HiveNodeID: HiveBarrierToken] = [:]
        result.reserveCapacity(raw.count)
        for (producerRaw, token) in raw {
            result[HiveNodeID(producerRaw)] = token
        }
        return result
    }

    public func isAvailable(barrier: HiveBarrierKey, expectedProducers: [HiveNodeID]) -> Bool {
        guard let tokens = tokensByBarrierID[barrier.rawValue] else { return false }
        for producer in expectedProducers {
            if tokens[producer.rawValue] == nil {
                return false
            }
        }
        return true
    }

    mutating func apply(_ update: HiveBarrierUpdate) {
        switch update {
        case .markSeen(let barrier, let producer, let token):
            var perProducer = tokensByBarrierID[barrier.rawValue] ?? [:]
            perProducer[producer.rawValue] = token
            tokensByBarrierID[barrier.rawValue] = perProducer
        case .consume(let barrier, let expectedProducers):
            guard isAvailable(barrier: barrier, expectedProducers: expectedProducers) else { return }
            tokensByBarrierID[barrier.rawValue] = nil
        }
    }
}

/// Channel value wrapper for barrier channels.
///
/// The reducer for this value type must normalize to `.state`.
public enum HiveBarrierChannelValue: Sendable, Hashable, Codable {
    case state(HiveBarrierState)
    case update(HiveBarrierUpdate)

    public var stateValue: HiveBarrierState? {
        if case .state(let state) = self { return state }
        return nil
    }
}

public extension HiveReducer where Value == HiveBarrierChannelValue {
    static func barrier() -> HiveReducer<Value> {
        HiveReducer { current, update in
            func extractState(_ value: HiveBarrierChannelValue) -> HiveBarrierState {
                switch value {
                case .state(let state):
                    return state
                case .update(let update):
                    var state = HiveBarrierState.empty
                    state.apply(update)
                    return state
                }
            }

            var state = extractState(current)
            switch update {
            case .state(let newState):
                state = newState
            case .update(let update):
                state.apply(update)
            }
            return .state(state)
        }
    }
}

/// Stable identifier for a topic instance within topic channel state.
public struct HiveTopicKey: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Topic channel update operations.
public enum HiveTopicUpdate<Value: Sendable & Codable>: Sendable, Codable {
    case publish(topic: HiveTopicKey, value: Value)
    case clear(topic: HiveTopicKey)
}

/// Deterministic topic channel state.
public struct HiveTopicState<Value: Sendable & Codable>: Sendable, Codable {
    private var valuesByTopicID: [String: [Value]]

    public init(valuesByTopicID: [String: [Value]] = [:]) {
        self.valuesByTopicID = valuesByTopicID
    }

    public static var empty: Self { Self() }

    public func values(for topic: HiveTopicKey) -> [Value] {
        valuesByTopicID[topic.rawValue] ?? []
    }

    mutating func apply(_ update: HiveTopicUpdate<Value>, maxValuesPerTopic: Int) {
        switch update {
        case .publish(let topic, let value):
            let maxValues = max(0, maxValuesPerTopic)
            guard maxValues != 0 else {
                valuesByTopicID[topic.rawValue] = []
                return
            }

            var values = valuesByTopicID[topic.rawValue] ?? []
            values.append(value)
            if values.count > maxValues {
                values.removeFirst(values.count - maxValues)
            }
            valuesByTopicID[topic.rawValue] = values
        case .clear(let topic):
            valuesByTopicID[topic.rawValue] = nil
        }
    }
}

/// Channel value wrapper for topic channels.
///
/// The reducer for this value type must normalize to `.state`.
public enum HiveTopicChannelValue<Value: Sendable & Codable>: Sendable, Codable {
    case state(HiveTopicState<Value>)
    case update(HiveTopicUpdate<Value>)

    public var stateValue: HiveTopicState<Value>? {
        if case .state(let state) = self { return state }
        return nil
    }
}

public extension HiveReducer {
    static func topicAppendOnly<TopicValue>(
        maxValuesPerTopic: Int
    ) -> HiveReducer<HiveTopicChannelValue<TopicValue>>
    where Value == HiveTopicChannelValue<TopicValue>, TopicValue: Sendable & Codable {
        // Defensive normalization: invalid configuration should not crash the process.
        let normalizedMaxValuesPerTopic = Swift.max(1, maxValuesPerTopic)
        return HiveReducer<HiveTopicChannelValue<TopicValue>> { current, update in
            func extractState(_ value: HiveTopicChannelValue<TopicValue>) -> HiveTopicState<TopicValue> {
                switch value {
                case .state(let state):
                    return state
                case .update(let update):
                    var state = HiveTopicState<TopicValue>.empty
                    state.apply(update, maxValuesPerTopic: normalizedMaxValuesPerTopic)
                    return state
                }
            }

            var state = extractState(current)
            switch update {
            case .state(let newState):
                state = newState
            case .update(let update):
                state.apply(update, maxValuesPerTopic: normalizedMaxValuesPerTopic)
            }
            return .state(state)
        }
    }
}
