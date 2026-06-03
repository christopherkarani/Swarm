// OllamaSettings.swift
// Swarm Framework
//
// Lightweight Ollama settings without exposing Conduit types.

import Conduit

/// Configuration for Ollama local inference.
///
/// Use via the closure-based configuration on provider factories:
/// ```swift
/// let llm: some InferenceProvider = .ollama("mistral") { settings in
///     settings.host = "127.0.0.1"
///     settings.port = 11435
/// }
/// ```
public struct OllamaSettings: Sendable, Hashable {
    public var host: String
    public var port: Int
    public var keepAlive: String?
    public var pullOnMissing: Bool
    public var numGPU: Int?
    public var lowVRAM: Bool
    public var numCtx: Int?
    public var healthCheck: Bool

    public init(
        host: String = "localhost",
        port: Int = 11434,
        keepAlive: String? = nil,
        pullOnMissing: Bool = false,
        numGPU: Int? = nil,
        lowVRAM: Bool = false,
        numCtx: Int? = nil,
        healthCheck: Bool = true
    ) {
        self.host = host
        self.port = port
        self.keepAlive = keepAlive
        self.pullOnMissing = pullOnMissing
        self.numGPU = numGPU
        self.lowVRAM = lowVRAM
        self.numCtx = numCtx
        self.healthCheck = healthCheck
    }

    public static let `default` = OllamaSettings()

    func toConduit() -> OllamaConfiguration {
        OllamaConfiguration(
            keepAlive: keepAlive,
            pullOnMissing: pullOnMissing,
            numParallel: nil,
            numGPU: numGPU,
            mainGPU: nil,
            lowVRAM: lowVRAM,
            numCtx: numCtx,
            healthCheck: healthCheck,
            healthCheckTimeout: 5.0
        )
    }
}
