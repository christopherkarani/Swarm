// Agent+FoundationModelsNative.swift
// Swarm Framework
//
// Legacy helper for tests that still document the envelope fallback.
// Agent no longer uses this as the InferenceProvider seam.

import Foundation

/// Message list for a native Foundation Models session.
///
/// Matches capture mode: when ``structuredMessages`` is `nil` (`strict4k`
/// windowing and/or `PromptEnvelope` rewrite), send the stuffed envelope
/// prompt as a single user turn. Never fall back to the raw conversation
/// history — that would drop ContextCore windowing and 4K truncation.
enum FoundationModelsNativePrompt {
    static func messages(
        structuredMessages: [InferenceMessage]?,
        envelopePrompt: String
    ) -> [InferenceMessage] {
        structuredMessages ?? [.user(envelopePrompt)]
    }
}
