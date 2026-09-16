// ToolBatchPlanTests.swift
// SwarmTests
//
// Pure grouping table for consecutive parallel-eligible tool calls.

import Foundation
@testable import Swarm
import Testing

@Suite("ToolBatchPlan")
struct ToolBatchPlanTests {
    @Test("empty eligibility yields no groups")
    func emptyEligibility() {
        #expect(ToolBatchPlan.groups(eligibility: []) == [])
    }

    @Test("all false yields one serial group per index")
    func allFalseYieldsSerialSingletons() {
        #expect(ToolBatchPlan.groups(eligibility: [false]) == [.serial(0)])
        #expect(
            ToolBatchPlan.groups(eligibility: [false, false, false])
                == [.serial(0), .serial(1), .serial(2)]
        )
    }

    @Test("consecutive true runs collapse to concurrent ranges")
    func consecutiveTrueRunsAreConcurrent() {
        #expect(
            ToolBatchPlan.groups(eligibility: [true, true, false, true])
                == [.concurrent(0..<2), .serial(2), .concurrent(3..<4)]
        )
        #expect(ToolBatchPlan.groups(eligibility: [true]) == [.concurrent(0..<1)])
        #expect(ToolBatchPlan.groups(eligibility: [true, true]) == [.concurrent(0..<2)])
        #expect(
            ToolBatchPlan.groups(eligibility: [false, true, true, false])
                == [.serial(0), .concurrent(1..<3), .serial(3)]
        )
    }
}
