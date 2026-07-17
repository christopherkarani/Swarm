// DynamicProfile.swift
// Swarm Framework
//
// Swarm Dynamic Profiles — Apple WWDC 2026–aligned agent configuration.
//
// Apple's FoundationModels `LanguageModelSession.DynamicProfile` API is documented
// for WWDC 2026 but is **not** present in the macOS 26.2 / Xcode SDK shipping with
// this repository's toolchain (`DynamicProfile` symbol count = 0 in the
// FoundationModels.swiftinterface). Until that SDK lands, Swarm provides a
// compatible profile model that:
//
// 1. Re-resolves instructions, tools, options, and history policy every turn
//    (matching Apple's "body is re-evaluated each prompt" semantics).
// 2. Supports baton-pass mode switching via ``ProfileMode``.
// 3. Composes reusable instruction + tool bundles via ``DynamicInstructions``.
// 4. Plugs into ``FoundationModelsInferenceProvider`` today.
//
// When Apple's native API is available, a future revision can bridge
// ``DynamicProfile`` → `LanguageModelSession(profile:)` without changing call sites.

import Foundation

// MARK: - Profile

/// A single agent configuration phase (Apple-style `LanguageModelSession.Profile`).
///
/// Profiles group instructions, tool visibility, generation overrides, and
/// transcript history policy. A ``DynamicProfile`` resolves one of these on
/// every generation turn.
public struct Profile: Sendable, Equatable {
    /// Stable identifier for logging and handoff tools (e.g. `"brainstorm"`, `"review"`).
    public var id: String

    /// System-level instructions for this phase.
    public var instructions: String

    /// Which tools from the request schema list are visible to the model.
    public var toolFilter: ProfileToolFilter

    /// Optional generation overrides applied on top of the request's `InferenceOptions`.
    public var generation: ProfileGenerationOverrides

    /// How conversation history is transformed before prompting.
    public var history: ProfileHistoryPolicy

    /// Creates a profile.
    public init(
        id: String,
        instructions: String,
        toolFilter: ProfileToolFilter = .all,
        generation: ProfileGenerationOverrides = .init(),
        history: ProfileHistoryPolicy = .keepAll
    ) {
        self.id = id
        self.instructions = instructions
        self.toolFilter = toolFilter
        self.generation = generation
        self.history = history
    }

    /// Creates a profile from composable ``DynamicInstructions``.
    public init(
        id: String,
        dynamicInstructions: DynamicInstructions,
        toolFilter: ProfileToolFilter? = nil,
        generation: ProfileGenerationOverrides = .init(),
        history: ProfileHistoryPolicy = .keepAll
    ) {
        self.id = id
        self.instructions = dynamicInstructions.text
        if let toolFilter {
            self.toolFilter = toolFilter
        } else if dynamicInstructions.toolNames.isEmpty {
            self.toolFilter = .all
        } else {
            self.toolFilter = .only(Set(dynamicInstructions.toolNames))
        }
        self.generation = generation
        self.history = history
    }
}

/// Controls which request tools the model may see for a profile.
public enum ProfileToolFilter: Sendable, Equatable {
    /// Expose every tool supplied on the request.
    case all
    /// Expose only these tool names (intersection with the request).
    case only(Set<String>)
    /// Expose all request tools except these names.
    case excluding(Set<String>)

    /// Filters a request tool list.
    public func apply(to tools: [ToolSchema]) -> [ToolSchema] {
        switch self {
        case .all:
            return tools
        case let .only(names):
            return tools.filter { names.contains($0.name) }
        case let .excluding(names):
            return tools.filter { !names.contains($0.name) }
        }
    }
}

/// Optional generation knobs for a profile phase.
public struct ProfileGenerationOverrides: Sendable, Equatable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var toolChoice: ToolChoice?

    public init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        toolChoice: ToolChoice? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.toolChoice = toolChoice
    }

    /// Merges profile overrides into request options.
    ///
    /// Profile values fill in when present; request `structuredOutput`,
    /// `stopSequences`, and continuation fields are always preserved from the request.
    public func merging(into request: InferenceOptions) -> InferenceOptions {
        var merged = request
        if let temperature {
            merged.temperature = temperature
        }
        if let maxTokens {
            merged.maxTokens = maxTokens
        }
        if let topP {
            merged.topP = topP
        }
        if let toolChoice {
            merged.toolChoice = toolChoice
        }
        return merged
    }
}

/// Transcript / message history policy applied before each prompt
/// (Apple-style `historyTransform`).
public enum ProfileHistoryPolicy: Sendable, Equatable {
    /// Leave the message list unchanged.
    case keepAll
    /// Drop tool-result messages and strip assistant tool-call metadata.
    /// Useful when switching to a smaller on-device context window.
    case dropToolTranscript
    /// Keep only the last `count` messages after other transforms.
    case keepLast(count: Int)
    /// Drop tool transcript, then keep the last `count` messages.
    case dropToolTranscriptAndKeepLast(count: Int)

    /// Applies this policy to conversation messages.
    public func apply(to messages: [InferenceMessage]) -> [InferenceMessage] {
        switch self {
        case .keepAll:
            return messages
        case .dropToolTranscript:
            return Self.droppingToolTranscript(messages)
        case let .keepLast(count):
            guard count >= 0 else { return [] }
            return Array(messages.suffix(count))
        case let .dropToolTranscriptAndKeepLast(count):
            let trimmed = Self.droppingToolTranscript(messages)
            guard count >= 0 else { return [] }
            return Array(trimmed.suffix(count))
        }
    }

    private static func droppingToolTranscript(_ messages: [InferenceMessage]) -> [InferenceMessage] {
        messages.compactMap { message in
            switch message.role {
            case .tool:
                return nil
            case .assistant where !message.toolCalls.isEmpty:
                // Keep textual content only — tool args can dominate on-device context.
                guard !message.content.isEmpty else { return nil }
                return .assistant(message.content, toolCalls: [])
            default:
                return message
            }
        }
    }
}

// MARK: - DynamicInstructions

/// Composable instructions + preferred tool names (Apple-style `DynamicInstructions`).
///
/// Nesting / merging concatenates instruction text and unions tool preferences,
/// matching the WWDC 2026 composition model.
public struct DynamicInstructions: Sendable, Equatable {
    /// Ordered instruction paragraphs.
    public var segments: [String]

    /// Tool names that should be preferred / enabled with these instructions.
    public var toolNames: [String]

    /// Joined instruction text.
    public var text: String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public init(segments: [String] = [], toolNames: [String] = []) {
        self.segments = segments
        self.toolNames = toolNames
    }

    public init(_ text: String, tools toolNames: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.segments = trimmed.isEmpty ? [] : [trimmed]
        self.toolNames = toolNames
    }

    /// Merges another instructions bundle (append text, append unique tool names).
    public func merging(_ other: DynamicInstructions) -> DynamicInstructions {
        var names = toolNames
        for name in other.toolNames where !names.contains(name) {
            names.append(name)
        }
        return DynamicInstructions(
            segments: segments + other.segments,
            toolNames: names
        )
    }

    public static func + (lhs: DynamicInstructions, rhs: DynamicInstructions) -> DynamicInstructions {
        lhs.merging(rhs)
    }
}

// MARK: - DynamicProfile protocol

/// Resolves the active ``Profile`` for the next generation turn.
///
/// Apple re-evaluates `DynamicProfile.body` on every prompt. Swarm mirrors that
/// by calling ``resolve()`` at the start of each `generate` / `generateWithToolCalls`.
public protocol DynamicProfile: Sendable {
    /// Returns the profile that should drive the next model turn.
    func resolve() -> Profile
}

/// A profile that never changes.
public struct StaticDynamicProfile: DynamicProfile {
    private let profile: Profile

    public init(_ profile: Profile) {
        self.profile = profile
    }

    public func resolve() -> Profile { profile }
}

/// A profile resolved by a closure (re-evaluated every turn).
public struct ClosureDynamicProfile: DynamicProfile {
    private let body: @Sendable () -> Profile

    public init(_ body: @escaping @Sendable () -> Profile) {
        self.body = body
    }

    public func resolve() -> Profile { body() }
}

// MARK: - Mode switching (baton-pass)

/// Thread-safe mode cell for baton-pass style profile switching.
///
/// ```swift
/// enum Phase { case brainstorm, plan, review }
/// let mode = ProfileMode(Phase.brainstorm)
/// let profile = ModeSwitchingDynamicProfile(mode: mode) { phase in
///     switch phase {
///     case .brainstorm: Profile(id: "brainstorm", instructions: "…")
///     case .plan: Profile(id: "plan", instructions: "…")
///     case .review: Profile(id: "review", instructions: "…")
///     }
/// }
/// // Later, from a handoff tool:
/// mode.current = .plan
/// ```
public final class ProfileMode<Mode: Hashable & Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Mode

    public init(_ initial: Mode) {
        self.value = initial
    }

    public var current: Mode {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// Dynamic profile that switches definition based on a shared ``ProfileMode``.
public struct ModeSwitchingDynamicProfile<Mode: Hashable & Sendable>: DynamicProfile {
    private let mode: ProfileMode<Mode>
    private let makeProfile: @Sendable (Mode) -> Profile

    public init(
        mode: ProfileMode<Mode>,
        profile makeProfile: @escaping @Sendable (Mode) -> Profile
    ) {
        self.mode = mode
        self.makeProfile = makeProfile
    }

    public func resolve() -> Profile {
        makeProfile(mode.current)
    }
}

// MARK: - Resolution helpers

enum DynamicProfileResolution {
    /// Applies a resolved profile to messages, tools, and options.
    static func apply(
        _ profile: Profile?,
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        baseInstructions: String?
    ) -> (
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions,
        instructions: String?
    ) {
        guard let profile else {
            return (messages, tools, options, baseInstructions)
        }

        let transformedMessages = profile.history.apply(to: messages)
        let filteredTools = profile.toolFilter.apply(to: tools)
        let mergedOptions = profile.generation.merging(into: options)

        let instructions: String?
        let profileText = profile.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = baseInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (baseText, profileText.isEmpty ? nil : profileText) {
        case let (base?, profile?):
            instructions = base.isEmpty ? profile : (profile.isEmpty ? base : "\(base)\n\n\(profile)")
        case let (base?, nil):
            instructions = base.isEmpty ? nil : base
        case let (nil, profile?):
            instructions = profile
        case (nil, nil):
            instructions = nil
        }

        return (transformedMessages, filteredTools, mergedOptions, instructions)
    }

    /// Ensures profile instructions appear as a system message when not already present.
    static func messagesByInjectingInstructions(
        _ instructions: String?,
        into messages: [InferenceMessage]
    ) -> [InferenceMessage] {
        guard let instructions, !instructions.isEmpty else {
            return messages
        }
        if let first = messages.first, first.role == .system {
            // Replace / strengthen leading system message for this phase.
            var copy = messages
            copy[0] = .system(instructions)
            return copy
        }
        return [.system(instructions)] + messages
    }
}
