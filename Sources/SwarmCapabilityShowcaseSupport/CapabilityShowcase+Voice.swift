// CapabilityShowcase+Voice.swift
// SwarmCapabilityShowcaseSupport
//
// Deterministic VoiceSession scenario — mocks only, no microphone.

import Foundation
import Swarm

func runVoiceScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let speechToText = ShowcaseSpeechToText(transcripts: [
        SpeechTranscript(text: "hel", isFinal: false),
        SpeechTranscript(text: "hello there", isFinal: true),
    ])
    let textToSpeech = ShowcaseTextToSpeech()
    let agent = ShowcaseAgentRuntime(tokens: ["Hello ", "world."])
    let voice = VoiceSession(
        agent: agent,
        speechToText: speechToText,
        textToSpeech: textToSpeech
    )

    let turn = try await voice.listenAndRespond()
    let spoken = await textToSpeech.spoken
    let streamInputs = await agent.streamInputs

    try ensure(turn.transcript == "hello there", "Expected the final transcript to reach VoiceSession.")
    try ensure(streamInputs == ["hello there"], "Expected the agent to receive the final transcript only.")
    try ensure(
        spoken.contains("Hello world."),
        "Expected sentence-buffered speech from output tokens."
    )
    try ensure(
        !spoken.contains(where: { $0.localizedCaseInsensitiveContains("thinking") }),
        "Thinking text must not be spoken."
    )
    try ensure(
        turn.spokenUtterances == spoken,
        "Turn result spoken utterances must match the TTS adapter."
    )

    let body = [
        "transcript=\(turn.transcript)",
        "spoken=\(spoken.joined(separator: " | "))",
        "agentOutput=\(turn.agentResult.output)",
    ].joined(separator: "\n")
    let artifact = try context.writeArtifact(named: "voice.txt", contents: body)

    return .init(
        id: "voice",
        name: "Voice",
        families: [.voice],
        status: .passed,
        summary: "Ran a turn-based VoiceSession with scripted STT/TTS and streamed output tokens.",
        evidence: [
            .init(label: "voice", detail: body, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

// MARK: - In-scenario doubles

private actor ShowcaseSpeechToText: SpeechToText {
    private let transcripts: [SpeechTranscript]

    init(transcripts: [SpeechTranscript]) {
        self.transcripts = transcripts
    }

    nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for transcript in await self.transcripts {
                continuation.yield(transcript)
            }
            continuation.finish()
        }
    }

    func stop() async {}
}

private actor ShowcaseTextToSpeech: TextToSpeech {
    private(set) var spoken: [String] = []

    func speak(_ text: String) async throws {
        spoken.append(text)
    }

    func stop() async {}
}

private actor ShowcaseAgentRuntime: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions = "showcase voice"
    nonisolated let configuration = AgentConfiguration.default
    nonisolated let memory: (any Memory)? = nil
    nonisolated let inferenceProvider: (any InferenceProvider)? = nil
    nonisolated let tracer: (any Tracer)? = nil
    nonisolated let handoffs: [AnyHandoffConfiguration] = []
    nonisolated let inputGuardrails: [any InputGuardrail] = []
    nonisolated let outputGuardrails: [any OutputGuardrail] = []

    private let tokens: [String]
    private(set) var streamInputs: [String] = []

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        AgentResult(output: tokens.joined())
    }

    nonisolated func stream(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            await self.record(input)
            continuation.yield(.lifecycle(.started(input: input)))
            continuation.yield(.output(.thinking(thought: "Thinking")))
            var aggregate = ""
            for token in await self.tokens {
                aggregate += token
                continuation.yield(.output(.token(token)))
            }
            continuation.yield(.lifecycle(.completed(result: AgentResult(output: aggregate))))
            continuation.finish()
        }
    }

    func cancel() async {}

    private func record(_ input: String) {
        streamInputs.append(input)
    }
}
