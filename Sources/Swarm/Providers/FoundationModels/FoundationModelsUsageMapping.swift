import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Maps Apple session usage onto Swarm ``TokenUsage``.
///
/// `LanguageModelSession.Response.usage` exists on OS 27. OS 26 has no
/// usage field; callers get `nil` and Swarm does not invent counts.
enum FoundationModelsUsageMapping: Sendable {
    @available(macOS 27.0, iOS 27.0, visionOS 27.0, *)
    static func tokenUsage(from usage: LanguageModelSession.Usage) -> TokenUsage {
        TokenUsage(
            inputTokens: usage.input.totalTokenCount,
            outputTokens: usage.output.totalTokenCount
        )
    }

    static func tokenUsage<Content: Generable>(
        from response: LanguageModelSession.Response<Content>
    ) -> TokenUsage? {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            return tokenUsage(from: response.usage)
        }
        return nil
    }

    static func tokenUsage<Content: Generable>(
        from snapshot: LanguageModelSession.ResponseStream<Content>.Snapshot
    ) -> TokenUsage? {
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            return tokenUsage(from: snapshot.usage)
        }
        return nil
    }
}
#endif
