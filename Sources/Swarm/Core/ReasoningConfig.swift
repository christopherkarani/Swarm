// ReasoningConfig.swift
// Swarm Framework
//
// Optional reasoning / extended-thinking configuration for InferenceOptions.

import Foundation

/// Reasoning effort level for models that support extended thinking / chain-of-
/// thought reasoning.
///
/// Providers that do not support reasoning ignore this value.
public enum ReasoningEffort: String, Sendable, Hashable, Codable, CaseIterable {
    /// Maximum reasoning time.
    case xhigh
    /// Extensive reasoning.
    case high
    /// Balanced reasoning.
    case medium
    /// Light reasoning.
    case low
    /// Very brief reasoning.
    case minimal
    /// No reasoning — standard generation. Use this to explicitly
    /// disable reasoning when the base/provider config has it enabled;
    /// `nil` means "preserve base config", which can't override an
    /// inherited reasoning setting.
    case none
}

/// Configuration for extended thinking / reasoning mode.
///
/// Use `effort` for providers that accept a qualitative level.
/// Use `maxTokens` to allocate a token budget directly.
/// Use `enabled` for simple on/off providers.
/// Use `exclude` to suppress reasoning details from the response payload.
///
/// Built-in Foundation Models may ignore fields they do not support.
/// Custom ``InferenceProvider`` implementations decide how to map these values.
public struct ReasoningConfig: Sendable, Hashable, Codable {
    /// Reasoning effort level (qualitative).
    public var effort: ReasoningEffort?

    /// Maximum tokens for reasoning. Alternative to `effort`.
    public var maxTokens: Int?

    /// Whether to exclude reasoning details from the response.
    public var exclude: Bool?

    /// Whether reasoning is enabled. Used by simple-flag providers.
    public var enabled: Bool?

    public init(
        effort: ReasoningEffort? = nil,
        maxTokens: Int? = nil,
        exclude: Bool? = nil,
        enabled: Bool? = nil
    ) {
        self.effort = effort
        self.maxTokens = maxTokens
        self.exclude = exclude
        self.enabled = enabled
    }
}

// MARK: - CustomStringConvertible

extension ReasoningConfig: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        if let effort { parts.append("effort: \(effort.rawValue)") }
        if let maxTokens { parts.append("maxTokens: \(maxTokens)") }
        if let exclude { parts.append("exclude: \(exclude)") }
        if let enabled { parts.append("enabled: \(enabled)") }
        if parts.isEmpty {
            return "ReasoningConfig(default)"
        }
        return "ReasoningConfig(\(parts.joined(separator: ", ")))"
    }
}
