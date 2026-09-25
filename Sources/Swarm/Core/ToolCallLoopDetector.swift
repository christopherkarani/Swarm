// ToolCallLoopDetector.swift
// Swarm Framework
//
// Detects models stuck repeating identical tool-call batches.

import Foundation

/// A detected tool-call loop: the same batch repeated consecutively.
public struct ToolCallLoop: Sendable, Equatable {
    /// Tool names in the repeated batch, in call order.
    public let toolNames: [String]

    /// How many consecutive identical batches were observed.
    public let repetitions: Int

    /// Creates a detected loop.
    public init(toolNames: [String], repetitions: Int) {
        self.toolNames = toolNames
        self.repetitions = repetitions
    }
}

/// Detects when a model repeats the same tool-call batch consecutively.
///
/// Each observed batch is fingerprinted by tool name plus canonical
/// (key-sorted) arguments, in call order. When the same fingerprint
/// repeats ``maxConsecutiveRepeats`` times in a row, `observe` returns a
/// ``ToolCallLoop`` instead of `nil` so the caller can stop the run with
/// a clear error rather than burning the iteration budget.
///
/// The detector is a value type: keep one per run and feed it every
/// tool-call batch in order.
///
/// ## Example
///
/// ```swift
/// var detector = ToolCallLoopDetector()
/// for batch in batches {
///     if let loop = detector.observe(batch) {
///         throw AgentError.toolCallLoopDetected(
///             toolNames: loop.toolNames,
///             repetitions: loop.repetitions
///         )
///     }
/// }
/// ```
public struct ToolCallLoopDetector: Sendable {
    /// Consecutive identical batches that constitute a loop.
    ///
    /// Values below 2 are raised to 2: a single batch can never be a loop.
    /// Default: 3, which allows one genuine retry of a failed call.
    public var maxConsecutiveRepeats: Int

    /// Creates a detector.
    ///
    /// - Parameter maxConsecutiveRepeats: Trip threshold. Default: 3.
    public init(maxConsecutiveRepeats: Int = 3) {
        self.maxConsecutiveRepeats = max(2, maxConsecutiveRepeats)
    }

    /// Observes one tool-call batch, in run order.
    ///
    /// - Parameter calls: The batch just produced by the model. Empty
    ///   batches reset the streak and never trip.
    /// - Returns: The detected loop once the streak reaches
    ///   ``maxConsecutiveRepeats``; otherwise `nil`.
    public mutating func observe(_ calls: [InferenceResponse.ParsedToolCall]) -> ToolCallLoop? {
        guard !calls.isEmpty else {
            reset()
            return nil
        }
        let fingerprint = Self.fingerprint(calls)
        if fingerprint == lastFingerprint {
            streak += 1
        } else {
            lastFingerprint = fingerprint
            streak = 1
        }
        guard streak >= maxConsecutiveRepeats else {
            return nil
        }
        return ToolCallLoop(toolNames: calls.map(\.name), repetitions: streak)
    }

    /// Clears the observed streak.
    public mutating func reset() {
        lastFingerprint = nil
        streak = 0
    }

    private var lastFingerprint: String?
    private var streak = 0

    private static func fingerprint(_ calls: [InferenceResponse.ParsedToolCall]) -> String {
        calls.map { "\($0.name)(\(canonicalArguments($0.arguments)))" }
            .joined(separator: "\n")
    }

    private static func canonicalArguments(_ arguments: [String: SendableValue]) -> String {
        let object = SendableValue.dictionary(arguments).toJSONObject()
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "<unencodable>"
        }
        return string
    }
}
