// DynamicProfile.swift
// Swarm Framework
//
// Swarm agent profiles — capture-path agent configuration.
//
// This file defines Swarm's `DynamicAgentProfile` / `AgentProfile` /
// `AgentInstructions`. Before 0.7 they were named `DynamicProfile` /
// `Profile` / `DynamicInstructions`, which collide with Apple's OS 27
// FoundationModels names. The old names remain as deprecated typealiases
// at the bottom of this file.
//
// Capture mode still resolves the Swarm profile every turn:
//
// 1. Re-resolves instructions, tools, options, and history policy.
// 2. Supports baton-pass mode switching via ``ProfileMode``.
// 3. Composes reusable instruction + tool bundles via ``AgentInstructions``.
// 4. Plugs into ``FoundationModelsInferenceProvider``.
//
// Apple's native `LanguageModelSession(profile:)` is the owned-loop bridge
// for these types (see `FoundationModelsNativeDynamicProfile`), not a rename
// of them.

import Foundation

// MARK: - AgentProfile

/// A single agent configuration phase, modeled on Apple's `Profile`.
///
/// Profiles group instructions, tool visibility, generation overrides, and
/// transcript history policy. A ``DynamicAgentProfile`` resolves one of these on
/// every generation turn.
public struct AgentProfile: Sendable, Equatable {
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

    /// Creates a profile from composable ``AgentInstructions``.
    public init(
        id: String,
        dynamicInstructions: AgentInstructions,
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
    /// AgentProfile values fill in when present; request `structuredOutput`,
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

// MARK: - AgentInstructions

/// Composable instructions + preferred tool names, modeled on Apple's `DynamicInstructions`.
///
/// Nesting / merging concatenates instruction text and unions tool preferences,
/// matching the WWDC 2026 composition model.
public struct AgentInstructions: Sendable, Equatable {
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
    public func merging(_ other: AgentInstructions) -> AgentInstructions {
        var names = toolNames
        for name in other.toolNames where !names.contains(name) {
            names.append(name)
        }
        return AgentInstructions(
            segments: segments + other.segments,
            toolNames: names
        )
    }

    public static func + (lhs: AgentInstructions, rhs: AgentInstructions) -> AgentInstructions {
        lhs.merging(rhs)
    }
}

// MARK: - DynamicAgentProfile protocol

/// Resolves the active ``AgentProfile`` for the next generation turn.
///
/// Swarm calls ``resolve()`` at the start of each capture `generate` /
/// `generateWithToolCalls`. This protocol is not Apple's
/// `LanguageModelSession.DynamicProfile`.
public protocol DynamicAgentProfile: Sendable {
    /// Returns the profile that should drive the next model turn.
    func resolve() -> AgentProfile
}

/// A profile that never changes.
public struct StaticDynamicProfile: DynamicAgentProfile {
    private let profile: AgentProfile

    public init(_ profile: AgentProfile) {
        self.profile = profile
    }

    public func resolve() -> AgentProfile { profile }
}

/// A profile resolved by a closure (re-evaluated every turn).
public struct ClosureDynamicProfile: DynamicAgentProfile {
    private let body: @Sendable () -> AgentProfile

    public init(_ body: @escaping @Sendable () -> AgentProfile) {
        self.body = body
    }

    public func resolve() -> AgentProfile { body() }
}

// MARK: - Mode switching (baton-pass)

/// Thread-safe mode cell for baton-pass style profile switching.
///
/// ```swift
/// enum Phase { case brainstorm, plan, review }
/// let mode = ProfileMode(Phase.brainstorm)
/// let profile = ModeSwitchingDynamicProfile(mode: mode) { phase in
///     switch phase {
///     case .brainstorm: AgentProfile(id: "brainstorm", instructions: "…")
///     case .plan: AgentProfile(id: "plan", instructions: "…")
///     case .review: AgentProfile(id: "review", instructions: "…")
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
public struct ModeSwitchingDynamicProfile<Mode: Hashable & Sendable>: DynamicAgentProfile {
    private let mode: ProfileMode<Mode>
    private let makeProfile: @Sendable (Mode) -> AgentProfile

    public init(
        mode: ProfileMode<Mode>,
        profile makeProfile: @escaping @Sendable (Mode) -> AgentProfile
    ) {
        self.mode = mode
        self.makeProfile = makeProfile
    }

    public func resolve() -> AgentProfile {
        makeProfile(mode.current)
    }
}

// MARK: - Resolution helpers

enum DynamicProfileResolution {
    /// Applies a resolved profile to messages, tools, and options.
    static func apply(
        _ profile: AgentProfile?,
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

// MARK: - Deprecated names

/// Renamed to ``AgentProfile`` so it does not collide with Apple's
/// FoundationModels `Profile` when a file imports both modules.
@available(*, deprecated, renamed: "AgentProfile")
public typealias Profile = AgentProfile

/// Renamed to ``DynamicAgentProfile`` so it does not collide with Apple's
/// `LanguageModelSession.DynamicProfile` when a file imports both modules.
@available(*, deprecated, renamed: "DynamicAgentProfile")
public typealias DynamicProfile = DynamicAgentProfile

/// Renamed to ``AgentInstructions`` so it does not collide with Apple's
/// FoundationModels `DynamicInstructions` when a file imports both modules.
@available(*, deprecated, renamed: "AgentInstructions")
public typealias DynamicInstructions = AgentInstructions
