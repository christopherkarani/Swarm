// ToolCallLoopDetectorTests.swift
// SwarmTests
//
// Unit tests for consecutive tool-call loop detection.

import Foundation
@testable import Swarm
import Testing

@Suite("ToolCallLoopDetector")
struct ToolCallLoopDetectorTests {
    @Test("Distinct batches never trip")
    func distinctBatchesNeverTrip() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("a")]) == nil)
        #expect(detector.observe([call("b")]) == nil)
        #expect(detector.observe([call("a")]) == nil)
        #expect(detector.observe([call("b")]) == nil)
    }

    @Test("Three identical batches trip with names and count")
    func threeIdenticalBatchesTrip() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) == nil)
        let loop = detector.observe([call("noop")])
        #expect(loop == ToolCallLoop(toolNames: ["noop"], repetitions: 3))
    }

    @Test("Argument changes reset the streak")
    func argumentChangesResetStreak() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("get", arguments: ["id": .string("1")])]) == nil)
        #expect(detector.observe([call("get", arguments: ["id": .string("1")])]) == nil)
        #expect(detector.observe([call("get", arguments: ["id": .string("2")])]) == nil)
        #expect(detector.observe([call("get", arguments: ["id": .string("2")])]) == nil)
        #expect(detector.observe([call("get", arguments: ["id": .string("2")])]) != nil)
    }

    @Test("Argument key order does not matter")
    func argumentKeyOrderDoesNotMatter() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("f", arguments: ["a": .int(1), "b": .int(2)])]) == nil)
        #expect(detector.observe([call("f", arguments: ["b": .int(2), "a": .int(1)])]) == nil)
        #expect(detector.observe([call("f", arguments: ["a": .int(1), "b": .int(2)])]) != nil)
    }

    @Test("Batch order matters")
    func batchOrderMatters() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("a"), call("b")]) == nil)
        #expect(detector.observe([call("a"), call("b")]) == nil)
        #expect(detector.observe([call("b"), call("a")]) == nil)
        #expect(detector.observe([call("b"), call("a")]) == nil)
        let loop = detector.observe([call("b"), call("a")])
        #expect(loop?.toolNames == ["b", "a"])
    }

    @Test("Empty batch resets the streak")
    func emptyBatchResetsStreak() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([]) == nil)
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) != nil)
    }

    @Test("Custom threshold is honored")
    func customThresholdIsHonored() {
        var detector = ToolCallLoopDetector(maxConsecutiveRepeats: 2)
        #expect(detector.observe([call("noop")]) == nil)
        let loop = detector.observe([call("noop")])
        #expect(loop?.repetitions == 2)
    }

    @Test("Threshold below 2 coerces to 2")
    func thresholdFloorIsTwo() {
        var detector = ToolCallLoopDetector(maxConsecutiveRepeats: 1)
        #expect(detector.maxConsecutiveRepeats == 2)
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) != nil)
    }

    @Test("Reset clears the streak")
    func resetClearsStreak() {
        var detector = ToolCallLoopDetector()
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) == nil)
        detector.reset()
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) == nil)
        #expect(detector.observe([call("noop")]) != nil)
    }

    private func call(
        _ name: String,
        arguments: [String: SendableValue] = [:]
    ) -> InferenceResponse.ParsedToolCall {
        InferenceResponse.ParsedToolCall(id: nil, name: name, arguments: arguments)
    }
}
