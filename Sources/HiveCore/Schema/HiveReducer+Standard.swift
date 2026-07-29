public extension HiveReducer {
    /// Always selects the update value, ignoring the current value.
    static func lastWriteWins() -> HiveReducer<Value> {
        HiveReducer { _, update in update }
    }

    /// Combines current and update using a caller-supplied binary operator.
    /// Folds all updates into the current value using the supplied binary operation.
    static func binaryOp(
        _ op: @escaping @Sendable (Value, Value) -> Value
    ) -> HiveReducer<Value> {
        HiveReducer { current, update in op(current, update) }
    }
}

public extension HiveReducer where Value: Numeric & Sendable {
    /// Accumulates updates by addition. Common for counters and running totals.
    static func sum() -> HiveReducer<Value> {
        HiveReducer { current, update in current + update }
    }
}

public extension HiveReducer where Value: Comparable & Sendable {
    /// Retains the lesser of current and update.
    static func min() -> HiveReducer<Value> {
        HiveReducer { current, update in Swift.min(current, update) }
    }

    /// Retains the greater of current and update.
    static func max() -> HiveReducer<Value> {
        HiveReducer { current, update in Swift.max(current, update) }
    }
}

public extension HiveReducer where Value: RangeReplaceableCollection {
    /// Appends update elements to the current collection, preserving order.
    static func append() -> HiveReducer<Value> {
        HiveReducer { current, update in
            var combined = current
            combined.append(contentsOf: update)
            return combined
        }
    }
}

public extension HiveReducer {
    /// Appends update elements for optional collections, treating nil as empty.
    /// Returns nil only when both current and update are nil.
    static func appendNonNil<C>() -> HiveReducer<C?> where C: RangeReplaceableCollection, C: Sendable {
        HiveReducer<C?> { current, update in
            switch (current, update) {
            case (nil, nil):
                return nil
            case (nil, let update?):
                return update
            case (let current?, nil):
                return current
            case (let current?, let update?):
                var combined = current
                combined.append(contentsOf: update)
                return combined
            }
        }
    }

    /// Merges two sets using union semantics.
    static func setUnion<Element>() -> HiveReducer<Set<Element>> where Element: Hashable, Element: Sendable {
        HiveReducer<Set<Element>> { current, update in
            current.union(update)
        }
    }

    /// Merges update entries into current, resolving conflicts via `valueReducer`.
    /// Update keys are processed in ascending UTF-8 lexicographic order.
    static func dictionaryMerge<V>(valueReducer: HiveReducer<V>) -> HiveReducer<[String: V]> where V: Sendable {
        HiveReducer<[String: V]> { current, update in
            var merged = current
            let sortedKeys = update.keys.sorted { lhs, rhs in
                lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
            }
            for key in sortedKeys {
                guard let updateValue = update[key] else { continue }
                if let currentValue = merged[key] {
                    merged[key] = try valueReducer.reduce(current: currentValue, update: updateValue)
                } else {
                    merged[key] = updateValue
                }
            }
            return merged
        }
    }
}
