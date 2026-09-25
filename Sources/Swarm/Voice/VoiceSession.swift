// VoiceSession.swift
// Swarm Framework
//
// Turn-based coordinator: listen → Agent.stream → sentence-spoken reply.

import Foundation

/// Coordinates one spoken (or injected) utterance through an ``AgentRuntime``.
///
/// `VoiceSession` is not an Agent. It owns turn identity — listen, speak queue,
/// and the in-flight flag — and forwards text to `agent.stream`. Swarm does
/// not accept audio on Agent or `InferenceMessage`.
///
/// v1 is turn-based: one utterance, one stream, serial speak. Barge-in is not
/// in v1; ``stop()`` is the interrupt hook.
public actor VoiceSession {
    private let agent: any AgentRuntime
    private let speechToText: any SpeechToText
    private let textToSpeech: any TextToSpeech
    private let session: (any Session)?
    private let configuration: VoiceSessionConfiguration

    /// Long-lived event stream. ``stop()`` does not finish it; deinit does.
    public nonisolated let events: AsyncStream<VoiceEvent>
    private nonisolated let eventContinuation: AsyncStream<VoiceEvent>.Continuation

    private var isTurnInFlight = false
    private var isCancelled = false
    private var isGenerating = false
    private var spokenUtterances: [String] = []
    private var speakFailure: VoiceError?

    /// Creates a voice coordinator around an existing agent.
    ///
    /// - Parameters:
    ///   - agent: Text-in / text-out runtime. Audio is never passed here.
    ///   - speechToText: Capture adapter. Unused by ``respond(to:)``.
    ///   - textToSpeech: Speak adapter.
    ///   - session: Optional conversation history forwarded to `agent.stream`.
    ///   - configuration: Sentence split and adapter settings.
    public init(
        agent: any AgentRuntime,
        speechToText: any SpeechToText,
        textToSpeech: any TextToSpeech,
        session: (any Session)? = nil,
        configuration: VoiceSessionConfiguration = .default
    ) {
        self.agent = agent
        self.speechToText = speechToText
        self.textToSpeech = textToSpeech
        self.session = session
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
            emit(.phase(.listening))
            let transcript = try await collectFinalTranscript()
            return try await runRespond(transcript)
        } catch {
            finishFailedTurn()
            throw error
        }
    }

    /// Runs one agent turn from an injected transcript. Does not open STT.
    public func respond(to transcript: String) async throws -> VoiceTurnResult {
        try beginTurn()
        do {
            return try await runRespond(transcript)
        } catch {
            finishFailedTurn()
            throw error
        }
    }

    /// Cancels the in-flight turn. Does not finish ``events``.
    public func stop() async {
        isCancelled = true
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
        spokenUtterances = []
        speakFailure = nil
    }

    private func finishFailedTurn() {
        isTurnInFlight = false
        isGenerating = false
        emit(.phase(.idle))
    }

    private func finishSucceededTurn() {
        isTurnInFlight = false
        isGenerating = false
        emit(.phase(.idle))
    }

    private func emit(_ event: VoiceEvent) {
        eventContinuation.yield(event)
    }

    private func collectFinalTranscript() async throws -> String {
        if isCancelled {
            throw VoiceError.cancelled
        }

        let stream = speechToText.start()
        var lastPartial: String?
        var lastFinal: String?

        do {
            for try await transcript in stream {
                if isCancelled {
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
            if isCancelled {
                throw VoiceError.cancelled
            }
            throw VoiceError.speechFailed(reason: String(describing: error))
        }

        if isCancelled {
            throw VoiceError.cancelled
        }

        return lastFinal ?? lastPartial ?? ""
    }

    private func runRespond(_ transcript: String) async throws -> VoiceTurnResult {
        if isCancelled {
            throw VoiceError.cancelled
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoiceError.emptyTranscript
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
            for try await event in agent.stream(trimmed, session: session, observer: nil) {
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
        } catch {
            isGenerating = false
            sentenceContinuation.finish()
            await speaker.value
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

    private func speakUtterance(_ sentence: String) async throws {
        guard !isCancelled else {
            return
        }
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
        spokenUtterances.append(sentence)
        emit(.speakingFinished(sentence))
        if isGenerating && !isCancelled {
            emit(.phase(.running))
        }
    }

    private func recordSpeakFailure(_ error: Error) {
        if let voiceError = error as? VoiceError {
            speakFailure = voiceError
        } else if error is CancellationError {
            speakFailure = .cancelled
        } else {
            speakFailure = .synthesisFailed(reason: String(describing: error))
        }
    }

    private func mappedTurnError(_ error: Error) -> Error {
        if isCancelled {
            return VoiceError.cancelled
        }
        if error is CancellationError {
            return VoiceError.cancelled
        }
        return error
    }
}
