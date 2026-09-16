// ToolBatchPlan.swift
// Swarm Framework
//
// Pure grouping of consecutive parallel-eligible tool calls.

import Foundation

/// One step of a tool batch: overlapping work or a serial singleton.
enum ToolBatchGroup: Equatable, Sendable {
    /// Half-open indices into the call list that may overlap.
    case concurrent(Range<Int>)
    /// Single index that must not overlap any other call.
    case serial(Int)
}

/// Groups a call list from parallel-eligibility flags.
///
/// A maximal consecutive `true` run is one concurrent group. Each `false` is
/// a serial singleton. Empty input yields no groups.
enum ToolBatchPlan: Sendable {
    static func groups(eligibility: [Bool]) -> [ToolBatchGroup] {
        var groups: [ToolBatchGroup] = []
        var index = 0
        while index < eligibility.count {
            if eligibility[index] {
                var end = index + 1
                while end < eligibility.count, eligibility[end] {
                    end += 1
                }
                groups.append(.concurrent(index..<end))
                index = end
            } else {
                groups.append(.serial(index))
                index += 1
            }
        }
        return groups
    }
}
