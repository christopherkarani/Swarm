// ModelSettings.swift
// Swarm Framework
//
// Comprehensive model configuration settings for LLM inference.

import Foundation

// MARK: - ModelSettings

/// Comprehensive configuration settings for model inference.
///
/// Use this struct to customize model behavior including sampling parameters,
/// tool control settings, and provider-specific options. All properties are
/// optional with sensible defaults.
///
/// ## Basic Usage
///
/// ```swift
/// let settings = ModelSettings.default
///     .temperature(0.8)
///     .maxTokens(1024)
///     .topP(0.9)
/// ```
///
/// ## Using Presets
///
/// ```swift
/// let creative = ModelSettings.creative
/// let precise = ModelSettings.precise
/// let balanced = ModelSettings.balanced
/// ```
///
/// ## Merging Settings
///
/// ```swift
/// let base = ModelSettings.default.temperature(0.7)
/// let override = ModelSettings().maxTokens(2048)
/// let merged = base.merged(with: override)
/// // Result: temperature 0.7, maxTokens 2048
/// ```
public struct ModelSettings: Sendable, Equatable {
    // MARK: - Sampling Parameters

    /// Temperature for model generation (0.0 = deterministic, 2.0 = creative).
    ///
    /// Lower values produce more focused, deterministic outputs.
    /// Higher values produce more diverse, creative outputs.
    /// - Valid range: 0.0 to 2.0
    public var temperature: Double?

    /// Nucleus sampling threshold.
    ///
    /// Only consider tokens with cumulative probability up to this threshold.
    /// Lower values produce more focused outputs.
    /// - Valid range: 0.0 to 1.0
    public var topP: Double?

    /// Top-k sampling parameter.
    ///
    /// Only consider the top k most likely tokens.
    /// Lower values produce more focused outputs.
    /// - Valid range: > 0
    public var topK: Int?

    /// Maximum tokens to generate per response.
    ///
    /// Limits the length of the generated response.
    /// - Valid range: > 0
    public var maxTokens: Int?

    /// Frequency penalty for repeated tokens.
    ///
    /// Positive values discourage repetition of tokens based on their frequency.
    /// Negative values encourage repetition.
    /// - Valid range: -2.0 to 2.0
    public var frequencyPenalty: Double?

    /// Presence penalty for new tokens.
    ///
    /// Positive values encourage the model to use new tokens.
    /// Negative values encourage staying with tokens already used.
    /// - Valid range: -2.0 to 2.0
    public var presencePenalty: Double?

    /// Sequences that will stop generation when encountered.
    ///
    /// The model will stop generating when any of these sequences appear.
    public var stopSequences: [String]?

    /// Random seed for reproducible generation.
    ///
    /// When set, the model will produce deterministic outputs
    /// for the same input and seed combination.
    public var seed: Int?

    // MARK: - Tool Control

    /// Controls how the model should use tools.
    ///
    /// Use this to force tool usage, disable tools, or select a specific tool.
    public var toolChoice: ToolChoice?

    /// Whether to execute multiple tool calls in parallel.
    ///
    /// When enabled, if the model requests multiple tool calls,
    /// they will be executed concurrently.
    public var parallelToolCalls: Bool?

    // MARK: - Advanced Options

    /// Strategy for handling context length truncation.
    ///
    /// Controls how the model handles inputs that exceed the context window.
    public var truncation: TruncationStrategy?

    /// Verbosity level for model responses.
    ///
    /// Controls how detailed the model's responses should be.
    public var verbosity: Verbosity?

    /// Prompt cache retention policy.
    ///
    /// Controls how long prompts are cached for reuse.
    public var promptCacheRetention: CacheRetention?

    // MARK: - Additional Sampling Parameters

    /// Repetition penalty for repeated sequences.
    ///
    /// Values greater than 1.0 discourage repetition.
    /// Values less than 1.0 encourage repetition.
    public var repetitionPenalty: Double?

    /// Minimum probability threshold for tokens.
    ///
    /// Tokens with probability below this threshold are filtered out.
    /// - Valid range: 0.0 to 1.0
    public var minP: Double?

    // MARK: - Provider-Specific Settings

    /// Provider-specific settings as a type-safe dictionary.
    ///
    /// Use this for settings that are specific to certain providers
    /// and not covered by the standard properties.
    ///
    /// Example:
    /// ```swift
    /// let settings = ModelSettings()
    ///     .providerSettings([
    ///         "anthropic:thinking": .bool(true),
    ///         "openai:logprobs": .int(5)
    ///     ])
    /// ```
    public var providerSettings: [String: SendableValue]?

    /// Configuration for extended thinking / reasoning mode.
    ///
    /// Used by OpenAI o-series, OpenRouter `:thinking`, and similar providers.
    /// Without this, reasoning models may run unbounded — see one-fhx for the
    /// production failure mode (gpt-5 returning response_bytes=0 after 800-1000
    /// reasoning tokens).
    public var reasoning: ReasoningConfig?

    // MARK: - Initialization

    /// Creates a new model settings configuration.
    ///
    /// All parameters are optional and default to nil, meaning the provider's
    /// defaults will be used.
    public init(
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        maxTokens: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil,
        toolChoice: ToolChoice? = nil,
        parallelToolCalls: Bool? = nil,
        truncation: TruncationStrategy? = nil,
        verbosity: Verbosity? = nil,
        promptCacheRetention: CacheRetention? = nil,
        repetitionPenalty: Double? = nil,
        minP: Double? = nil,
        providerSettings: [String: SendableValue]? = nil,
        reasoning: ReasoningConfig? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stopSequences = stopSequences
        self.seed = seed
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.truncation = truncation
        self.verbosity = verbosity
        self.promptCacheRetention = promptCacheRetention
        self.repetitionPenalty = repetitionPenalty
        self.minP = minP
        self.providerSettings = providerSettings
        self.reasoning = reasoning
    }
}

// MARK: - Fluent Builders

public extension ModelSettings {
    @discardableResult
    func temperature(_ value: Double?) -> Self {
        var copy = self
        copy.temperature = value
        return copy
    }

    @discardableResult
    func topP(_ value: Double?) -> Self {
        var copy = self
        copy.topP = value
        return copy
    }

    @discardableResult
    func topK(_ value: Int?) -> Self {
        var copy = self
        copy.topK = value
        return copy
    }

    @discardableResult
    func maxTokens(_ value: Int?) -> Self {
        var copy = self
        copy.maxTokens = value
        return copy
    }

    @discardableResult
    func frequencyPenalty(_ value: Double?) -> Self {
        var copy = self
        copy.frequencyPenalty = value
        return copy
    }

    @discardableResult
    func presencePenalty(_ value: Double?) -> Self {
        var copy = self
        copy.presencePenalty = value
        return copy
    }

    @discardableResult
    func stopSequences(_ value: [String]?) -> Self {
        var copy = self
        copy.stopSequences = value
        return copy
    }

    @discardableResult
    func seed(_ value: Int?) -> Self {
        var copy = self
        copy.seed = value
        return copy
    }

    @discardableResult
    func toolChoice(_ value: ToolChoice?) -> Self {
        var copy = self
        copy.toolChoice = value
        return copy
    }

    @discardableResult
    func parallelToolCalls(_ value: Bool?) -> Self {
        var copy = self
        copy.parallelToolCalls = value
        return copy
    }

    @discardableResult
    func truncation(_ value: TruncationStrategy?) -> Self {
        var copy = self
        copy.truncation = value
        return copy
    }

    @discardableResult
    func verbosity(_ value: Verbosity?) -> Self {
        var copy = self
        copy.verbosity = value
        return copy
    }

    @discardableResult
    func promptCacheRetention(_ value: CacheRetention?) -> Self {
        var copy = self
        copy.promptCacheRetention = value
        return copy
    }

    @discardableResult
    func repetitionPenalty(_ value: Double?) -> Self {
        var copy = self
        copy.repetitionPenalty = value
        return copy
    }

    @discardableResult
    func minP(_ value: Double?) -> Self {
        var copy = self
        copy.minP = value
        return copy
    }

    @discardableResult
    func providerSettings(_ value: [String: SendableValue]?) -> Self {
        var copy = self
        copy.providerSettings = value
        return copy
    }

    @discardableResult
    func reasoning(_ value: ReasoningConfig?) -> Self {
        var copy = self
        copy.reasoning = value
        return copy
    }
}

// MARK: - Static Presets

public extension ModelSettings {
    /// Default model settings with no overrides.
    ///
    /// All values are nil, meaning provider defaults will be used.
    static var `default`: ModelSettings {
        ModelSettings()
    }

    /// Creative settings optimized for diverse, imaginative outputs.
    ///
    /// - Temperature: 1.2
    /// - Top P: 0.95
    static var creative: ModelSettings {
        ModelSettings(temperature: 1.2, topP: 0.95)
    }

    /// Precise settings optimized for focused, deterministic outputs.
    ///
    /// - Temperature: 0.2
    /// - Top P: 0.9
    static var precise: ModelSettings {
        ModelSettings(temperature: 0.2, topP: 0.9)
    }

    /// Balanced settings for general-purpose use.
    ///
    /// - Temperature: 0.7
    /// - Top P: 0.9
    static var balanced: ModelSettings {
        ModelSettings(temperature: 0.7, topP: 0.9)
    }
}

// MARK: - Validation

public extension ModelSettings {
    /// Validates all settings and throws if any are out of range.
    ///
    /// - Throws: `ModelSettingsValidationError` if any setting is invalid.
    ///
    /// Example:
    /// ```swift
    /// let settings = ModelSettings()
    ///     .temperature(0.8)
    ///     .topP(0.9)
    ///
    /// try settings.validate() // Succeeds
    ///
    /// let invalid = ModelSettings().temperature(3.0)
    /// try invalid.validate() // Throws invalidTemperature
    /// ```
    func validate() throws {
        if let temperature {
            guard temperature.isFinite, temperature >= 0.0, temperature <= 2.0 else {
                throw ModelSettingsValidationError.invalidTemperature(temperature)
            }
        }

        if let topP {
            guard topP.isFinite, topP >= 0.0, topP <= 1.0 else {
                throw ModelSettingsValidationError.invalidTopP(topP)
            }
        }

        if let topK {
            guard topK > 0 else {
                throw ModelSettingsValidationError.invalidTopK(topK)
            }
        }

        if let maxTokens {
            guard maxTokens > 0 else {
                throw ModelSettingsValidationError.invalidMaxTokens(maxTokens)
            }
        }

        if let frequencyPenalty {
            guard frequencyPenalty.isFinite, frequencyPenalty >= -2.0, frequencyPenalty <= 2.0 else {
                throw ModelSettingsValidationError.invalidFrequencyPenalty(frequencyPenalty)
            }
        }

        if let presencePenalty {
            guard presencePenalty.isFinite, presencePenalty >= -2.0, presencePenalty <= 2.0 else {
                throw ModelSettingsValidationError.invalidPresencePenalty(presencePenalty)
            }
        }

        if let minP {
            guard minP.isFinite, minP >= 0.0, minP <= 1.0 else {
                throw ModelSettingsValidationError.invalidMinP(minP)
            }
        }

        if let repetitionPenalty {
            guard repetitionPenalty.isFinite, repetitionPenalty >= 0.0 else {
                throw ModelSettingsValidationError.invalidRepetitionPenalty(repetitionPenalty)
            }
        }

        if let reasoningMaxTokens = reasoning?.maxTokens {
            guard reasoningMaxTokens > 0 else {
                throw ModelSettingsValidationError.invalidReasoningMaxTokens(reasoningMaxTokens)
            }
        }
    }
}

// MARK: - Merging

public extension ModelSettings {
    // MARK: Internal

    /// Merges another ModelSettings, with other's values taking precedence.
    ///
    /// This is useful for combining base settings with overrides.
    /// Only non-nil values from `other` replace values in `self`.
    /// The merged settings are validated before being returned.
    ///
    /// - Parameter other: The settings to merge in.
    /// - Returns: A new ModelSettings with merged and validated values.
    /// - Throws: `ModelSettingsValidationError` if the merged settings are invalid.
    ///
    /// Example:
    /// ```swift
    /// let base = ModelSettings.balanced
    /// let override = ModelSettings().maxTokens(2048)
    /// let merged = try base.merged(with: override)
    /// // Result: temperature 0.7, topP 0.9, maxTokens 2048
    ///
    /// // Merging invalid settings will throw
    /// let invalid = ModelSettings().temperature(3.0)
    /// let merged = try base.merged(with: invalid) // Throws invalidTemperature
    /// ```
    func merged(with other: ModelSettings) throws -> ModelSettings {
        let merged = ModelSettings(
            temperature: other.temperature ?? temperature,
            topP: other.topP ?? topP,
            topK: other.topK ?? topK,
            maxTokens: other.maxTokens ?? maxTokens,
            frequencyPenalty: other.frequencyPenalty ?? frequencyPenalty,
            presencePenalty: other.presencePenalty ?? presencePenalty,
            stopSequences: other.stopSequences ?? stopSequences,
            seed: other.seed ?? seed,
            toolChoice: other.toolChoice ?? toolChoice,
            parallelToolCalls: other.parallelToolCalls ?? parallelToolCalls,
            truncation: other.truncation ?? truncation,
            verbosity: other.verbosity ?? verbosity,
            promptCacheRetention: other.promptCacheRetention ?? promptCacheRetention,
            repetitionPenalty: other.repetitionPenalty ?? repetitionPenalty,
            minP: other.minP ?? minP,
            providerSettings: mergeProviderSettings(with: other.providerSettings),
            reasoning: other.reasoning ?? reasoning
        )

        // Validate the merged settings to catch invalid combinations
        try merged.validate()

        return merged
    }

    // MARK: Private

    /// Merges provider settings dictionaries.
    private func mergeProviderSettings(
        with other: [String: SendableValue]?
    ) -> [String: SendableValue]? {
        guard let other else { return providerSettings }
        guard let providerSettings else { return other }
        return providerSettings.merging(other) { _, new in new }
    }
}

// MARK: - ModelSettingsValidationError

/// Errors that can occur during model settings validation.
public enum ModelSettingsValidationError: Error, Sendable, LocalizedError {
    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .invalidTemperature(value):
            "Invalid temperature \(value): must be a finite number between 0.0 and 2.0"
        case let .invalidTopP(value):
            "Invalid topP \(value): must be a finite number between 0.0 and 1.0"
        case let .invalidTopK(value):
            "Invalid topK \(value): must be greater than 0"
        case let .invalidMaxTokens(value):
            "Invalid maxTokens \(value): must be greater than 0"
        case let .invalidFrequencyPenalty(value):
            "Invalid frequencyPenalty \(value): must be a finite number between -2.0 and 2.0"
        case let .invalidPresencePenalty(value):
            "Invalid presencePenalty \(value): must be a finite number between -2.0 and 2.0"
        case let .invalidMinP(value):
            "Invalid minP \(value): must be a finite number between 0.0 and 1.0"
        case let .invalidRepetitionPenalty(value):
            "Invalid repetitionPenalty \(value): must be a finite number >= 0.0"
        case let .invalidReasoningMaxTokens(value):
            "Invalid reasoning maxTokens \(value): must be greater than 0"
        }
    }

    /// Temperature must be between 0.0 and 2.0.
    case invalidTemperature(Double)

    /// Top P must be between 0.0 and 1.0.
    case invalidTopP(Double)

    /// Top K must be greater than 0.
    case invalidTopK(Int)

    /// Max tokens must be greater than 0.
    case invalidMaxTokens(Int)

    /// Frequency penalty must be between -2.0 and 2.0.
    case invalidFrequencyPenalty(Double)

    /// Presence penalty must be between -2.0 and 2.0.
    case invalidPresencePenalty(Double)

    /// Min P must be between 0.0 and 1.0.
    case invalidMinP(Double)

    /// Repetition penalty must be a finite number >= 0.0.
    case invalidRepetitionPenalty(Double)

    /// Reasoning max tokens must be greater than 0.
    case invalidReasoningMaxTokens(Int)
}

// MARK: - ToolChoice

/// Controls how the model should use tools.
public enum ToolChoice: Sendable, Equatable, Codable {
    // MARK: Public

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "auto":
            self = .auto
        case "none":
            self = .none
        case "required":
            self = .required
        case "specific":
            let toolName = try container.decode(String.self, forKey: .toolName)
            self = .specific(toolName: toolName)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown ToolChoice type: \(type)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .none:
            try container.encode("none", forKey: .type)
        case .required:
            try container.encode("required", forKey: .type)
        case let .specific(toolName):
            try container.encode("specific", forKey: .type)
            try container.encode(toolName, forKey: .toolName)
        }
    }

    /// Let the model decide whether to use tools.
    case auto

    /// Do not use any tools.
    case none

    /// Force the model to use at least one tool.
    case required

    /// Force the model to use a specific tool.
    case specific(toolName: String)

    // MARK: Private

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case toolName
    }
}

// MARK: - TruncationStrategy

/// Strategy for handling context length truncation.
public enum TruncationStrategy: String, Sendable, Codable {
    /// Automatically truncate to fit the context window.
    case auto

    /// Disable truncation (will error if context is too long).
    case disabled
}

// MARK: - Verbosity

/// Verbosity level for model responses.
public enum Verbosity: String, Sendable, Codable {
    /// Concise responses with minimal detail.
    case low

    /// Balanced responses with moderate detail.
    case medium

    /// Detailed responses with comprehensive information.
    case high
}

// MARK: - CacheRetention

/// Prompt cache retention policy.
public enum CacheRetention: String, Sendable, Codable {
    /// Keep prompts in memory only (cleared on process exit).
    case inMemory = "in_memory"

    /// Cache prompts for 24 hours.
    case twentyFourHours = "24h"

    /// Cache prompts for 5 minutes.
    case fiveMinutes = "5m"
}

// MARK: - ModelSettings + CustomStringConvertible

extension ModelSettings: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        if let temperature { parts.append("temperature: \(temperature)") }
        if let topP { parts.append("topP: \(topP)") }
        if let topK { parts.append("topK: \(topK)") }
        if let maxTokens { parts.append("maxTokens: \(maxTokens)") }
        if let frequencyPenalty { parts.append("frequencyPenalty: \(frequencyPenalty)") }
        if let presencePenalty { parts.append("presencePenalty: \(presencePenalty)") }
        if let stopSequences { parts.append("stopSequences: \(stopSequences)") }
        if let seed { parts.append("seed: \(seed)") }
        if let toolChoice { parts.append("toolChoice: \(toolChoice)") }
        if let parallelToolCalls { parts.append("parallelToolCalls: \(parallelToolCalls)") }
        if let truncation { parts.append("truncation: \(truncation.rawValue)") }
        if let verbosity { parts.append("verbosity: \(verbosity.rawValue)") }
        if let promptCacheRetention { parts.append("promptCacheRetention: \(promptCacheRetention.rawValue)") }
        if let repetitionPenalty { parts.append("repetitionPenalty: \(repetitionPenalty)") }
        if let minP { parts.append("minP: \(minP)") }
        if let providerSettings { parts.append("providerSettings: \(providerSettings)") }
        if let reasoning { parts.append("reasoning: \(reasoning)") }

        if parts.isEmpty {
            return "ModelSettings(default)"
        }

        return "ModelSettings(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - ModelSettings + Codable

extension ModelSettings: Codable {}
