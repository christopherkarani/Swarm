import Foundation

/// Image sidecar normalized for Apple multimodal prompts.
///
/// Pure value (no `FoundationModels` import): extraction from
/// ``InferenceMessage/Attachment`` stays unit testable on every platform.
/// Apple rendering (`Transcript` segments, `Prompt` attachments) is OS 27 only.
struct PendingImage: Sendable, Equatable {
    /// Attachment id, reused as the Apple attachment label.
    var label: String
    /// In-memory image bytes, when the attachment carries them.
    var data: Data?
    /// File URL, when the attachment references one.
    var fileURL: URL?
}

/// Extracts and renders ``InferenceMessage`` image attachments.
///
/// Audio attachments and attachments with neither bytes nor a file URL are
/// ignored. Remote (non-file) URLs without bytes are skipped: the provider
/// never fetches over the network.
enum FoundationModelsImageAttachments: Sendable {
    /// Image sidecars on `message`, in attachment order. Empty when none.
    static func pendingImages(in message: InferenceMessage) -> [PendingImage] {
        message.attachments.compactMap { attachment in
            guard attachment.kind == .image else { return nil }
            guard attachment.data != nil || attachment.fileURL != nil else { return nil }
            return PendingImage(
                label: attachment.id,
                data: attachment.data,
                fileURL: attachment.fileURL
            )
        }
    }

    /// Whether a file URL is safe to hand to Apple image initializers.
    static func isLocalFileURL(_ url: URL) -> Bool {
        url.isFileURL
    }
}

#if canImport(FoundationModels)
import FoundationModels

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

@available(macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0, *)
@available(tvOS, unavailable)
extension FoundationModelsImageAttachments {
    /// `Transcript` segments for one prompt: text first, then one attachment
    /// segment per decodable image. Undecodable images are omitted.
    static func transcriptSegments(text: String, images: [PendingImage]) -> [Transcript.Segment] {
        var segments: [Transcript.Segment] = [
            .text(Transcript.TextSegment(content: text)),
        ]
        for image in images {
            if let segment = attachmentSegment(for: image) {
                segments.append(segment)
            }
        }
        return segments
    }

    /// Multimodal `Prompt`: the text plus one attachment per decodable image.
    ///
    /// `Prompt` has no append API, so parts compose through the homogeneous
    /// `[Prompt]` `PromptRepresentable` conformance.
    static func prompt(text: String, images: [PendingImage]) -> Prompt {
        var parts: [Prompt] = [Prompt(text)]
        for image in images {
            if let attachment = promptAttachment(for: image) {
                parts.append(Prompt(attachment))
            }
        }
        return Prompt(parts)
    }

    private static func attachmentSegment(for image: PendingImage) -> Transcript.Segment? {
        if let url = image.fileURL,
           isLocalFileURL(url),
           image.data == nil
        {
            return .attachment(
                Transcript.AttachmentSegment(
                    content: .image(Transcript.ImageAttachment(imageURL: url)),
                    label: image.label
                )
            )
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        if let cgImage = cgImage(from: image) {
            return .attachment(
                Transcript.AttachmentSegment(
                    content: .image(Transcript.ImageAttachment(cgImage)),
                    label: image.label
                )
            )
        }
        #endif
        return nil
    }

    private static func promptAttachment(for image: PendingImage) -> Attachment<ImageAttachmentContent>? {
        if let url = image.fileURL,
           isLocalFileURL(url),
           image.data == nil
        {
            return Attachment(imageURL: url).label(image.label)
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        if let cgImage = cgImage(from: image) {
            return Attachment(cgImage).label(image.label)
        }
        #endif
        return nil
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    /// Decodes attachment bytes (or a local file) into a `CGImage`.
    static func cgImage(from image: PendingImage) -> CGImage? {
        if let data = image.data {
            return cgImage(from: data)
        }
        if let url = image.fileURL,
           isLocalFileURL(url),
           let data = try? Data(contentsOf: url)
        {
            return cgImage(from: data)
        }
        return nil
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    #endif
}
#endif
