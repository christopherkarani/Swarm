// Agent+ToolOutput.swift
// Swarm Framework
//
// Canonical text projection for tool outputs. Shared by the tool-calling turn
// and provider adapters that surface tool results without running the turn.

import Foundation

extension Agent {
    /// Serializes a non-string tool result as canonical JSON so downstream
    /// consumers (Membrane pointerization, transcript replay, model context)
    /// receive a parsable contract rather than `SendableValue.description`'s
    /// JSON-ish format which does not escape quotes, backslashes, or newlines.
    ///
    /// Plain-string results pass through unchanged. Falls back to
    /// `description` if the value contains a non-finite double — `JSONSerialization`
    /// raises an Objective-C `NSException` (not a Swift error) on NaN/Infinity,
    /// so we must screen the value before serializing rather than relying on
    /// `do/catch`.
    static func toolOutputText(for output: SendableValue) -> String {
        if let string = output.stringValue {
            return string
        }

        guard !containsNonFiniteDouble(output) else {
            return output.description
        }

        do {
            let object = output.toJSONObject()
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            if let text = String(data: data, encoding: .utf8) {
                return text
            }
        } catch {
            Log.agents.warning("Tool output JSON serialization failed; falling back to description: \(error)")
        }

        return output.description
    }

    private static func containsNonFiniteDouble(_ value: SendableValue) -> Bool {
        switch value {
        case let .double(number):
            return !number.isFinite
        case let .array(values):
            return values.contains(where: containsNonFiniteDouble)
        case let .dictionary(values):
            return values.values.contains(where: containsNonFiniteDouble)
        case .null, .bool, .int, .string:
            return false
        }
    }
}
