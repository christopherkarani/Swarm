// RunOptions.swift
// Swarm Framework
//
// Execution-time options for agent.run() and agent.stream().
// Replaces the 18-field AgentConfiguration with a focused 6-field struct.

import Foundation
import Logging

/// Execution-time options for `agent.run()` and `agent.stream()`.
///
/// ```swift
/// let result = try await agent.run("Hello", options: .creative)
/// let result = try await agent.run("Analyze", options: RunOptions(maxIterations: 20, temperature: 0.3))
/// ```
public struct RunOptions: Sendable, Equatable {
    /// Maximum reasoning iterations. Default: 10
    public var maxIterations: Int

    /// Maximum execution time. Default: 60 seconds
    public var timeout: Duration

    /// Model temperature (0.0–2.0). Default: 1.0
    public var temperature: Double

    /// Maximum tokens per response. Default: nil (model default)
    public var maxTokens: Int?

    /// Whether to stream responses. Default: true
    public var stream: Bool

    /// Whether to execute tool calls in parallel. Default: false
    public var parallelTools: Bool

    public init(
        maxIterations: Int = 10,
        timeout: Duration = .seconds(60),
        temperature: Double = 1.0,
        maxTokens: Int? = nil,
        stream: Bool = true,
        parallelTools: Bool = false
    ) {
        if maxIterations < 1 {
            Log.agents.warning("RunOptions: maxIterations \(maxIterations) must be >= 1; using 1")
        }
        if timeout <= .zero {
            Log.agents.warning("RunOptions: timeout must be positive; using default 60 seconds")
        }
        if !temperature.isFinite || !(0.0 ... 2.0).contains(temperature) {
            Log.agents.warning("RunOptions: temperature \(temperature) out of [0.0, 2.0]; using default 1.0")
        }

        self.maxIterations = max(1, maxIterations)
        self.timeout = timeout > .zero ? timeout : .seconds(60)
        self.temperature = (temperature.isFinite && (0.0 ... 2.0).contains(temperature)) ? temperature : 1.0
        self.maxTokens = maxTokens
        self.stream = stream
        self.parallelTools = parallelTools
    }

    // MARK: - Presets

    /// Default options — balanced for general use.
    public static let `default` = RunOptions()

    /// Creative mode — higher temperature for more varied output.
    public static let creative = RunOptions(temperature: 1.5)

    /// Precise mode — low temperature for factual, deterministic tasks.
    public static let precise = RunOptions(temperature: 0.2)

    /// Fast mode — fewer iterations, shorter timeout.
    public static let fast = RunOptions(maxIterations: 3, timeout: .seconds(15))
}
