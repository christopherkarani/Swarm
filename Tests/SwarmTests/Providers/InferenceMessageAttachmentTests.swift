// InferenceMessageAttachmentTests.swift
// SwarmTests
//
// Additive attachments stay off the text prompt unless capability-gated.

import Foundation
@testable import Swarm
import Testing

@Suite("InferenceMessage Attachments")
struct InferenceMessageAttachmentTests {
    private let pcm = Data([0x01, 0x02, 0x03, 0x04])

    private var audioAttachment: InferenceMessage.Attachment {
        InferenceMessage.Attachment(
            id: "utt-1",
            kind: .audio,
            mimeType: "audio/wav",
            data: pcm
        )
    }

    @Test("user factory keeps text content and stores attachments")
    func userFactoryKeepsTextContent() {
        let message = InferenceMessage.user("hi", attachments: [audioAttachment])

        #expect(message.content == "hi")
        #expect(message.body == .user("hi"))
        #expect(message.attachments.count == 1)
        #expect(message.attachments[0].id == "utt-1")
        #expect(message.attachments[0].kind == .audio)
        #expect(InferenceMessage.user("hi").attachments.isEmpty)
    }

    @Test("flattenPrompt is text only and does not include PCM")
    func flattenPromptIsTextOnly() {
        let message = InferenceMessage.user("hi", attachments: [audioAttachment])
        let flattened = InferenceMessage.flattenPrompt([message])

        #expect(flattened.contains("[User]: hi"))
        #expect(!flattened.contains("AQIDBA=="))
        #expect(!flattened.contains(String(data: pcm, encoding: .isoLatin1) ?? "\u{1}"))
        #expect(!flattened.contains("\u{1}\u{2}\u{3}\u{4}"))
    }

    @Test("envelope token counting ignores attachment bytes")
    func envelopeTokenCountingIgnoresAttachmentBytes() async {
        let short = InferenceMessage.user("hi", attachments: [audioAttachment])
        let fitted = await ContextWindow.fit(
            messages: [short],
            policy: ContextWindow.Policy(
                maxTokens: 20,
                protectLeadingSystem: false,
                alwaysKeepLast: true
            ),
            countTokens: { $0.count }
        )

        #expect(fitted.count == 1)
        #expect(fitted[0].content == "hi")
        #expect(fitted[0].attachments == [audioAttachment])
    }

    @Test("codec omits audio unless multimodalAudio is advertised")
    func codecOmitsAudioWithoutCapability() {
        let message = InferenceMessage.user("hi", attachments: [audioAttachment])
        let omitted = OpenAICompatibleCodec.encodeMessage(message)
        let included = OpenAICompatibleCodec.encodeMessage(
            message,
            capabilities: [.multimodalAudio]
        )

        #expect(omitted["content"] as? String == "hi")
        let parts = included["content"] as? [[String: Any]]
        #expect(parts?.contains { $0["type"] as? String == "text" } == true)
        #expect(parts?.contains { $0["type"] as? String == "input_audio" } == true)
        let audio = parts?.first { $0["type"] as? String == "input_audio" }
        let payload = audio?["input_audio"] as? [String: Any]
        #expect(payload?["data"] as? String == pcm.base64EncodedString())
        #expect(payload?["format"] as? String == "wav")
    }

    @Test("Foundation Models flatten ignores attachment bytes")
    func foundationModelsFlattenIgnoresAttachments() {
        let prompt = FoundationModelsPromptFlattening.flatten(
            messages: [.user("hi", attachments: [audioAttachment])],
            tools: [],
            options: InferenceOptions()
        )
        #expect(prompt.contains("User: hi"))
        #expect(!prompt.contains(pcm.base64EncodedString()))
    }

    @Test("VoiceSession rejects audio attachments without the capability")
    func voiceSessionRejectsUngatedAudio() async throws {
        let voice = VoiceSession(
            agent: MockAgentRuntime(streamTokens: ["Hi."]),
            speechToText: MockSpeechToText(),
            textToSpeech: MockTextToSpeech()
        )

        await #expect(throws: VoiceError.self) {
            try await voice.respond(to: "hi", attachments: [audioAttachment])
        }
    }
}
