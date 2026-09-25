// VoiceTurnRuntime.swift
// Swarm Framework
//
// AgentRuntime wrapper around VoiceSession.respond(to:).

import Foundation

/// Presents a ``VoiceSession`` as an ``AgentRuntime`` so hosts can write
/// `Workflow().step(voiceTurn)` or pass it to `JobChild`.
///
/// `run` and `stream` inject the input string via ``VoiceSession/respond(to:)``.
/// They do not open the microphone. Durable workflows still checkpoint text only.
public struct VoiceTurnRuntime: AgentRuntime {
    private let voice: VoiceSession
    private let presented: any AgentRuntime

    /// Creates a workflow/job adapter.
    ///
    /// - Parameters:
    ///   - voice: Session that will speak the turn.
    ///   - presented: Runtime whose metadata (`tools`, `instructions`, …) is
    ///     forwarded. Typically the same agent stored in `voice`.
    public init(voice: VoiceSession, presenting presented: any AgentRuntime) {
        self.voice = voice
        self.presented = presented
    }

    public nonisolated var name: String { presented.name }
    public nonisolated var tools: [any AnyJSONTool] { presented.tools }
    public nonisolated var instructions: String { presented.instructions }
    public nonisolated var configuration: AgentConfiguration { presented.configuration }
    public nonisolated var memory: (any Memory)? { presented.memory }
    public nonisolated var inferenceProvider: (any InferenceProvider)? { presented.inferenceProvider }
    public nonisolated var tracer: (any Tracer)? { presented.tracer }
    public nonisolated var handoffs: [AnyHandoffConfiguration] { presented.handoffs }
    public nonisolated var inputGuardrails: [any InputGuardrail] { presented.inputGuardrails }
    public nonisolated var outputGuardrails: [any OutputGuardrail] { presented.outputGuardrails }

    public func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        _ = session
        await observer?.onAgentStart(context: nil, agent: self, input: input)
        let turn = try await voice.respond(to: input)
        await observer?.onAgentEnd(context: nil, agent: self, result: turn.agentResult)
        return turn.agentResult
    }

    public nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            continuation.yield(.lifecycle(.started(input: input)))
            do {
                let result = try await self.run(input, session: session, observer: observer)
                continuation.yield(.lifecycle(.completed(result: result)))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func cancel() async {
        await voice.stop()
        await presented.cancel()
    }
}
