// ContextSlotStore.swift
// Swarm Framework
//
// Internal unified slot storage backing `AgentContext`'s typed values.

import Foundation

// MARK: - ContextSlotID

/// Identifies one typed slot inside `AgentContext`'s unified store.
///
/// Slot identity combines the static `Value` type of a `ContextKey<Value>`
/// with the key's string name, so two keys sharing a name but carrying
/// different value types always occupy distinct slots. Wrong key/value
/// pairings therefore fail to compile instead of surfacing as silent
/// runtime nils.
struct ContextSlotID: Hashable {
    // MARK: Internal

    /// Runtime identity of the slot's value type.
    let valueTypeIdentity: ObjectIdentifier

    /// The string name contributed by the key.
    let name: String

    // MARK: - Initialization

    /// Creates a slot identifier for `valueType` under `name`.
    ///
    /// - Parameters:
    ///   - valueType: The static value type of the accessing key.
    ///   - name: The string name of the accessing key.
    init<Value>(valueType: Value.Type, name: String) {
        valueTypeIdentity = ObjectIdentifier(valueType)
        self.name = name
    }
}

// MARK: - ContextSlotEntry

/// An encoded value stored under a `ContextKey<Value>` slot identity.
///
/// Values are encoded once when written and decoded once when read. Keeping
/// the encoded form lets `snapshot`, `merge(from:)`, and
/// `copy(additionalValues:)` produce `[String: SendableValue]` at their
/// boundaries without re-interpreting a stored value under another type.
struct ContextSlotEntry {
    // MARK: Public

    /// The encoded representation written for the slot's value type.
    let payload: SendableValue

    /// Monotonic sequence number used to resolve ties deterministically when
    /// several same-named slots of different value types project into a
    /// snapshot; the most recently written slot wins.
    let writeStamp: Int
}

// MARK: - ContextSlotStore

/// The single unified store for `AgentContext` typed values.
///
/// `ContextKey<Value>` writes land in value slots keyed by
/// `(Value type identity, key name)`. Untyped string access remains a separate
/// raw `[String: SendableValue]` namespace owned by `AgentContext`.
struct ContextSlotStore {
    // MARK: Private

    /// Typed value slots keyed by value-type identity plus key name.
    private var valueSlots: [ContextSlotID: ContextSlotEntry] = [:]

    /// Source of monotonically increasing write stamps.
    private var nextWriteStamp = 0

    // MARK: - Value Slots

    /// Stores `payload` in the slot identified by `key`.
    ///
    /// - Parameters:
    ///   - key: The typed key identifying the slot.
    ///   - payload: The encoded value to store.
    mutating func setValuePayload<T>(_ key: ContextKey<T>, payload: SendableValue) {
        nextWriteStamp += 1
        let id = ContextSlotID(valueType: T.self, name: key.name)
        valueSlots[id] = ContextSlotEntry(payload: payload, writeStamp: nextWriteStamp)
    }

    /// Returns the encoded payload stored for `key`, if any.
    ///
    /// - Parameter key: The typed key identifying the slot.
    /// - Returns: The stored payload, or nil when the slot is empty.
    func valuePayload<T>(for key: ContextKey<T>) -> SendableValue? {
        valueSlots[ContextSlotID(valueType: T.self, name: key.name)]?.payload
    }

    /// Removes the slot identified by `key`.
    ///
    /// - Parameter key: The typed key identifying the slot.
    /// - Returns: The removed payload, or nil when the slot was empty.
    @discardableResult
    mutating func removeValuePayload<T>(_ key: ContextKey<T>) -> SendableValue? {
        valueSlots.removeValue(forKey: ContextSlotID(valueType: T.self, name: key.name))?.payload
    }

    /// Returns whether a slot exists for `key`.
    ///
    /// - Parameter key: The typed key identifying the slot.
    /// - Returns: True when the slot holds a value.
    func hasValuePayload<T>(_ key: ContextKey<T>) -> Bool {
        valueSlots[ContextSlotID(valueType: T.self, name: key.name)] != nil
    }

    /// Merges value slots from `other` into this store.
    ///
    /// Incoming slots are re-stamped in source-recency order so the relative
    /// order that `projectedValues` resolves ties by survives the merge
    /// regardless of dictionary iteration order.
    ///
    /// When `overwrite` is false, existing slots are left untouched. Incoming
    /// slots that share a name with a local slot but have a different value
    /// type are still inserted so typed reads of the incoming type work, but
    /// they receive a write stamp strictly below the current same-name winner
    /// so they cannot steal the snapshot projection.
    ///
    /// - Parameters:
    ///   - other: The store whose value slots are copied in.
    ///   - overwrite: When false, existing slots are left untouched and
    ///     same-name newcomers stay below the local projection winner.
    mutating func mergeValueSlots(from other: ContextSlotStore, overwrite: Bool) {
        let incoming = other.valueSlots.sorted(by: { $0.value.writeStamp < $1.value.writeStamp })

        if overwrite {
            for (id, entry) in incoming {
                nextWriteStamp += 1
                valueSlots[id] = ContextSlotEntry(
                    payload: entry.payload,
                    writeStamp: nextWriteStamp
                )
            }
            return
        }

        var winnerStampByName: [String: Int] = [:]
        var usedStampsByName: [String: Set<Int>] = [:]
        for (id, entry) in valueSlots {
            usedStampsByName[id.name, default: []].insert(entry.writeStamp)
            if let current = winnerStampByName[id.name], current >= entry.writeStamp {
                continue
            }
            winnerStampByName[id.name] = entry.writeStamp
        }

        var newNames: [(id: ContextSlotID, entry: ContextSlotEntry)] = []
        var belowWinnerByName: [String: [(id: ContextSlotID, entry: ContextSlotEntry)]] = [:]
        for (id, entry) in incoming {
            guard valueSlots[id] == nil else { continue }
            if winnerStampByName[id.name] != nil {
                belowWinnerByName[id.name, default: []].append((id, entry))
            } else {
                newNames.append((id, entry))
            }
        }

        for (name, entries) in belowWinnerByName {
            guard var nextBelow = winnerStampByName[name] else { continue }
            var used = usedStampsByName[name] ?? []
            // Newest incoming first so relative recency among newcomers is
            // preserved, all strictly below the local winner.
            for (id, entry) in entries.reversed() {
                nextBelow -= 1
                while used.contains(nextBelow) {
                    nextBelow -= 1
                }
                valueSlots[id] = ContextSlotEntry(payload: entry.payload, writeStamp: nextBelow)
                used.insert(nextBelow)
            }
        }

        for (id, entry) in newNames {
            nextWriteStamp += 1
            valueSlots[id] = ContextSlotEntry(
                payload: entry.payload,
                writeStamp: nextWriteStamp
            )
        }
    }

    /// Projects value slots into the string-keyed snapshot form.
    ///
    /// When several slots share a name across different value types, the most
    /// recently written slot wins. Raw namespace entries owned by
    /// `AgentContext` take precedence during snapshot assembly.
    ///
    /// - Returns: Projected payloads keyed by slot name.
    func projectedValues() -> [String: SendableValue] {
        var latestByName: [String: (stamp: Int, payload: SendableValue)] = [:]
        for (id, entry) in valueSlots {
            if let current = latestByName[id.name], current.stamp > entry.writeStamp {
                continue
            }
            latestByName[id.name] = (entry.writeStamp, entry.payload)
        }
        return latestByName.mapValues(\.payload)
    }

    /// The distinct slot names held in value slots.
    var valueNames: [String] {
        Set(valueSlots.keys.map(\.name)).sorted()
    }

    /// Returns whether any value slot occupies `name`, regardless of the
    /// owning value type.
    ///
    /// - Parameter name: The string name to look up.
    /// - Returns: True when at least one slot uses this name.
    func containsValueName(_ name: String) -> Bool {
        valueSlots.contains { $0.key.name == name }
    }

    // MARK: - Copying

    /// Creates a copy holding the value slots.
    ///
    /// - Returns: A store whose value slots match this store's.
    func copyingValueSlots() -> ContextSlotStore {
        var copy = ContextSlotStore()
        // Re-stamp in source-recency order so a copy projects the same
        // same-named winner as its source regardless of dictionary
        // iteration order.
        for (id, entry) in valueSlots.sorted(by: { $0.value.writeStamp < $1.value.writeStamp }) {
            copy.nextWriteStamp += 1
            copy.valueSlots[id] = ContextSlotEntry(
                payload: entry.payload,
                writeStamp: copy.nextWriteStamp
            )
        }
        return copy
    }

}
