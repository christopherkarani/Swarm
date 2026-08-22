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
/// `(Value type identity, key name)`; the deprecated `AgentContextProviding`
/// shim stores instances in provided slots keyed by
/// `(concrete type identity, contextKey)`. Untyped string access remains a
/// separate raw `[String: SendableValue]` namespace owned by `AgentContext`.
struct ContextSlotStore {
    // MARK: Private

    /// Typed value slots keyed by value-type identity plus key name.
    private var valueSlots: [ContextSlotID: ContextSlotEntry] = [:]

    /// Deprecated `AgentContextProviding` instances keyed by concrete type
    /// identity plus the conformer's `contextKey`.
    private var providedSlots: [ContextSlotID: any AgentContextProviding] = [:]

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
    /// - Parameters:
    ///   - other: The store whose value slots are copied in.
    ///   - overwrite: When false, existing slots are left untouched.
    mutating func mergeValueSlots(from other: ContextSlotStore, overwrite: Bool) {
        // Re-stamp in source-recency order so the relative order that
        // `projectedValues` resolves ties by survives the merge regardless
        // of dictionary iteration order.
        for (id, entry) in other.valueSlots.sorted(by: { $0.value.writeStamp < $1.value.writeStamp }) {
            if overwrite || valueSlots[id] == nil {
                nextWriteStamp += 1
                valueSlots[id] = ContextSlotEntry(
                    payload: entry.payload,
                    writeStamp: nextWriteStamp
                )
            }
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

    // MARK: - Provided Slots (deprecated shim)

    /// Stores `instance` in the slot identified by its concrete type and
    /// `AgentContextProviding.contextKey`.
    ///
    /// - Parameter instance: The typed context instance to store.
    mutating func setProvided<T: AgentContextProviding>(_ instance: T) {
        let id = ContextSlotID(valueType: T.self, name: T.contextKey)
        providedSlots[id] = instance
    }

    /// Returns the stored instance for `type`, if any.
    ///
    /// The slot identifier pins the concrete type, so the single existential
    /// crossing below can neither fail nor produce a wrong-typed value; a
    /// mismatched request simply addresses an empty slot and returns nil.
    ///
    /// - Parameter type: The concrete context type to retrieve.
    /// - Returns: The stored instance, or nil when absent.
    func provided<T: AgentContextProviding>(of type: T.Type) -> T? {
        extract(type, from: providedSlots[ContextSlotID(valueType: T.self, name: T.contextKey)])
    }

    /// Removes and returns the stored instance for `type`, if any.
    ///
    /// - Parameter type: The concrete context type to remove.
    /// - Returns: The removed instance, or nil when absent.
    @discardableResult
    mutating func removeProvided<T: AgentContextProviding>(of type: T.Type) -> T? {
        extract(type, from: providedSlots.removeValue(forKey: ContextSlotID(
            valueType: T.self,
            name: T.contextKey
        )))
    }

    /// Returns whether a provided slot exists for `type`.
    ///
    /// - Parameter type: The concrete context type to look up.
    /// - Returns: True when an instance of this type is stored.
    func containsProvided<T: AgentContextProviding>(of type: T.Type) -> Bool {
        providedSlots[ContextSlotID(valueType: T.self, name: T.contextKey)] != nil
    }

    // MARK: - Copying

    /// Creates a copy holding only value slots, dropping provided slots.
    ///
    /// Provided slots are deliberately excluded: `copy(additionalValues:)`
    /// historically duplicated only the string-keyed values that typed
    /// `ContextKey` writes produced, never `AgentContextProviding` instances.
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

    // MARK: Private

    /// Crosses the `any AgentContextProviding` existential boundary after
    /// slot identity already established the stored instance has type
    /// `Value`.
    ///
    /// This is not a speculative runtime check like the removed string-keyed
    /// lookup: the slot identifier pins the concrete conformer type, so the
    /// conversion below can neither fail nor produce a wrong-typed value. It
    /// exists only because Swift has no way to recover a concrete type from
    /// an existential without one checked conversion at the storage boundary.
    private func extract<Value: AgentContextProviding>(
        _ type: Value.Type,
        from slot: (any AgentContextProviding)?
    ) -> Value? {
        guard let slot else { return nil }
        return slot as? Value
    }
}
