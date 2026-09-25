import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Foundation Models image attachments")
struct FoundationModelsImageAttachmentsTests {
    private func imageAttachment(
        id: String = "img-1",
        data: Data? = Data([0x89, 0x50]),
        fileURL: URL? = nil
    ) -> InferenceMessage.Attachment {
        InferenceMessage.Attachment(
            id: id,
            kind: .image,
            mimeType: "image/png",
            data: data,
            fileURL: fileURL
        )
    }

    @Test("image attachments extract in order")
    func imageAttachmentsExtractInOrder() {
        let message = InferenceMessage.user(
            "describe these",
            attachments: [
                imageAttachment(id: "a"),
                imageAttachment(id: "b"),
            ]
        )
        let images = FoundationModelsImageAttachments.pendingImages(in: message)
        #expect(images.map { $0.label } == ["a", "b"])
        #expect(images.allSatisfy { $0.data != nil })
    }

    @Test("audio and empty attachments are ignored")
    func audioAndEmptyAttachmentsIgnored() {
        let message = InferenceMessage.user(
            "hi",
            attachments: [
                InferenceMessage.Attachment(id: "s", kind: .audio, mimeType: "audio/wav"),
                InferenceMessage.Attachment(id: "e", kind: .image, mimeType: "image/png"),
            ]
        )
        #expect(FoundationModelsImageAttachments.pendingImages(in: message).isEmpty)
    }

    @Test("only file URLs count as local")
    func onlyFileURLsAreLocal() {
        #expect(FoundationModelsImageAttachments.isLocalFileURL(URL(fileURLWithPath: "/tmp/a.png")))
        #expect(!FoundationModelsImageAttachments.isLocalFileURL(URL(string: "https://example.com/a.png")!))
    }

    @Test("capture mapEntries carries user images")
    func captureMapEntriesCarriesImages() {
        let attachment = imageAttachment()
        let mapped = FoundationModelsTranscriptSeed.mapEntries(
            messages: [.user("look", attachments: [attachment])],
            instructions: nil
        )
        #expect(mapped.canRehydrate)
        #expect(mapped.entries == [
            .prompt(
                text: "look",
                images: [PendingImage(label: "img-1", data: attachment.data, fileURL: nil)]
            ),
        ])
    }

    @Test("image-only user message still maps")
    func imageOnlyUserMessageMaps() {
        let mapped = FoundationModelsTranscriptSeed.mapEntries(
            messages: [.user("", attachments: [imageAttachment()])],
            instructions: nil
        )
        #expect(mapped.entries.count == 1)
    }

    @Test("capture seed pops pending images with the pending prompt")
    func captureSeedPopsPendingImages() {
        let attachment = imageAttachment()
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [
                .user("u1"),
                .user("u2", attachments: [attachment]),
            ],
            instructions: nil
        )
        #expect(seed.canRehydrate)
        #expect(seed.pendingPrompt == "u2")
        #expect(seed.pendingImages.map { $0.label } == ["img-1"])
        #expect(seed.seedEntries == [.prompt(text: "u1", images: [])])
    }

    @Test("single-message seed pops pending images with the pending prompt")
    func singleMessageSeedPopsPendingImages() {
        let seed = FoundationModelsTranscriptSeed.seed(
            messages: [.user("u1", attachments: [imageAttachment(id: "b")])],
            instructions: nil
        )
        #expect(seed.pendingPrompt == "u1")
        #expect(seed.pendingImages.map { $0.label } == ["b"])
    }

    #if canImport(FoundationModels)
    @Test("transcript segments are text plus one attachment per decodable image")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func transcriptSegmentsCombineTextAndImages() {
        let png = Data(base64Encoded: Self.tinyPNG)!
        let segments = FoundationModelsImageAttachments.transcriptSegments(
            text: "look",
            images: [
                PendingImage(label: "good", data: png, fileURL: nil),
                PendingImage(label: "bad", data: Data([0x00]), fileURL: nil),
            ]
        )
        #expect(segments.count == 2)
        guard case .text = segments[0], case .attachment = segments[1] else {
            Issue.record("expected text then attachment segments")
            return
        }
    }

    @Test("garbage bytes do not decode")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func garbageBytesDoNotDecode() {
        #expect(FoundationModelsImageAttachments.cgImage(from: Data([0x00, 0x01])) == nil)
        let png = Data(base64Encoded: Self.tinyPNG)!
        #expect(FoundationModelsImageAttachments.cgImage(from: png) != nil)
    }

    @Test("file URL images decode from disk")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func fileURLImagesDecodeFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data(base64Encoded: Self.tinyPNG)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = PendingImage(label: "disk", data: nil, fileURL: url)
        #expect(FoundationModelsImageAttachments.cgImage(from: image) != nil)
    }

    @Test("remote URLs without bytes render text-only segments")
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    func remoteURLsWithoutBytesRenderTextOnly() {
        let segments = FoundationModelsImageAttachments.transcriptSegments(
            text: "look",
            images: [
                PendingImage(
                    label: "remote",
                    data: nil,
                    fileURL: URL(string: "https://example.com/a.png")
                ),
            ]
        )
        #expect(segments.count == 1)
        guard case .text = segments[0] else {
            Issue.record("expected a single text segment")
            return
        }
    }

    /// 1x1 PNG.
    private static let tinyPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    #endif
}
