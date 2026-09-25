import Foundation

/// Maps a resolved Swarm ``Profile`` onto owned-loop session inputs.
///
/// This is **not** Apple's `LanguageModelSession.DynamicProfile`. Swarm
/// ``DynamicProfile`` / ``Profile`` / ``ProfileHistoryPolicy`` stay Swarm
/// types. Owned-loop uses the resolved instructions, tool filter, and
/// history policy. Capture still goes through ``DynamicProfileResolution``.
///
/// Transcript seeding itself lives in ``FoundationModelsTranscriptSeed``,
/// shared with the capture turn; this module only adds profile resolution.
enum FoundationModelsAppleProfileBridge: Sendable {
    /// Full resolve of a Swarm profile for an owned-loop turn.
    struct Plan: Sendable, Equatable {
        var instructions: String?
        var tools: [ToolSchema]
        var options: InferenceOptions
        var messages: [InferenceMessage]
        var entries: [FoundationModelsTranscriptSeed.Entry]
        var canRehydrateTranscript: Bool
    }

    static func plan(
        profile: Profile?,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        baseInstructions: String?
    ) -> Plan {
        let applied = DynamicProfileResolution.apply(
            profile,
            messages: messages,
            tools: tools,
            options: options,
            baseInstructions: baseInstructions
        )
        let withSystem = DynamicProfileResolution.messagesByInjectingInstructions(
            applied.instructions,
            into: applied.messages
        )
        let mapped = FoundationModelsTranscriptSeed.mapEntries(
            messages: withSystem,
            instructions: applied.instructions
        )
        return Plan(
            instructions: applied.instructions,
            tools: applied.tools,
            options: applied.options,
            messages: withSystem,
            entries: mapped.entries,
            canRehydrateTranscript: mapped.canRehydrate
        )
    }
}
