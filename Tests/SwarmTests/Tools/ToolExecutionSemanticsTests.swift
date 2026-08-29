// ToolExecutionSemanticsTests.swift
// SwarmTests
//
// Pure `runtimePolicy()` decisions for tool governance.

import Foundation
@testable import Swarm
import Testing

@Suite("ToolExecutionSemantics runtimePolicy")
struct ToolExecutionSemanticsTests {
    @Test("automatic preserves host-loop defaults")
    func automaticPreservesHostLoopDefaults() {
        let policy = ToolExecutionSemantics.automatic.runtimePolicy()
        #expect(policy.mayRetryAutomatically == true)
        #expect(policy.requiresApproval == false)
        #expect(policy.mayRunInParallel == true)
    }

    @Test("unspecified side effects stay parallel-eligible")
    func unspecifiedSideEffectsStayParallelEligible() {
        let policy = ToolExecutionSemantics(sideEffectLevel: .unspecified).runtimePolicy()
        #expect(policy.mayRunInParallel == true)
        #expect(policy.requiresApproval == false)
    }

    @Test("explicit externalMutation is not parallel-eligible")
    func explicitExternalMutationIsNotParallelEligible() {
        let policy = ToolExecutionSemantics(sideEffectLevel: .externalMutation).runtimePolicy()
        #expect(policy.mayRunInParallel == false)
        #expect(policy.requiresApproval == false)
        #expect(policy.mayRetryAutomatically == true)
    }

    @Test("readOnly and localMutation remain parallel-eligible")
    func readOnlyAndLocalMutationRemainParallelEligible() {
        #expect(ToolExecutionSemantics(sideEffectLevel: .readOnly).runtimePolicy().mayRunInParallel == true)
        #expect(ToolExecutionSemantics(sideEffectLevel: .localMutation).runtimePolicy().mayRunInParallel == true)
    }

    @Test("unsafe retry policy is not automatically retryable")
    func unsafeRetryPolicyIsNotAutomaticallyRetryable() {
        let policy = ToolExecutionSemantics(retryPolicy: .unsafe).runtimePolicy()
        #expect(policy.mayRetryAutomatically == false)
        #expect(policy.requiresApproval == false)
        #expect(policy.mayRunInParallel == true)
    }

    @Test("safe retry policy may retry automatically")
    func safeRetryPolicyMayRetryAutomatically() {
        #expect(ToolExecutionSemantics(retryPolicy: .safe).runtimePolicy().mayRetryAutomatically == true)
    }

    @Test("caller-managed retry is not automatically retryable")
    func callerManagedRetryIsNotAutomaticallyRetryable() {
        #expect(
            ToolExecutionSemantics(retryPolicy: .callerManaged).runtimePolicy().mayRetryAutomatically == false
        )
    }

    @Test("always approval requires approval without changing parallel defaults")
    func alwaysApprovalRequiresApproval() {
        let policy = ToolExecutionSemantics(approvalRequirement: .always).runtimePolicy()
        #expect(policy.requiresApproval == true)
        #expect(policy.mayRunInParallel == true)
        #expect(policy.mayRetryAutomatically == true)
    }

    @Test("never approval does not require approval")
    func neverApprovalDoesNotRequireApproval() {
        #expect(ToolExecutionSemantics(approvalRequirement: .never).runtimePolicy().requiresApproval == false)
    }
}
