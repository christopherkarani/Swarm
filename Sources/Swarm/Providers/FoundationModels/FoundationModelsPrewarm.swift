import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// When a newly created `LanguageModelSession` should be prewarmed.
///
/// Capture (`ownsToolLoop == false`) is opt-in via `prewarmOnInit` on every OS.
/// Owned-loop sessions on OS 27 always prewarm after create / recreate; on
/// OS 26 they still follow the flag. Both `makeSession` overloads call
/// ``apply(to:prewarmOnInit:ownsToolLoop:)`` once, including detached
/// busy-slot `create()`.
enum FoundationModelsPrewarm: Sendable {
    /// Returns whether to call `LanguageModelSession.prewarm(promptPrefix:)`.
    ///
    /// `os27Available` is injected so tests can cover OS 26 without a live
    /// older SDK. Production passes `#available(macOS 27.0, iOS 27.0, visionOS 27.0, *)`.
    static func shouldPrewarm(
        prewarmOnInit: Bool,
        ownsToolLoop: Bool,
        os27Available: Bool
    ) -> Bool {
        prewarmOnInit || (ownsToolLoop && os27Available)
    }

    #if canImport(FoundationModels)
    /// Prewarms `session` at most once when ``shouldPrewarm(prewarmOnInit:ownsToolLoop:os27Available:)`` is true.
    ///
    /// `promptPrefix` stays `nil`.
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    static func apply(
        to session: LanguageModelSession,
        prewarmOnInit: Bool,
        ownsToolLoop: Bool
    ) {
        let os27Available: Bool
        if #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) {
            os27Available = true
        } else {
            os27Available = false
        }
        guard shouldPrewarm(
            prewarmOnInit: prewarmOnInit,
            ownsToolLoop: ownsToolLoop,
            os27Available: os27Available
        ) else {
            return
        }
        session.prewarm(promptPrefix: nil)
    }
    #endif
}
