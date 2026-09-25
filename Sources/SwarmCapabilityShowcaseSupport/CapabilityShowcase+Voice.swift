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

func runVoiceBargeInScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let speechToText = ShowcaseSpeechToText(
        transcripts: [SpeechTranscript(text: "hello", isFinal: true)],
        subsequentStarts: [[SpeechTranscript(text: "never mind", isFinal: true)]]
    )
    let textToSpeech = ShowcaseTextToSpeech()
    let agent = ShowcaseAgentRuntime(tokenRuns: [
        ["Hello world."],
        ["Okay then."],
    ])
    var configuration = VoiceSessionConfiguration.default
    configuration.bargeInEnabled = true
    let voice = VoiceSession(
        agent: agent,
        speechToText: speechToText,
        textToSpeech: textToSpeech,
        voiceActivityDetector: ShowcaseImmediateVAD(),
        configuration: configuration
    )

    let turn = try await voice.listenAndRespond()
    try ensure(turn.transcript == "never mind", "Expected barge-in to replace the transcript.")
    try ensure(
        turn.spokenUtterances.contains("Okay then."),
        "Expected the replacement turn to be spoken."
    )

    let body = "transcript=\(turn.transcript)\nspoken=\(turn.spokenUtterances.joined(separator: " | "))"
    let artifact = try context.writeArtifact(named: "voice-bargein.txt", contents: body)
    return .init(
        id: "voice-bargein",
        name: "Voice Barge-In",
        families: [.voice],
        status: .passed,
        summary: "Interrupted a spoken turn with a scripted VAD and spoke the replacement.",
        evidence: [
            .init(label: "voice-bargein", detail: body, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

func runVoiceWorkflowScenario(context: CapabilityScenarioContext) async throws -> CapabilityScenarioResult {
    let textToSpeech = ShowcaseTextToSpeech()
    let agent = ShowcaseAgentRuntime(tokens: ["Hello ", "world."])
    let voice = VoiceSession(
        agent: agent,
        speechToText: ShowcaseSpeechToText(transcripts: []),
        textToSpeech: textToSpeech
    )
    let runtime = VoiceTurnRuntime(voice: voice, presenting: agent)
    let result = try await Workflow().step(runtime).run("hello there")
    let spoken = await textToSpeech.spoken

    try ensure(result.output.contains("Hello world."), "Expected the workflow step to return the spoken agent output.")
    try ensure(spoken.contains("Hello world."), "Expected VoiceTurnRuntime to speak through VoiceSession.")

    let body = "output=\(result.output)\nspoken=\(spoken.joined(separator: " | "))"
    let artifact = try context.writeArtifact(named: "voice-workflow.txt", contents: body)
    return .init(
        id: "voice-workflow",
        name: "Voice Workflow",
        families: [.voice],
        status: .passed,
        summary: "Wrapped VoiceSession.respond(to:) as a Workflow step.",
        evidence: [
            .init(label: "voice-workflow", detail: body, artifactPath: context.relativeArtifactPath(for: artifact)),
        ]
    )
}

// MARK: - In-scenario doubles

private actor ShowcaseSpeechToText: SpeechToText {
    private let transcripts: [SpeechTranscript]
    private let subsequentStarts: [[SpeechTranscript]]
    private var startCount = 0

    init(transcripts: [SpeechTranscript], subsequentStarts: [[SpeechTranscript]] = []) {
        self.transcripts = transcripts
        self.subsequentStarts = subsequentStarts
    }

    nonisolated func start() -> AsyncThrowingStream<SpeechTranscript, Error> {
        StreamHelper.makeTrackedStream { continuation in
            for transcript in await self.nextBatch() {
                continuation.yield(transcript)
            }
            continuation.finish()
        }
    }

    func stop() async {}

    private func nextBatch() -> [SpeechTranscript] {
        let index = startCount
        startCount += 1
        if index == 0 { return transcripts }
        let subsequentIndex = index - 1
        guard subsequentStarts.indices.contains(subsequentIndex) else { return [] }
        return subsequentStarts[subsequentIndex]
    }
}

private actor ShowcaseImmediateVAD: VoiceActivityDetector {
    private var didFire = false

    nonisolated func start() -> AsyncThrowingStream<VoiceActivityEvent, Error> {
        StreamHelper.makeTrackedStream { continuation in
            if await self.consume() {
                continuation.yield(.speechStarted)
            }
            continuation.finish()
        }
    }

    func stop() async {}

    private func consume() -> Bool {
        if didFire { return false }
        didFire = true
        return true
    }
}

private actor ShowcaseTextToSpeech: TextToSpeech {
    private(set) var spoken: [String] = []

    func speak(_ text: String) async throws {
        // Yield the barge-in window: the VAD watcher task needs scheduling
        // time to observe speech and commit before an instant utterance
        // completes, otherwise the scenario flakes under load.
        try? await Task.sleep(for: .milliseconds(200))
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
    private let tokenRuns: [[String]]
    private var streamInvocation = 0
    private(set) var streamInputs: [String] = []

    init(tokens: [String] = [], tokenRuns: [[String]] = []) {
        self.tokens = tokens
        self.tokenRuns = tokenRuns
    }

    func run(
        _ input: String,
        session: (any Session)?,
        observer: (any AgentObserver)?
    ) async throws -> AgentResult {
        AgentResult(output: (tokenRuns.first ?? tokens).joined())
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
            for token in await self.tokensForThisStream() {
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

    private func tokensForThisStream() -> [String] {
        defer { streamInvocation += 1 }
        if tokenRuns.isEmpty {
            return tokens
        }
        return tokenRuns[min(streamInvocation, tokenRuns.count - 1)]
    }
}
