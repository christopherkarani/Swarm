import Foundation

/// Internal capability for runtimes that can create an isolated branch of their own execution state.
///
/// ``AgentRuntime/branchConversationRuntime()`` is now a defaulted requirement.
@available(*, deprecated, message: "branchConversationRuntime is a defaulted AgentRuntime requirement")
package protocol ConversationBranchingRuntime: AgentRuntime {}

/// Internal capability for sessions that can clone themselves while preserving backend semantics.
///
/// ``Session/branchConversationSession()`` is now a defaulted requirement.
@available(*, deprecated, message: "branchConversationSession is a defaulted Session requirement")
package protocol ConversationBranchingSession: Session {}
