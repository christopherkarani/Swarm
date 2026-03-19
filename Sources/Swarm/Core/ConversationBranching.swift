import Foundation

/// Internal capability for runtimes that can create an isolated branch of their own execution state.
package protocol ConversationBranchingRuntime: AgentRuntime {
    func branchConversationRuntime() async throws -> any AgentRuntime
}

/// Internal capability for sessions that can clone themselves while preserving backend semantics.
package protocol ConversationBranchingSession: Session {
    func branchConversationSession() async throws -> any Session
}
