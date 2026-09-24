// VoiceSession.swift
// Swarm Framework
//
// Turn-based coordinator: listen → Agent.stream → sentence-spoken reply.

import Foundation

/// Coordinates one spoken (or injected) utterance through an ``AgentRuntime``.
///
/// `VoiceSession` is not an Agent. It owns turn identity — listen, speak queue,
/// and the in-flight flag — and forwards text to `agent.stream` by default.
/// Audio attachments are opt-in and capability-gated.
///
/// Barge-in is opt-in via ``VoiceSessionConfiguration/bargeInEnabled``.
/// ``stop()`` remains the host interrupt hook.
public actor VoiceSession {
    private let agent: any AgentRuntime
    private let speechToText: any SpeechToText
    private let textToSpeech: any TextToSpeech
    private let voiceActivityDetector: (any VoiceActivityDetector)?
    private let session: (any Session)?
    private let configuration: VoiceSessionConfiguration

    /// Long-lived event stream. ``stop()`` does not finish it; deinit does.
    public nonisolated let events: AsyncStream<VoiceEvent>
    private nonisolated let eventContinuation: AsyncStream<VoiceEvent>.Continuation

    private var isTurnInFlight = false
    private var isCancelled = false
    private var isGenerating = false
    private var pendingBargeIn = false
    private var spokenUtterances: [String] = []
    private var speakFailure: VoiceError?
    private var bargeInWatcher: Task<Void, Never>?

    /// Creates a voice coordinator around an existing agent.
    ///
    /// - Parameters:
    ///   - agent: Text-in / text-out runtime by default.
    ///   - speechToText: Capture adapter. Unused by ``respond(to:)``.
    ///   - textToSpeech: Speak adapter.
    ///   - session: Optional conversation history forwarded to `agent.stream`.
    ///   - voiceActivityDetector: Optional barge-in detector.
    ///   - configuration: Sentence split and adapter settings.
    public init(
        agent: any AgentRuntime,
        speechToText: any SpeechToText,
        textToSpeech: any TextToSpeech,
        session: (any Session)? = nil,
        voiceActivityDetector: (any VoiceActivityDetector)? = nil,
        configuration: VoiceSessionConfiguration = .default
    ) {
        self.agent = agent
        self.speechToText = speechToText
        self.textToSpeech = textToSpeech
        self.session = session
        self.voiceActivityDetector = voiceActivityDetector
        self.configuration = configuration
        let (stream, continuation) = AsyncStream<VoiceEvent>.makeStream()
        events = stream
        eventContinuation = continuation
        continuation.yield(.phase(.idle))
    }

    deinit {
        eventContinuation.finish()
    }

    /// Listens for one utterance, then runs ``respond(to:)`` on the transcript.
    public func listenAndRespond() async throws -> VoiceTurnResult {
        try beginTurn()
        do {
            return try await listenThenRespondLoop()
        } catch {
            finishFailedTurn()
            throw error
        }
    }

    /// Runs one agent turn from an injected transcript. Does not open STT.
    public func respond(
        to transcript: String,
        attachments: [InferenceMessage.Attachment] = []
    ) async throws -> VoiceTurnResult {
        try beginTurn()
        do {
            return try await respondLoop(transcript, attachments: attachments)
        } catch {
            finishFailedTurn()
            throw error
        }
    }

    /// Cancels the in-flight turn. Does not finish ``events``.
    public func stop() async {
        isCancelled = true
        pendingBargeIn = false
        bargeInWatcher?.cancel()
        bargeInWatcher = nil
        await voiceActivityDetector?.stop()
        await speechToText.stop()
        await agent.cancel()
        await textToSpeech.stop()
        emit(.phase(.idle))
    }

    private func beginTurn() throws {
        if isTurnInFlight {
            throw VoiceError.busy
        }
        isTurnInFlight = true
        isCancelled = false
        isGenerating = false
        pendingBargeIn = false
        spokenUtterances = []
        speakFailure = nil
    }

    private func finishFailedTurn() {
        isTurnInFlight = false
        isGenerating = false
        pendingBargeIn = false
        bargeInWatcher?.cancel()
        bargeInWatcher = nil
        emit(.phase(.idle))
    }

    private func finishSucceededTurn() {
        isTurnInFlight = false
        isGenerating = false
        pendingBargeIn = false
        bargeInWatcher?.cancel()
        bargeInWatcher = nil
        emit(.phase(.idle))
    }

    private func emit(_ event: VoiceEvent) {
        eventContinuation.yield(event)
    }

    private func listenThenRespondLoop() async throws -> VoiceTurnResult {
        emit(.phase(.listening))
        let transcript = try await collectFinalTranscript()
        return try await respondLoop(transcript, attachments: [])
    }

    private func respondLoop(
        _ transcript: String,
        attachments: [InferenceMessage.Attachment]
    ) async throws -> VoiceTurnResult {
        do {
            let result = try await runRespond(transcript, attachments: attachments)
            if pendingBargeIn {
                return try await replaceAfterBargeIn()
            }
            return result
        } catch {
            if pendingBargeIn, !isHostCancelled() {
                return try await replaceAfterBargeIn()
            }
            throw error
        }
    }

    private func isHostCancelled() -> Bool {
        isCancelled && !pendingBargeIn
    }

    private func replaceAfterBargeIn() async throws -> VoiceTurnResult {
        pendingBargeIn = false
        isCancelled = false
        speakFailure = nil
        spokenUtterances = []
        bargeInWatcher?.cancel()
        bargeInWatcher = nil
        await voiceActivityDetector?.stop()
        emit(.phase(.listening))
        let next = try await collectFinalTranscript()
        return try await respondLoop(next, attachments: [])
    }

    private func collectFinalTranscript() async throws -> String {
        if isCancelled, !pendingBargeIn {
            throw VoiceError.cancelled
        }

        let stream = speechToText.start()
        var lastPartial: String?
        var lastFinal: String?

        do {
            for try await transcript in stream {
                if isCancelled, !pendingBargeIn {
                    throw VoiceError.cancelled
                }
                if transcript.isFinal {
                    lastFinal = transcript.text
                } else {
                    lastPartial = transcript.text
                    emit(.partialTranscript(transcript.text))
                }
            }
        } catch let error as VoiceError {
            throw error
        } catch is CancellationError {
            throw VoiceError.cancelled
        } catch {
            if isCancelled, !pendingBargeIn {
                throw VoiceError.cancelled
            }
            throw VoiceError.speechFailed(reason: String(describing: error))
        }

        if isCancelled, !pendingBargeIn {
            throw VoiceError.cancelled
        }

        return lastFinal ?? lastPartial ?? ""
    }

    private func runRespond(
        _ transcript: String,
        attachments: [InferenceMessage.Attachment]
    ) async throws -> VoiceTurnResult {
        if isCancelled, !pendingBargeIn {
            throw VoiceError.cancelled
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoiceError.emptyTranscript
        }

        if !attachments.isEmpty {
            let capabilities = agent.inferenceProvider.map {
                InferenceProviderCapabilities.resolved(for: $0)
            } ?? []
            guard capabilities.contains(.multimodalAudio) else {
                throw VoiceError.speechFailed(
                    reason: "Provider does not advertise multimodalAudio."
                )
            }
        }

        emit(.finalTranscript(trimmed))
        emit(.phase(.running))

        var buffer = VoiceSentenceBuffer(
            minSpeakCharacters: configuration.minSpeakCharacters,
            sentenceTerminators: configuration.sentenceTerminators
        )
        var agentResult: AgentResult?
        var sawSpokenOutput = false

        let (sentenceStream, sentenceContinuation) = AsyncStream<String>.makeStream()
        let speaker = Task {
            for await sentence in sentenceStream {
                do {
                    try await self.speakUtterance(sentence)
                } catch {
                    self.recordSpeakFailure(error)
                    break
                }
            }
        }

        func enqueue(_ sentences: [String]) {
            for sentence in sentences {
                sentenceContinuation.yield(sentence)
            }
        }

        isGenerating = true
        do {
            if !attachments.isEmpty, let provider = agent.inferenceProvider {
                let output = try await provider.generate(
                    messages: [.user(trimmed, attachments: attachments)],
                    options: agent.configuration.inferenceOptions
                )
                agentResult = AgentResult(output: output)
                emit(.agent(.lifecycle(.started(input: trimmed))))
                emit(.agent(.lifecycle(.completed(result: agentResult!))))
                if output.contains(where: { !$0.isWhitespace }) {
                    enqueue(buffer.append(output))
                    if let remainder = buffer.flush() {
                        enqueue([remainder])
                    }
                }
            } else {
                for try await event in agent.stream(trimmed, session: session, observer: nil) {
                    if pendingBargeIn {
                        throw VoiceError.cancelled
                    }
                    if isCancelled {
                        throw VoiceError.cancelled
                    }
                    emit(.agent(event))
                    switch event {
                    case let .output(.token(text)), let .output(.chunk(text)):
                        sawSpokenOutput = true
                        enqueue(buffer.append(text))
                    case let .lifecycle(.completed(result)):
                        agentResult = result
                    case let .lifecycle(.failed(error)):
                        throw error
                    case let .lifecycle(.guardrailFailed(error)):
                        throw error
                    case .lifecycle(.cancelled):
                        throw VoiceError.cancelled
                    default:
                        break
                    }
                }
            }
        } catch {
            isGenerating = false
            sentenceContinuation.finish()
            await speaker.value
            stopBargeInWatcher()
            throw mappedTurnError(error)
        }

        isGenerating = false

        if let remainder = buffer.flush() {
            enqueue([remainder])
        } else if !sawSpokenOutput,
                  let output = agentResult?.output,
                  output.contains(where: { !$0.isWhitespace }) {
            enqueue(buffer.append(output))
            if let remainder = buffer.flush() {
                enqueue([remainder])
            }
        }

        sentenceContinuation.finish()
        await speaker.value
        stopBargeInWatcher()

        if pendingBargeIn {
            throw VoiceError.cancelled
        }
        if isCancelled {
            throw VoiceError.cancelled
        }
        if let speakFailure {
            throw speakFailure
        }
        guard let result = agentResult else {
            throw VoiceError.agentFinishedWithoutResult
        }

        let turn = VoiceTurnResult(
            transcript: trimmed,
            agentResult: result,
            spokenUtterances: spokenUtterances
        )
        finishSucceededTurn()
        return turn
    }

    private func startBargeInWatcherIfNeeded() {
        guard configuration.bargeInEnabled, let detector = voiceActivityDetector else {
            return
        }
        bargeInWatcher?.cancel()
        bargeInWatcher = Task {
            do {
                for try await event in detector.start() {
                    if case .speechStarted = event {
                        await self.commitBargeIn()
                        break
                    }
                }
            } catch {
                return
            }
        }
    }

    private func stopBargeInWatcher() {
        bargeInWatcher?.cancel()
        bargeInWatcher = nil
    }

    private func commitBargeIn() async {
        guard configuration.bargeInEnabled, !pendingBargeIn else { return }
        pendingBargeIn = true
        isCancelled = true
        emit(.interrupted(transcriptSoFar: spokenUtterances.joined(separator: " ")))
        await textToSpeech.stop()
        await agent.cancel()
    }

    private func speakUtterance(_ sentence: String) async throws {
        guard !isCancelled, !pendingBargeIn else {
            return
        }
        startBargeInWatcherIfNeeded()
        emit(.phase(.speaking))
        emit(.speaking(sentence))
        do {
            try await textToSpeech.speak(sentence)
        } catch let error as VoiceError {
            throw error
        } catch is CancellationError {
            throw VoiceError.cancelled
        } catch {
            throw VoiceError.synthesisFailed(reason: String(describing: error))
        }
        guard !isCancelled, !pendingBargeIn else {
            return
        }
        spokenUtterances.append(sentence)
        emit(.speakingFinished(sentence))
        if isGenerating && !isCancelled {
            emit(.phase(.running))
        }
    }

    private func recordSpeakFailure(_ error: Error) {
        if pendingBargeIn {
            return
        }
        if let voiceError = error as? VoiceError {
            speakFailure = voiceError
        } else if error is CancellationError {
            speakFailure = .cancelled
        } else {
            speakFailure = .synthesisFailed(reason: String(describing: error))
        }
    }

    private func mappedTurnError(_ error: Error) -> Error {
        if pendingBargeIn {
            return VoiceError.cancelled
        }
        if isCancelled {
            return VoiceError.cancelled
        }
        if error is CancellationError {
            return VoiceError.cancelled
        }
        return error
    }
}
