# Swarm Public API Catalog

Generated from `Sources/Swarm/` on 2026-04-30; source-verified and refreshed for high-risk public rows on 2026-07-28 (Conduit hard-removed in 0.6). MCP client rows refreshed 2026-08-14. OpenAI-compatible provider rows added 2026-08-14.

- Scope: all `.swift` files under `Sources/Swarm/`, excluding `Internal/GraphRuntime/`
- Source files scanned: 194
- Public/open symbols cataloged: 2325

## 1. Swarm (entry point)

### Swarm.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 42 | enum | public | Swarm | `public enum Swarm` |
| 44 | var | public | Swarm.version | `public static let version: String` |
| 47 | var | public | Swarm.minimumMacOSVersion | `public static let minimumMacOSVersion: String` |
| 50 | var | public | Swarm.minimumiOSVersion | `public static let minimumiOSVersion: String` |

## 2. Core

### Core/AgentConfiguration+InferenceOptions.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 10 | var | public | AgentConfiguration.effectiveContextProfile | `public var effectiveContextProfile: ContextProfile { get }` |
| 22 | var | public | AgentConfiguration.inferenceOptions | `public var inferenceOptions: InferenceOptions { get }` |

### Core/AgentConfiguration.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 10 | enum | public | ContextMode | `public enum ContextMode` |
| 12 | case | public | ContextMode.adaptive | `public case adaptive` |
| 15 | case | public | ContextMode.strict4k | `public case strict4k` |
| 46 | struct | public | InferencePolicy | `public struct InferencePolicy` |
| 48 | enum | public | InferencePolicy.LatencyTier | `public enum LatencyTier` |
| 50 | case | public | InferencePolicy.LatencyTier.interactive | `public case interactive` |
| 52 | case | public | InferencePolicy.LatencyTier.background | `public case background` |
| 56 | enum | public | InferencePolicy.NetworkState | `public enum NetworkState` |
| 57 | case | public | InferencePolicy.NetworkState.offline | `public case offline` |
| 58 | case | public | InferencePolicy.NetworkState.online | `public case online` |
| 59 | case | public | InferencePolicy.NetworkState.metered | `public case metered` |
| 63 | var | public | InferencePolicy.latencyTier | `public var latencyTier: InferencePolicy.LatencyTier` |
| 66 | var | public | InferencePolicy.privacyRequired | `public var privacyRequired: Bool` |
| 73 | var | public | InferencePolicy.tokenBudget | `public var tokenBudget: Int?` |
| 76 | var | public | InferencePolicy.networkState | `public var networkState: InferencePolicy.NetworkState` |
| 78 | func | public | InferencePolicy.init(latencyTier:privacyRequired:tokenBudget:networkState:) | `public init(latencyTier: InferencePolicy.LatencyTier = .interactive, privacyRequired: Bool = false, tokenBudget: Int? = nil, networkState: InferencePolicy.NetworkState = .online)` |
| 108 | func | public | AgentConfiguration.autoPreviousResponseId(_:) | `public @discardableResult func autoPreviousResponseId(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.contextMode(_:) | `public @discardableResult func contextMode(_ value: ContextMode) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.contextProfile(_:) | `public @discardableResult func contextProfile(_ value: ContextProfile) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.autoAttachMetricsCollector(_:) | `public @discardableResult func autoAttachMetricsCollector(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.defaultTracingEnabled(_:) | `public @discardableResult func defaultTracingEnabled(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.enableStreaming(_:) | `public @discardableResult func enableStreaming(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.foundationModelsExecution(_:) | `public @discardableResult func foundationModelsExecution(_ value: FoundationModelsExecutionMode) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.includeReasoning(_:) | `public @discardableResult func includeReasoning(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.includeToolCallDetails(_:) | `public @discardableResult func includeToolCallDetails(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.inferencePolicy(_:) | `public @discardableResult func inferencePolicy(_ value: InferencePolicy?) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.maxIterations(_:) | `public @discardableResult func maxIterations(_ value: Int) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.maxTokens(_:) | `public @discardableResult func maxTokens(_ value: Int?) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.modelSettings(_:) | `public @discardableResult func modelSettings(_ value: ModelSettings?) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.name(_:) | `public @discardableResult func name(_ value: String) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.parallelToolCalls(_:) | `public @discardableResult func parallelToolCalls(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.previousResponseId(_:) | `public @discardableResult func previousResponseId(_ value: String?) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.sessionHistoryLimit(_:) | `public @discardableResult func sessionHistoryLimit(_ value: Int?) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.stopOnToolError(_:) | `public @discardableResult func stopOnToolError(_ value: Bool) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.stopSequences(_:) | `public @discardableResult func stopSequences(_ value: [String]) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.temperature(_:) | `public @discardableResult func temperature(_ value: Double) -> AgentConfiguration` |
| 108 | func | public | AgentConfiguration.timeout(_:) | `public @discardableResult func timeout(_ value: Duration) -> AgentConfiguration` |
| 109 | struct | public | AgentConfiguration | `public struct AgentConfiguration` |
| 113 | var | public | AgentConfiguration.default | `public static let `default`: AgentConfiguration` |
| 119 | var | public | AgentConfiguration.name | `public var name: String` |
| 125 | var | public | AgentConfiguration.maxIterations | `public var maxIterations: Int` |
| 129 | var | public | AgentConfiguration.timeout | `public var timeout: Duration` |
| 135 | var | public | AgentConfiguration.temperature | `public var temperature: Double` |
| 139 | var | public | AgentConfiguration.maxTokens | `public var maxTokens: Int?` |
| 143 | var | public | AgentConfiguration.stopSequences | `public var stopSequences: [String]` |
| 159 | var | public | AgentConfiguration.modelSettings | `public var modelSettings: ModelSettings?` |
| 166 | var | public | AgentConfiguration.contextProfile | `public var contextProfile: ContextProfile` |
| 172 | var | public | AgentConfiguration.contextMode | `public var contextMode: ContextMode` |
| 187 | var | public | AgentConfiguration.inferencePolicy | `public var inferencePolicy: InferencePolicy?` |
| 193 | var | public | AgentConfiguration.enableStreaming | `public var enableStreaming: Bool` |
| 197 | var | public | AgentConfiguration.includeToolCallDetails | `public var includeToolCallDetails: Bool` |
| 201 | var | public | AgentConfiguration.stopOnToolError | `public var stopOnToolError: Bool` |
| 205 | var | public | AgentConfiguration.includeReasoning | `public var includeReasoning: Bool` |
| 215 | var | public | AgentConfiguration.sessionHistoryLimit | `public var sessionHistoryLimit: Int?` |
| 235 | var | public | AgentConfiguration.parallelToolCalls | `public var parallelToolCalls: Bool` |
| 245 | var | public | AgentConfiguration.previousResponseId | `public var previousResponseId: String?` |
| 253 | var | public | AgentConfiguration.autoPreviousResponseId | `public var autoPreviousResponseId: Bool` |
| 264 | var | public | AgentConfiguration.defaultTracingEnabled | `public var defaultTracingEnabled: Bool` |
| 265 | var | public | AgentConfiguration.autoAttachMetricsCollector | `public var autoAttachMetricsCollector: Bool` |
| 126 | enum | public | FoundationModelsExecutionMode | `public enum FoundationModelsExecutionMode` |
| 130 | case | public | FoundationModelsExecutionMode.capture | `public case capture` |
| 139 | case | public | FoundationModelsExecutionMode.nativeSession | `public case nativeSession` |
| 604 | var | public | AgentConfiguration.foundationModelsExecution | `public var foundationModelsExecution: FoundationModelsExecutionMode` |
| 608 | var | public | AgentConfiguration.resilience | `public var resilience: ResilienceConfiguration` |
| 630 | func | public | AgentConfiguration.init(name:maxIterations:timeout:temperature:maxTokens:stopSequences:modelSettings:contextProfile:inferencePolicy:enableStreaming:includeToolCallDetails:stopOnToolError:includeReasoning:sessionHistoryLimit:contextMode:parallelToolCalls:previousResponseId:autoPreviousResponseId:defaultTracingEnabled:autoAttachMetricsCollector:foundationModelsExecution:resilience:) | `public init(name: String = "Agent", maxIterations: Int = 10, timeout: Duration = .seconds(60), temperature: Double = 1.0, maxTokens: Int? = nil, stopSequences: [String] = [], modelSettings: ModelSettings? = nil, contextProfile: ContextProfile = .platformDefault, inferencePolicy: InferencePolicy? = nil, enableStreaming: Bool = true, includeToolCallDetails: Bool = true, stopOnToolError: Bool = false, includeReasoning: Bool = true, sessionHistoryLimit: Int? = 50, contextMode: ContextMode = .adaptive, parallelToolCalls: Bool = false, previousResponseId: String? = nil, autoPreviousResponseId: Bool = false, defaultTracingEnabled: Bool = true, autoAttachMetricsCollector: Bool = false, foundationModelsExecution: FoundationModelsExecutionMode = .capture, resilience: ResilienceConfiguration = .disabled)` |
| 108 | func | public | AgentConfiguration.resilience(_:) | `public @discardableResult func resilience(_ value: ResilienceConfiguration) -> AgentConfiguration` |
| 345 | var | public | AgentConfiguration.description | `public var description: String { get }` |

### Core/AgentEnvironment.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 15 | struct | public | AgentEnvironment | `public struct AgentEnvironment` |
| 16 | var | public | AgentEnvironment.inferenceProvider | `public var inferenceProvider: (any InferenceProvider)?` |
| 17 | var | public | AgentEnvironment.tracer | `public var tracer: (any Tracer)?` |
| 18 | var | public | AgentEnvironment.memory | `public var memory: (any Memory)?` |
| 19 | var | public | AgentEnvironment.membrane | `public var membrane: MembraneEnvironment?` |
| 21 | func | public | AgentEnvironment.init(inferenceProvider:tracer:memory:membrane:) | `public init(inferenceProvider: (any InferenceProvider)? = nil, tracer: (any Tracer)? = nil, memory: (any Memory)? = nil, membrane: MembraneEnvironment? = nil)` |
| 38 | enum | public | AgentEnvironmentValues | `public enum AgentEnvironmentValues` |
| 39 | var | public | AgentEnvironmentValues.current | `public static var current: AgentEnvironment { get }` |

### Core/AgentError.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | enum | public | AgentError | `public enum AgentError` |
| 15 | case | public | AgentError.invalidInput(reason:) | `public case invalidInput(reason: String)` |
| 20 | case | public | AgentError.cancelled | `public case cancelled` |
| 23 | case | public | AgentError.maxIterationsExceeded(iterations:) | `public case maxIterationsExceeded(iterations: Int)` |
| 26 | case | public | AgentError.timeout(duration:) | `public case timeout(duration: Duration)` |
| 29 | case | public | AgentError.invalidLoop(reason:) | `public case invalidLoop(reason: String)` |
| 34 | case | public | AgentError.toolNotFound(name:) | `public case toolNotFound(name: String)` |
| 37 | case | public | AgentError.toolExecutionFailed(toolName:underlyingError:) | `public case toolExecutionFailed(toolName: String, underlyingError: String)` |
| 305 | case | public | AgentError.toolFailure(toolName:message:cause:) | `public case toolFailure(toolName: String, message: String?, cause: (any Error)?)` |
| 40 | case | public | AgentError.invalidToolArguments(toolName:reason:) | `public case invalidToolArguments(toolName: String, reason: String)` |
| 45 | case | public | AgentError.inferenceProviderUnavailable(reason:) | `public case inferenceProviderUnavailable(reason: String)` |
| 48 | case | public | AgentError.contextWindowExceeded(tokenCount:limit:) | `public case contextWindowExceeded(tokenCount: Int, limit: Int)` |
| 51 | case | public | AgentError.guardrailViolation(reason:) | `public case guardrailViolation(reason: String)` |
| 54 | case | public | AgentError.contentFiltered(reason:) | `public case contentFiltered(reason: String)` |
| 57 | case | public | AgentError.unsupportedLanguage(language:) | `public case unsupportedLanguage(language: String)` |
| 60 | case | public | AgentError.generationFailed(reason:) | `public case generationFailed(reason: String)` |
| 63 | case | public | AgentError.modelNotAvailable(model:) | `public case modelNotAvailable(model: String)` |
| 68 | case | public | AgentError.rateLimitExceeded(retryAfter:) | `public case rateLimitExceeded(retryAfter: TimeInterval?)` |
| 73 | case | public | AgentError.embeddingFailed(reason:) | `public case embeddingFailed(reason: String)` |
| 78 | case | public | AgentError.agentNotFound(name:) | `public case agentNotFound(name: String)` |
| 81 | case | public | AgentError.internalError(reason:) | `public case internalError(reason: String)` |
| 84 | case | public | AgentError.toolCallingUnsupported | `public case toolCallingUnsupported` |
| 593 | case | public | AgentError.providerOwnedToolLoopRequiresExecutor | `public case providerOwnedToolLoopRequiresExecutor` |
| 628 | func | public | AgentError.==(_:_:) | `public static func == (lhs: AgentError, rhs: AgentError) -> Bool` |
| 90 | var | public | AgentError.errorDescription | `public var errorDescription: String? { get }` |
| 139 | var | public | AgentError.recoverySuggestion | `public var recoverySuggestion: String? { get }` |
| 152 | var | public | AgentError.debugDescription | `public var debugDescription: String { get }` |

### Core/AgentEvent.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 31 | enum | public | AgentEvent | `public enum AgentEvent` |
| 36 | case | public | AgentEvent.lifecycle(_:) | `public case lifecycle(AgentEvent.Lifecycle)` |
| 39 | case | public | AgentEvent.tool(_:) | `public case tool(AgentEvent.Tool)` |
| 42 | case | public | AgentEvent.output(_:) | `public case output(AgentEvent.Output)` |
| 45 | case | public | AgentEvent.handoff(_:) | `public case handoff(AgentEvent.Handoff)` |
| 48 | case | public | AgentEvent.observation(_:) | `public case observation(AgentEvent.Observation)` |
| 53 | enum | public | AgentEvent.Lifecycle | `public enum Lifecycle` |
| 55 | case | public | AgentEvent.Lifecycle.started(input:) | `public case started(input: String)` |
| 58 | case | public | AgentEvent.Lifecycle.completed(result:) | `public case completed(result: AgentResult)` |
| 61 | case | public | AgentEvent.Lifecycle.failed(error:) | `public case failed(error: AgentError)` |
| 64 | case | public | AgentEvent.Lifecycle.cancelled | `public case cancelled` |
| 67 | case | public | AgentEvent.Lifecycle.guardrailFailed(error:) | `public case guardrailFailed(error: GuardrailError)` |
| 70 | case | public | AgentEvent.Lifecycle.iterationStarted(number:) | `public case iterationStarted(number: Int)` |
| 73 | case | public | AgentEvent.Lifecycle.iterationCompleted(number:) | `public case iterationCompleted(number: Int)` |
| 77 | enum | public | AgentEvent.Tool | `public enum Tool` |
| 79 | case | public | AgentEvent.Tool.started(call:) | `public case started(call: ToolCall)` |
| 82 | case | public | AgentEvent.Tool.partial(update:) | `public case partial(update: PartialToolCallUpdate)` |
| 85 | case | public | AgentEvent.Tool.completed(call:result:) | `public case completed(call: ToolCall, result: ToolResult)` |
| 88 | case | public | AgentEvent.Tool.failed(call:error:) | `public case failed(call: ToolCall, error: AgentError)` |
| 92 | enum | public | AgentEvent.Output | `public enum Output` |
| 94 | case | public | AgentEvent.Output.token(_:) | `public case token(String)` |
| 97 | case | public | AgentEvent.Output.chunk(_:) | `public case chunk(String)` |
| 100 | case | public | AgentEvent.Output.thinking(thought:) | `public case thinking(thought: String)` |
| 103 | case | public | AgentEvent.Output.thinkingPartial(_:) | `public case thinkingPartial(String)` |
| 107 | enum | public | AgentEvent.Handoff | `public enum Handoff` |
| 109 | case | public | AgentEvent.Handoff.requested(from:to:reason:) | `public case requested(from: String, to: String, reason: String?)` |
| 112 | case | public | AgentEvent.Handoff.completed(from:to:) | `public case completed(from: String, to: String)` |
| 115 | case | public | AgentEvent.Handoff.started(from:to:input:) | `public case started(from: String, to: String, input: String)` |
| 118 | case | public | AgentEvent.Handoff.completedWithResult(from:to:result:) | `public case completedWithResult(from: String, to: String, result: AgentResult)` |
| 121 | case | public | AgentEvent.Handoff.skipped(from:to:reason:) | `public case skipped(from: String, to: String, reason: String)` |
| 125 | enum | public | AgentEvent.Observation | `public enum Observation` |
| 127 | case | public | AgentEvent.Observation.decision(_:options:) | `public case decision(String, options: [String]?)` |
| 130 | case | public | AgentEvent.Observation.planUpdated(_:stepCount:) | `public case planUpdated(String, stepCount: Int)` |
| 133 | case | public | AgentEvent.Observation.guardrailStarted(name:type:) | `public case guardrailStarted(name: String, type: GuardrailType)` |
| 136 | case | public | AgentEvent.Observation.guardrailPassed(name:type:) | `public case guardrailPassed(name: String, type: GuardrailType)` |
| 139 | case | public | AgentEvent.Observation.guardrailTriggered(name:type:message:) | `public case guardrailTriggered(name: String, type: GuardrailType, message: String?)` |
| 142 | case | public | AgentEvent.Observation.memoryAccessed(operation:count:) | `public case memoryAccessed(operation: MemoryOperation, count: Int)` |
| 145 | case | public | AgentEvent.Observation.llmStarted(model:promptTokens:) | `public case llmStarted(model: String?, promptTokens: Int?)` |
| 148 | case | public | AgentEvent.Observation.llmCompleted(model:promptTokens:completionTokens:duration:) | `public case llmCompleted(model: String?, promptTokens: Int?, completionTokens: Int?, duration: TimeInterval)` |
| 244 | enum | public | GuardrailType | `public enum GuardrailType` |
| 245 | case | public | GuardrailType.input | `public case input` |
| 246 | case | public | GuardrailType.output | `public case output` |
| 247 | case | public | GuardrailType.toolInput | `public case toolInput` |
| 248 | case | public | GuardrailType.toolOutput | `public case toolOutput` |
| 254 | enum | public | MemoryOperation | `public enum MemoryOperation` |
| 255 | case | public | MemoryOperation.read | `public case read` |
| 256 | case | public | MemoryOperation.write | `public case write` |
| 257 | case | public | MemoryOperation.search | `public case search` |
| 258 | case | public | MemoryOperation.clear | `public case clear` |
| 267 | struct | public | ToolCall | `public struct ToolCall` |
| 269 | var | public | ToolCall.id | `public let id: UUID` |
| 274 | var | public | ToolCall.providerCallId | `public let providerCallId: String?` |
| 277 | var | public | ToolCall.toolName | `public let toolName: String` |
| 280 | var | public | ToolCall.arguments | `public let arguments: [String : SendableValue]` |
| 283 | var | public | ToolCall.timestamp | `public let timestamp: Date` |
| 292 | func | public | ToolCall.init(id:providerCallId:toolName:arguments:timestamp:) | `public init(id: UUID = UUID(), providerCallId: String? = nil, toolName: String, arguments: [String : SendableValue] = [:], timestamp: Date = Date())` |
| 314 | func | public | ToolCall.init(from:) | `public init(from decoder: any Decoder) throws` |
| 323 | func | public | ToolCall.encode(to:) | `public func encode(to encoder: any Encoder) throws` |
| 268 | struct | public | ToolResult | `public struct ToolResult` |
| 270 | enum | public | ToolResult.Outcome | `public enum Outcome` |
| 272 | case | public | ToolResult.Outcome.success(_:) | `public case success(SendableValue)` |
| 275 | case | public | ToolResult.Outcome.failure(message:) | `public case failure(message: String)` |
| 278 | var | public | ToolResult.callId | `public let callId: UUID` |
| 281 | var | public | ToolResult.duration | `public let duration: Duration` |
| 284 | var | public | ToolResult.outcome | `public let outcome: ToolResult.Outcome` |
| 287 | var | public | ToolResult.isSuccess | `public var isSuccess: Bool { get }` |
| 300 | var | public | ToolResult.output | `public var output: SendableValue { get }` |
| 310 | var | public | ToolResult.errorMessage | `public var errorMessage: String? { get }` |
| 321 | func | public | ToolResult.init(callId:duration:outcome:) | `public init(callId: UUID, duration: Duration, outcome: ToolResult.Outcome)` |
| 332 | func | public | ToolResult.init(callId:isSuccess:output:duration:errorMessage:) | `public init(callId: UUID, isSuccess: Bool, output: SendableValue, duration: Duration, errorMessage: String? = nil)` (deprecated) |
| 355 | func | public | ToolResult.success(callId:output:duration:) | `public static func success(callId: UUID, output: SendableValue, duration: Duration) -> ToolResult` |
| 365 | func | public | ToolResult.failure(callId:error:duration:) | `public static func failure(callId: UUID, error: String, duration: Duration) -> ToolResult` |
| 400 | var | public | ToolCall.description | `public var description: String { get }` |
| 408 | var | public | ToolResult.description | `public var description: String { get }` |
| 420 | func | public | AgentEvent.==(_:_:) | `public static func == (lhs: AgentEvent, rhs: AgentEvent) -> Bool` |
| 441 | func | public | AgentEvent.Lifecycle.==(_:_:) | `public static func == (lhs: AgentEvent.Lifecycle, rhs: AgentEvent.Lifecycle) -> Bool` |
| 466 | func | public | AgentEvent.Tool.==(_:_:) | `public static func == (lhs: AgentEvent.Tool, rhs: AgentEvent.Tool) -> Bool` |
| 485 | func | public | AgentEvent.Output.==(_:_:) | `public static func == (lhs: AgentEvent.Output, rhs: AgentEvent.Output) -> Bool` |
| 504 | func | public | AgentEvent.Handoff.==(_:_:) | `public static func == (lhs: AgentEvent.Handoff, rhs: AgentEvent.Handoff) -> Bool` |
| 525 | func | public | AgentEvent.Observation.==(_:_:) | `public static func == (lhs: AgentEvent.Observation, rhs: AgentEvent.Observation) -> Bool` |

### Core/AgentResponse.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 35 | struct | public | ToolCallRecord | `public struct ToolCallRecord` |
| 37 | enum | public | ToolCallRecord.Outcome | `public enum Outcome` |
| 39 | case | public | ToolCallRecord.Outcome.success(_:) | `public case success(SendableValue)` |
| 42 | case | public | ToolCallRecord.Outcome.failure(message:) | `public case failure(message: String)` |
| 45 | var | public | ToolCallRecord.toolName | `public let toolName: String` |
| 48 | var | public | ToolCallRecord.arguments | `public let arguments: [String : SendableValue]` |
| 51 | var | public | ToolCallRecord.duration | `public let duration: Duration` |
| 54 | var | public | ToolCallRecord.timestamp | `public let timestamp: Date` |
| 57 | var | public | ToolCallRecord.outcome | `public let outcome: ToolCallRecord.Outcome` |
| 62 | var | public | ToolCallRecord.result | `public var result: SendableValue { get }` |
| 72 | var | public | ToolCallRecord.isSuccess | `public var isSuccess: Bool { get }` |
| 82 | var | public | ToolCallRecord.errorMessage | `public var errorMessage: String? { get }` |
| 95 | func | public | ToolCallRecord.init(toolName:arguments:duration:timestamp:outcome:) | `public init(toolName: String, arguments: [String : SendableValue] = [:], duration: Duration = .zero, timestamp: Date = Date(), outcome: ToolCallRecord.Outcome)` |
| 116 | func | public | ToolCallRecord.init(toolName:arguments:result:duration:timestamp:isSuccess:errorMessage:) | `public init(toolName: String, arguments: [String : SendableValue] = [:], result: SendableValue = .null, duration: Duration = .zero, timestamp: Date = Date(), isSuccess: Bool = true, errorMessage: String? = nil)` (deprecated) |
| 136 | func | public | ToolCallRecord.success(toolName:arguments:result:duration:timestamp:) | `public static func success(toolName: String, arguments: [String : SendableValue] = [:], result: SendableValue, duration: Duration = .zero, timestamp: Date = Date()) -> ToolCallRecord` |
| 152 | func | public | ToolCallRecord.failure(toolName:arguments:error:duration:timestamp:) | `public static func failure(toolName: String, arguments: [String : SendableValue] = [:], error: String, duration: Duration = .zero, timestamp: Date = Date()) -> ToolCallRecord` |
| 84 | var | public | ToolCallRecord.description | `public var description: String { get }` |
| 92 | var | public | ToolCallRecord.debugDescription | `public var debugDescription: String { get }` |
| 145 | struct | public | AgentResponse | `public struct AgentResponse` |
| 150 | var | public | AgentResponse.responseId | `public let responseId: String` |
| 153 | var | public | AgentResponse.output | `public let output: String` |
| 156 | var | public | AgentResponse.agentName | `public let agentName: String` |
| 159 | var | public | AgentResponse.timestamp | `public let timestamp: Date` |
| 165 | var | public | AgentResponse.metadata | `public let metadata: [String : SendableValue]` |
| 171 | var | public | AgentResponse.toolCalls | `public let toolCalls: [ToolCallRecord]` |
| 174 | var | public | AgentResponse.usage | `public let usage: TokenUsage?` |
| 181 | var | public | AgentResponse.iterationCount | `public let iterationCount: Int` |
| 201 | var | public | AgentResponse.asResult | `public var asResult: AgentResult { get }` |
| 251 | func | public | AgentResponse.init(responseId:output:agentName:timestamp:metadata:toolCalls:usage:iterationCount:) | `public init(responseId: String = UUID().uuidString, output: String, agentName: String, timestamp: Date = Date(), metadata: [String : SendableValue] = [:], toolCalls: [ToolCallRecord] = [], usage: TokenUsage? = nil, iterationCount: Int = 1)` |
| 275 | func | public | AgentResponse.==(_:_:) | `public static func == (lhs: AgentResponse, rhs: AgentResponse) -> Bool` |
| 290 | var | public | AgentResponse.description | `public var description: String { get }` |
| 306 | var | public | AgentResponse.debugDescription | `public var debugDescription: String { get }` |

### Core/AgentResult.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 23 | struct | public | AgentResult | `public struct AgentResult` |
| 25 | var | public | AgentResult.output | `public let output: String` |
| 28 | var | public | AgentResult.toolCalls | `public let toolCalls: [ToolCall]` |
| 31 | var | public | AgentResult.toolResults | `public let toolResults: [ToolResult]` |
| 34 | var | public | AgentResult.iterationCount | `public let iterationCount: Int` |
| 37 | var | public | AgentResult.duration | `public let duration: Duration` |
| 40 | var | public | AgentResult.tokenUsage | `public let tokenUsage: TokenUsage?` |
| 43 | var | public | AgentResult.metadata | `public let metadata: [String : SendableValue]` |
| 54 | func | public | AgentResult.init(output:toolCalls:toolResults:iterationCount:duration:tokenUsage:metadata:) | `public init(output: String, toolCalls: [ToolCall] = [], toolResults: [ToolResult] = [], iterationCount: Int = 1, duration: Duration = .zero, tokenUsage: TokenUsage? = nil, metadata: [String : SendableValue] = [:])` |
| 210 | var | public | AgentResult.description | `public var description: String { get }` |
| 227 | var | public | AgentResult.runtimeEngine | `public var runtimeEngine: String? { get }` |

### Core/AgentRuntime.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 31 | protocol | public | AgentRuntime | `public protocol AgentRuntime : Sendable` |
| 36 | var | public | AgentRuntime.name | `public nonisolated var name: String { get }` |
| 39 | var | public | AgentRuntime.tools | `public nonisolated var tools: [any AnyJSONTool] { get }` |
| 42 | var | public | AgentRuntime.instructions | `public nonisolated var instructions: String { get }` |
| 45 | var | public | AgentRuntime.configuration | `public nonisolated var configuration: AgentConfiguration { get }` |
| 48 | var | public | AgentRuntime.memory | `public nonisolated var memory: (any Memory)? { get }` |
| 51 | var | public | AgentRuntime.inferenceProvider | `public nonisolated var inferenceProvider: (any InferenceProvider)? { get }` |
| 54 | var | public | AgentRuntime.tracer | `public nonisolated var tracer: (any Tracer)? { get }` |
| 60 | var | public | AgentRuntime.inputGuardrails | `public nonisolated var inputGuardrails: [any InputGuardrail] { get }` |
| 66 | var | public | AgentRuntime.outputGuardrails | `public nonisolated var outputGuardrails: [any OutputGuardrail] { get }` |
| 72 | var | public | AgentRuntime.handoffs | `public nonisolated var handoffs: [AnyHandoffConfiguration] { get }` |
| 81 | func | public | AgentRuntime.run(_:session:observer:) | `public func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult` |
| 89 | func | public | AgentRuntime.stream(_:session:observer:) | `public nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 92 | func | public | AgentRuntime.cancel() | `public func cancel() async` |
| 108 | func | public | AgentRuntime.runWithResponse(_:session:observer:) | `public func runWithResponse(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResponse` |
| 119 | var | public | AgentRuntime.name | `public nonisolated var name: String { get }` |
| 122 | var | public | AgentRuntime.memory | `public nonisolated var memory: (any Memory)? { get }` |
| 125 | var | public | AgentRuntime.inferenceProvider | `public nonisolated var inferenceProvider: (any InferenceProvider)? { get }` |
| 128 | var | public | AgentRuntime.tracer | `public nonisolated var tracer: (any Tracer)? { get }` |
| 131 | var | public | AgentRuntime.inputGuardrails | `public nonisolated var inputGuardrails: [any InputGuardrail] { get }` |
| 134 | var | public | AgentRuntime.outputGuardrails | `public nonisolated var outputGuardrails: [any OutputGuardrail] { get }` |
| 137 | var | public | AgentRuntime.handoffs | `public nonisolated var handoffs: [AnyHandoffConfiguration] { get }` |
| 144 | func | public | AgentRuntime.run(_:observer:) | `public func run(_ input: String, observer: (any AgentObserver)? = nil) async throws -> AgentResult` |
| 149 | func | public | AgentRuntime.stream(_:observer:) | `public nonisolated func stream(_ input: String, observer: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 164 | func | public | AgentRuntime.runWithResponse(_:session:observer:) | `public func runWithResponse(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) async throws -> AgentResponse` |
| 205 | func | public | AgentRuntime.runWithResponse(_:observer:) | `public func runWithResponse(_ input: String, observer: (any AgentObserver)? = nil) async throws -> AgentResponse` |
| 221 | protocol | public | InferenceProvider | `public protocol InferenceProvider : Sendable` |
| 223 | var | public | InferenceProvider.capabilities | `public var capabilities: InferenceProviderCapabilities { get }` |
| 229 | var | public | InferenceProvider.promptTokenCounter | `public var promptTokenCounter: (any PromptTokenCounter)? { get }` |
| 235 | func | public | InferenceProvider.generate(prompt:options:) | `public func generate(prompt: String, options: InferenceOptions) async throws -> String` _(Compatibility only; Agent uses the messages overloads.)_ |
| 240 | func | public | InferenceProvider.stream(prompt:options:) | `public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, any Error>` _(Compatibility only; Agent uses the messages overloads.)_ |
| 245 | func | public | InferenceProvider.generateWithToolCalls(prompt:tools:options:) | `public func generateWithToolCalls(prompt: String, tools: [ToolSchema], options: InferenceOptions) async throws -> InferenceResponse` _(Compatibility only; Agent uses the messages overloads.)_ |
| 257 | func | public | InferenceProvider.streamWithToolCalls(prompt:tools:options:) | `public func streamWithToolCalls(prompt: String, tools: [ToolSchema], options: InferenceOptions) -> AsyncThrowingStream<InferenceStreamUpdate, any Error>` _(Compatibility only; Agent uses the messages overloads.)_ |
| 267 | func | public | InferenceProvider.generateStructured(prompt:request:options:) | `public func generateStructured(prompt: String, request: StructuredOutputRequest, options: InferenceOptions) async throws -> StructuredOutputResult` _(Compatibility only; Agent uses the messages overloads.)_ |
| 274 | func | public | InferenceProvider.generate(messages:options:) | `public func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String` |
| 277 | func | public | InferenceProvider.stream(messages:options:) | `public func stream(messages: [InferenceMessage], options: InferenceOptions) -> AsyncThrowingStream<String, any Error>` |
| 283 | func | public | InferenceProvider.generateWithToolCalls(messages:tools:options:) | `public func generateWithToolCalls(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions) async throws -> InferenceResponse` |
| 298 | func | public | InferenceProvider.generateWithToolCalls(messages:tools:options:toolExecutor:) | `public func generateWithToolCalls(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions, toolExecutor: ToolCallExecutor?) async throws -> InferenceResponse` |
| 306 | func | public | InferenceProvider.streamWithToolCalls(messages:tools:options:) | `public func streamWithToolCalls(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions) -> AsyncThrowingStream<InferenceStreamUpdate, any Error>` |
| 317 | func | public | InferenceProvider.streamWithToolCalls(messages:tools:options:toolExecutor:) | `public func streamWithToolCalls(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions, toolExecutor: ToolCallExecutor?) -> AsyncThrowingStream<InferenceStreamUpdate, any Error>` |
| 325 | func | public | InferenceProvider.generateStructured(messages:request:options:) | `public func generateStructured(messages: [InferenceMessage], request: StructuredOutputRequest, options: InferenceOptions) async throws -> StructuredOutputResult` |
| 265 | func | public | InferenceOptions.frequencyPenalty(_:) | `public @discardableResult func frequencyPenalty(_ value: Double?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.maxTokens(_:) | `public @discardableResult func maxTokens(_ value: Int?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.parallelToolCalls(_:) | `public @discardableResult func parallelToolCalls(_ value: Bool?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.presencePenalty(_:) | `public @discardableResult func presencePenalty(_ value: Double?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.previousResponseId(_:) | `public @discardableResult func previousResponseId(_ value: String?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.conversationId(_:) | `public @discardableResult func conversationId(_ value: String?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.providerSettings(_:) | `public @discardableResult func providerSettings(_ value: [String : SendableValue]?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.seed(_:) | `public @discardableResult func seed(_ value: Int?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.stopSequences(_:) | `public @discardableResult func stopSequences(_ value: [String]) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.temperature(_:) | `public @discardableResult func temperature(_ value: Double) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.toolChoice(_:) | `public @discardableResult func toolChoice(_ value: ToolChoice?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.topK(_:) | `public @discardableResult func topK(_ value: Int?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.topP(_:) | `public @discardableResult func topP(_ value: Double?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.truncation(_:) | `public @discardableResult func truncation(_ value: TruncationStrategy?) -> InferenceOptions` |
| 265 | func | public | InferenceOptions.verbosity(_:) | `public @discardableResult func verbosity(_ value: Verbosity?) -> InferenceOptions` |
| 266 | struct | public | InferenceOptions | `public struct InferenceOptions` |
| 268 | var | public | InferenceOptions.default | `public static let `default`: InferenceOptions` |
| 273 | var | public | InferenceOptions.creative | `public static var creative: InferenceOptions { get }` |
| 278 | var | public | InferenceOptions.precise | `public static var precise: InferenceOptions { get }` |
| 283 | var | public | InferenceOptions.balanced | `public static var balanced: InferenceOptions { get }` |
| 288 | var | public | InferenceOptions.codeGeneration | `public static var codeGeneration: InferenceOptions { get }` |
| 298 | var | public | InferenceOptions.chat | `public static var chat: InferenceOptions { get }` |
| 303 | var | public | InferenceOptions.temperature | `public var temperature: Double` |
| 306 | var | public | InferenceOptions.maxTokens | `public var maxTokens: Int?` |
| 309 | var | public | InferenceOptions.stopSequences | `public var stopSequences: [String]` |
| 312 | var | public | InferenceOptions.topP | `public var topP: Double?` |
| 315 | var | public | InferenceOptions.topK | `public var topK: Int?` |
| 318 | var | public | InferenceOptions.presencePenalty | `public var presencePenalty: Double?` |
| 321 | var | public | InferenceOptions.frequencyPenalty | `public var frequencyPenalty: Double?` |
| 326 | var | public | InferenceOptions.toolChoice | `public var toolChoice: ToolChoice?` |
| 329 | var | public | InferenceOptions.seed | `public var seed: Int?` |
| 332 | var | public | InferenceOptions.parallelToolCalls | `public var parallelToolCalls: Bool?` |
| 335 | var | public | InferenceOptions.truncation | `public var truncation: TruncationStrategy?` |
| 338 | var | public | InferenceOptions.verbosity | `public var verbosity: Verbosity?` |
| 341 | var | public | InferenceOptions.providerSettings | `public var providerSettings: [String : SendableValue]?` |
| 344 | var | public | InferenceOptions.previousResponseId | `public var previousResponseId: String?` |
| 402 | var | public | InferenceOptions.conversationId | `public var conversationId: String?` |
| 362 | func | public | InferenceOptions.init(temperature:maxTokens:stopSequences:topP:topK:presencePenalty:frequencyPenalty:toolChoice:seed:parallelToolCalls:truncation:verbosity:providerSettings:previousResponseId:) | `public init(temperature: Double = 1.0, maxTokens: Int? = nil, stopSequences: [String] = [], topP: Double? = nil, topK: Int? = nil, presencePenalty: Double? = nil, frequencyPenalty: Double? = nil, toolChoice: ToolChoice? = nil, seed: Int? = nil, parallelToolCalls: Bool? = nil, truncation: TruncationStrategy? = nil, verbosity: Verbosity? = nil, providerSettings: [String : SendableValue]? = nil, previousResponseId: String? = nil)` |
| 399 | func | public | InferenceOptions.stopSequences(_:) | `public func stopSequences(_ sequences: String...) -> InferenceOptions` |
| 408 | func | public | InferenceOptions.addStopSequence(_:) | `public func addStopSequence(_ sequence: String) -> InferenceOptions` |
| 416 | func | public | InferenceOptions.clearStopSequences() | `public func clearStopSequences() -> InferenceOptions` |
| 425 | func | public | InferenceOptions.with(_:) | `public func with(_ modifications: (inout InferenceOptions) -> Void) -> InferenceOptions` |
| 438 | struct | public | InferenceResponse | `public struct InferenceResponse` |
| 440 | enum | public | InferenceResponse.FinishReason | `public enum FinishReason` |
| 442 | case | public | InferenceResponse.FinishReason.completed | `public case completed` |
| 444 | case | public | InferenceResponse.FinishReason.toolCall | `public case toolCall` |
| 446 | case | public | InferenceResponse.FinishReason.maxTokens | `public case maxTokens` |
| 448 | case | public | InferenceResponse.FinishReason.contentFilter | `public case contentFilter` |
| 450 | case | public | InferenceResponse.FinishReason.cancelled | `public case cancelled` |
| 454 | struct | public | InferenceResponse.ParsedToolCall | `public struct ParsedToolCall` |
| 456 | var | public | InferenceResponse.ParsedToolCall.id | `public let id: String?` |
| 459 | var | public | InferenceResponse.ParsedToolCall.name | `public let name: String` |
| 462 | var | public | InferenceResponse.ParsedToolCall.arguments | `public let arguments: [String : SendableValue]` |
| 469 | func | public | InferenceResponse.ParsedToolCall.init(id:name:arguments:) | `public init(id: String? = nil, name: String, arguments: [String : SendableValue])` |
| 477 | var | public | InferenceResponse.content | `public let content: String?` |
| 480 | var | public | InferenceResponse.toolCalls | `public let toolCalls: [InferenceResponse.ParsedToolCall]` |
| 483 | var | public | InferenceResponse.finishReason | `public let finishReason: InferenceResponse.FinishReason` |
| 486 | var | public | InferenceResponse.usage | `public let usage: TokenUsage?` |
| 671 | var | public | InferenceResponse.transcriptMessages | `public let transcriptMessages: [InferenceMessage]` |
| 492 | var | public | InferenceResponse.hasToolCalls | `public var hasToolCalls: Bool { get }` |
| 499 | func | public | InferenceResponse.init(content:toolCalls:finishReason:usage:transcriptMessages:) | `public init(content: String? = nil, toolCalls: [InferenceResponse.ParsedToolCall] = [], finishReason: InferenceResponse.FinishReason = .completed, usage: TokenUsage? = nil, transcriptMessages: [InferenceMessage] = [])` |

### Core/CircularBuffer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 26 | struct | public | CircularBuffer | `public struct CircularBuffer<Element> where Element : Sendable` |
| 30 | var | public | CircularBuffer.capacity | `public let capacity: Int` |
| 36 | var | public | CircularBuffer.elements | `public var elements: [Element] { get }` |
| 53 | var | public | CircularBuffer.count | `public var count: Int { get }` |
| 60 | var | public | CircularBuffer.totalAppended | `public var totalAppended: Int { get }` |
| 65 | var | public | CircularBuffer.isEmpty | `public var isEmpty: Bool { get }` |
| 70 | var | public | CircularBuffer.isFull | `public var isFull: Bool { get }` |
| 75 | var | public | CircularBuffer.last | `public var last: Element? { get }` |
| 82 | var | public | CircularBuffer.first | `public var first: Element? { get }` |
| 94 | func | public | CircularBuffer.init(capacity:) | `public init(capacity: Int)` |
| 107 | func | public | CircularBuffer.append(_:) | `public mutating func append(_ element: Element)` |
| 118 | func | public | CircularBuffer.removeAll() | `public mutating func removeAll()` |
| 134 | var | public | CircularBuffer.startIndex | `public var startIndex: Int { get }` |
| 135 | var | public | CircularBuffer.endIndex | `public var endIndex: Int { get }` |
| 137 | func | public | CircularBuffer.index(after:) | `public func index(after i: Int) -> Int` |
| 141 | subscript | public | CircularBuffer.subscript(_:) | `public subscript(position: Int) -> Element { get }` |
| 154 | func | public | CircularBuffer.init(arrayLiteral:) | `public init(arrayLiteral elements: Element...)` |
| 165 | var | public | CircularBuffer.description | `public var description: String { get }` |
| 173 | func | public | CircularBuffer.==(_:_:) | `public static func == (lhs: CircularBuffer<Element>, rhs: CircularBuffer<Element>) -> Bool` |
| 181 | func | public | CircularBuffer.hash(into:) | `public func hash(into hasher: inout Hasher)` |

### Core/ContextProfile.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 15 | struct | public | ContextProfile | `public struct ContextProfile` |
| 18 | enum | public | ContextProfile.Preset | `public enum Preset` |
| 19 | case | public | ContextProfile.Preset.lite | `public case lite` |
| 20 | case | public | ContextProfile.Preset.balanced | `public case balanced` |
| 21 | case | public | ContextProfile.Preset.heavy | `public case heavy` |
| 22 | case | public | ContextProfile.Preset.strict4k | `public case strict4k` |
| 26 | struct | public | ContextProfile.Strict4kTemplate | `public struct Strict4kTemplate` |
| 27 | var | public | ContextProfile.Strict4kTemplate.default | `public static let `default`: ContextProfile.Strict4kTemplate` |
| 29 | var | public | ContextProfile.Strict4kTemplate.maxTotalContextTokens | `public var maxTotalContextTokens: Int` |
| 30 | var | public | ContextProfile.Strict4kTemplate.systemTokens | `public var systemTokens: Int` |
| 31 | var | public | ContextProfile.Strict4kTemplate.historyTokens | `public var historyTokens: Int` |
| 32 | var | public | ContextProfile.Strict4kTemplate.memoryTokens | `public var memoryTokens: Int` |
| 33 | var | public | ContextProfile.Strict4kTemplate.toolIOTokens | `public var toolIOTokens: Int` |
| 34 | var | public | ContextProfile.Strict4kTemplate.outputReserveTokens | `public var outputReserveTokens: Int` |
| 35 | var | public | ContextProfile.Strict4kTemplate.protocolOverheadReserveTokens | `public var protocolOverheadReserveTokens: Int` |
| 36 | var | public | ContextProfile.Strict4kTemplate.safetyMarginTokens | `public var safetyMarginTokens: Int` |
| 37 | var | public | ContextProfile.Strict4kTemplate.maxToolOutputTokens | `public var maxToolOutputTokens: Int` |
| 38 | var | public | ContextProfile.Strict4kTemplate.maxRetrievedItems | `public var maxRetrievedItems: Int` |
| 39 | var | public | ContextProfile.Strict4kTemplate.maxRetrievedItemTokens | `public var maxRetrievedItemTokens: Int` |
| 40 | var | public | ContextProfile.Strict4kTemplate.summaryCadenceTurns | `public var summaryCadenceTurns: Int` |
| 41 | var | public | ContextProfile.Strict4kTemplate.summaryTriggerUtilization | `public var summaryTriggerUtilization: Double` |
| 43 | var | public | ContextProfile.Strict4kTemplate.maxInputTokens | `public var maxInputTokens: Int { get }` |
| 47 | func | public | ContextProfile.Strict4kTemplate.init(maxTotalContextTokens:systemTokens:historyTokens:memoryTokens:toolIOTokens:outputReserveTokens:protocolOverheadReserveTokens:safetyMarginTokens:maxToolOutputTokens:maxRetrievedItems:maxRetrievedItemTokens:summaryCadenceTurns:summaryTriggerUtilization:) | `public init(maxTotalContextTokens: Int = 4096, systemTokens: Int = 512, historyTokens: Int = 1400, memoryTokens: Int = 900, toolIOTokens: Int = 600, outputReserveTokens: Int = 500, protocolOverheadReserveTokens: Int = 120, safetyMarginTokens: Int = 64, maxToolOutputTokens: Int = 600, maxRetrievedItems: Int = 3, maxRetrievedItemTokens: Int = 300, summaryCadenceTurns: Int = 2, summaryTriggerUtilization: Double = 0.65)` |
| 99 | struct | public | ContextProfile.PlatformDefaults | `public struct PlatformDefaults` |
| 101 | var | public | ContextProfile.PlatformDefaults.iOS | `public static let iOS: ContextProfile.PlatformDefaults` |
| 103 | var | public | ContextProfile.PlatformDefaults.macOS | `public static let macOS: ContextProfile.PlatformDefaults` |
| 106 | var | public | ContextProfile.PlatformDefaults.current | `public static var current: ContextProfile.PlatformDefaults { get }` |
| 115 | var | public | ContextProfile.PlatformDefaults.maxContextTokens | `public let maxContextTokens: Int` |
| 119 | var | public | ContextProfile.platformDefault | `public static var platformDefault: ContextProfile { get }` |
| 124 | var | public | ContextProfile.lite | `public static var lite: ContextProfile { get }` |
| 129 | var | public | ContextProfile.balanced | `public static var balanced: ContextProfile { get }` |
| 134 | var | public | ContextProfile.heavy | `public static var heavy: ContextProfile { get }` |
| 139 | var | public | ContextProfile.strict4k | `public static var strict4k: ContextProfile { get }` |
| 144 | func | public | ContextProfile.lite(maxContextTokens:) | `public static func lite(maxContextTokens: Int) -> ContextProfile` |
| 161 | func | public | ContextProfile.balanced(maxContextTokens:) | `public static func balanced(maxContextTokens: Int) -> ContextProfile` |
| 178 | func | public | ContextProfile.heavy(maxContextTokens:) | `public static func heavy(maxContextTokens: Int) -> ContextProfile` |
| 195 | func | public | ContextProfile.strict4k(template:) | `public static func strict4k(template: ContextProfile.Strict4kTemplate = .default) -> ContextProfile` |
| 232 | var | public | ContextProfile.preset | `public let preset: ContextProfile.Preset` |
| 235 | var | public | ContextProfile.maxContextTokens | `public let maxContextTokens: Int` |
| 238 | var | public | ContextProfile.maxTotalContextTokens | `public let maxTotalContextTokens: Int` |
| 241 | var | public | ContextProfile.workingTokenRatio | `public let workingTokenRatio: Double` |
| 244 | var | public | ContextProfile.memoryTokenRatio | `public let memoryTokenRatio: Double` |
| 247 | var | public | ContextProfile.toolIOTokenRatio | `public let toolIOTokenRatio: Double` |
| 250 | var | public | ContextProfile.summaryTokenRatio | `public let summaryTokenRatio: Double` |
| 253 | var | public | ContextProfile.maxToolOutputTokens | `public let maxToolOutputTokens: Int` |
| 256 | var | public | ContextProfile.maxRetrievedItems | `public let maxRetrievedItems: Int` |
| 259 | var | public | ContextProfile.maxRetrievedItemTokens | `public let maxRetrievedItemTokens: Int` |
| 262 | var | public | ContextProfile.summaryCadenceTurns | `public let summaryCadenceTurns: Int` |
| 265 | var | public | ContextProfile.summaryTriggerUtilization | `public let summaryTriggerUtilization: Double` |
| 268 | var | public | ContextProfile.outputReserveTokens | `public let outputReserveTokens: Int` |
| 271 | var | public | ContextProfile.protocolOverheadReserveTokens | `public let protocolOverheadReserveTokens: Int` |
| 274 | var | public | ContextProfile.safetyMarginTokens | `public let safetyMarginTokens: Int` |
| 277 | var | public | ContextProfile.bucketCaps | `public let bucketCaps: ContextBucketCaps?` |
| 300 | func | public | ContextProfile.init(preset:maxContextTokens:workingTokenRatio:memoryTokenRatio:toolIOTokenRatio:summaryTokenRatio:maxToolOutputTokens:maxRetrievedItems:maxRetrievedItemTokens:summaryCadenceTurns:summaryTriggerUtilization:maxTotalContextTokens:outputReserveTokens:protocolOverheadReserveTokens:safetyMarginTokens:bucketCaps:) | `public init(preset: ContextProfile.Preset, maxContextTokens: Int, workingTokenRatio: Double, memoryTokenRatio: Double, toolIOTokenRatio: Double, summaryTokenRatio: Double, maxToolOutputTokens: Int, maxRetrievedItems: Int, maxRetrievedItemTokens: Int, summaryCadenceTurns: Int, summaryTriggerUtilization: Double, maxTotalContextTokens: Int? = nil, outputReserveTokens: Int = 0, protocolOverheadReserveTokens: Int = 0, safetyMarginTokens: Int = 0, bucketCaps: ContextBucketCaps? = nil)` |
| 370 | var | public | ContextProfile.budget | `public var budget: ContextBudget { get }` |
| 407 | var | public | ContextProfile.memoryTokenLimit | `public var memoryTokenLimit: Int { get }` |
| 412 | var | public | ContextProfile.summaryTokenLimit | `public var summaryTokenLimit: Int { get }` |
| 455 | struct | public | ContextBudget | `public struct ContextBudget` |
| 456 | var | public | ContextBudget.maxTotalContextTokens | `public let maxTotalContextTokens: Int` |
| 457 | var | public | ContextBudget.maxContextTokens | `public let maxContextTokens: Int` |
| 458 | var | public | ContextBudget.maxInputTokens | `public let maxInputTokens: Int` |
| 459 | var | public | ContextBudget.maxOutputTokens | `public let maxOutputTokens: Int` |
| 460 | var | public | ContextBudget.workingTokens | `public let workingTokens: Int` |
| 461 | var | public | ContextBudget.memoryTokens | `public let memoryTokens: Int` |
| 462 | var | public | ContextBudget.toolIOTokens | `public let toolIOTokens: Int` |
| 463 | var | public | ContextBudget.outputReserveTokens | `public let outputReserveTokens: Int` |
| 464 | var | public | ContextBudget.protocolOverheadReserveTokens | `public let protocolOverheadReserveTokens: Int` |
| 465 | var | public | ContextBudget.safetyMarginTokens | `public let safetyMarginTokens: Int` |
| 466 | var | public | ContextBudget.maxToolOutputTokens | `public let maxToolOutputTokens: Int` |
| 467 | var | public | ContextBudget.maxRetrievedItems | `public let maxRetrievedItems: Int` |
| 468 | var | public | ContextBudget.maxRetrievedItemTokens | `public let maxRetrievedItemTokens: Int` |
| 469 | var | public | ContextBudget.bucketCaps | `public let bucketCaps: ContextBucketCaps?` |
| 473 | struct | public | ContextBucketCaps | `public struct ContextBucketCaps` |
| 474 | var | public | ContextBucketCaps.system | `public let system: Int` |
| 475 | var | public | ContextBucketCaps.history | `public let history: Int` |
| 476 | var | public | ContextBucketCaps.memory | `public let memory: Int` |
| 477 | var | public | ContextBucketCaps.toolIO | `public let toolIO: Int` |
| 479 | func | public | ContextBucketCaps.init(system:history:memory:toolIO:) | `public init(system: Int, history: Int, memory: Int, toolIO: Int)` |

### Core/Conversation.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 7 | class | public | Conversation | `public actor Conversation` |
| 9 | struct | public | Conversation.Message | `public struct Message` |
| 10 | enum | public | Conversation.Message.Role | `public enum Role` |
| 11 | case | public | Conversation.Message.Role.user | `public case user` |
| 12 | case | public | Conversation.Message.Role.assistant | `public case assistant` |
| 15 | var | public | Conversation.Message.role | `public let role: Conversation.Message.Role` |
| 16 | var | public | Conversation.Message.text | `public let text: String` |
| 18 | func | public | Conversation.Message.init(role:text:) | `public init(role: Conversation.Message.Role, text: String)` |
| 24 | var | public | Conversation.messages | `public var messages: [Conversation.Message] { get }` |
| 29 | var | public | Conversation.observer | `public var observer: (any AgentObserver)?` |
| 35 | func | public | Conversation.init(with:session:observer:) | `public init(with agent: some AgentRuntime, session: (any Session)? = nil, observer: (any AgentObserver)? = nil)` |
| 43 | func | public | Conversation.send(_:) | `public @discardableResult func send(_ input: String) async throws -> AgentResult` |
| 51 | func | public | Conversation.stream(_:) | `public nonisolated func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 57 | func | public | Conversation.streamText(_:) | `public @discardableResult func streamText(_ input: String) async throws -> String` |

### Core/Environment.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 12 | struct | public | Environment | `public @propertyWrapper struct Environment<Value> where Value : Sendable` |
| 15 | func | public | Environment.init(_:) | `public init(_ keyPath: KeyPath<AgentEnvironment, Value>)` |
| 19 | var | public | Environment.wrappedValue | `public var wrappedValue: Value { get }` |

### Core/EnvironmentAgent.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | struct | public | EnvironmentAgent | `public struct EnvironmentAgent` |
| 13 | func | public | EnvironmentAgent.init(base:modify:) | `public init(base: any AgentRuntime, modify: @escaping (inout AgentEnvironment) -> Void)` |
| 23 | var | public | EnvironmentAgent.tools | `public var tools: [any AnyJSONTool] { get }` |
| 24 | var | public | EnvironmentAgent.instructions | `public var instructions: String { get }` |
| 25 | var | public | EnvironmentAgent.configuration | `public var configuration: AgentConfiguration { get }` |
| 26 | var | public | EnvironmentAgent.memory | `public var memory: (any Memory)? { get }` |
| 27 | var | public | EnvironmentAgent.inferenceProvider | `public var inferenceProvider: (any InferenceProvider)? { get }` |
| 28 | var | public | EnvironmentAgent.tracer | `public var tracer: (any Tracer)? { get }` |
| 29 | var | public | EnvironmentAgent.inputGuardrails | `public var inputGuardrails: [any InputGuardrail] { get }` |
| 30 | var | public | EnvironmentAgent.outputGuardrails | `public var outputGuardrails: [any OutputGuardrail] { get }` |
| 31 | var | public | EnvironmentAgent.handoffs | `public var handoffs: [AnyHandoffConfiguration] { get }` |
| 33 | func | public | EnvironmentAgent.run(_:session:observer:) | `public func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult` |
| 46 | func | public | EnvironmentAgent.stream(_:session:observer:) | `public nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 61 | func | public | EnvironmentAgent.cancel() | `public func cancel() async` |
| 86 | func | public | AgentRuntime.environment(_:_:) | `public func environment<V>(_ keyPath: WritableKeyPath<AgentEnvironment, V>, _ value: V) -> EnvironmentAgent where V : Sendable` |
| 97 | func | public | AgentRuntime.memory(_:) | `public func memory(_ memory: any Memory) -> EnvironmentAgent` |

### Core/Execution/AgentContext.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 24 | enum | public | AgentContextKey | `public enum AgentContextKey` _(Availability: * (deprecated); Use typed ContextKey orchestration statics such as ContextKey.originalInput.)_ |
| 26 | case | public | AgentContextKey.originalInput | `public case originalInput` |
| 29 | case | public | AgentContextKey.previousOutput | `public case previousOutput` |
| 32 | case | public | AgentContextKey.currentAgentName | `public case currentAgentName` |
| 35 | case | public | AgentContextKey.executionPath | `public case executionPath` |
| 38 | case | public | AgentContextKey.startTime | `public case startTime` |
| 41 | case | public | AgentContextKey.metadata | `public case metadata` |
| 86 | protocol | public | AgentContextProviding | `public protocol AgentContextProviding : Sendable` _(Availability: * (deprecated); Use ContextKey<Value> with setTyped(_:value:)/getTyped(_:) instead)_ |
| 88 | var | public | AgentContextProviding.contextKey | `public static var contextKey: String { get }` |
| 118 | class | public | AgentContext | `public actor AgentContext` |
| 122 | var | public | AgentContext.originalInput | `public nonisolated let originalInput: String` |
| 125 | var | public | AgentContext.executionId | `public nonisolated let executionId: UUID` |
| 128 | var | public | AgentContext.createdAt | `public nonisolated let createdAt: Date` |
| 134 | var | public | AgentContext.allKeys | `public var allKeys: [String] { get }` |
| 149 | var | public | AgentContext.snapshot | `public var snapshot: [String : SendableValue] { get }` |
| 164 | func | public | AgentContext.init(input:initialValues:) | `public init(input: String, initialValues: [String : SendableValue] = [:])` |
| 206 | func | public | AgentContext.get(_:) | `public func get(_ key: String) -> SendableValue?` |
| 216 | func | public | AgentContext.get(_:) | `public func get(_ key: AgentContextKey) -> SendableValue?` _(Availability: * (deprecated); Use typed ContextKey accessors such as get(.originalInput).)_ |
| 225 | func | public | AgentContext.set(_:value:) | `public func set(_ key: String, value: SendableValue)` |
| 240 | func | public | AgentContext.set(_:value:) | `public func set(_ key: AgentContextKey, value: SendableValue)` _(Availability: * (deprecated); Use typed ContextKey accessors such as set(.originalInput, _).)_ |
| 283 | func | public | AgentContext.remove(_:) | `public @discardableResult func remove(_ key: String) -> SendableValue?` |
| 292 | func | public | AgentContext.addMessage(_:) | `public func addMessage(_ message: MemoryMessage)` |
| 302 | func | public | AgentContext.getMessages() | `public func getMessages() -> [MemoryMessage]` |
| 307 | func | public | AgentContext.clearMessages() | `public func clearMessages()` |
| 319 | func | public | AgentContext.recordExecution(agentName:) | `public func recordExecution(agentName: String)` |
| 328 | func | public | AgentContext.getExecutionPath() | `public func getExecutionPath() -> [String]` |
| 340 | func | public | AgentContext.setPreviousOutput(_:) | `public func setPreviousOutput(_ result: AgentResult)` |
| 347 | func | public | AgentContext.getPreviousOutput() | `public func getPreviousOutput() -> String?` |
| 367 | func | public | AgentContext.merge(from:overwrite:) | `public func merge(from other: AgentContext, overwrite: Bool = false) async` |
| 421 | func | public | AgentContext.copy(additionalValues:) | `public func copy(additionalValues: [String : SendableValue] = [:]) -> AgentContext` |
| 453 | func | public | AgentContext.setTyped(_:) | `public func setTyped<T>(_ context: T) where T : AgentContextProviding` |
| 461 | func | public | AgentContext.typed(_:) | `public func typed<T>(_: T.Type) -> T? where T : AgentContextProviding` |
| 470 | func | public | AgentContext.removeTyped(_:) | `public @discardableResult func removeTyped<T>(_: T.Type) -> T? where T : AgentContextProviding` |
| 478 | func | public | AgentContext.hasTyped(_:) | `public func hasTyped<T>(_: T.Type) -> Bool where T : AgentContextProviding` |
| 574 | var | public | AgentContext.description | `public nonisolated var description: String { get }` |
| 588 | var | public | AgentContext.debugDescription | `public nonisolated var debugDescription: String { get }` |

### Core/Execution/ContextKey.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 38 | struct | public | ContextKey | `public struct ContextKey<Value> where Value : Sendable` |
| 40 | var | public | ContextKey.name | `public let name: String` |
| 45 | func | public | ContextKey.init(_:) | `public init(_ name: String)` |
| 51 | func | public | ContextKey.==(_:_:) | `public static func == (lhs: ContextKey<Value>, rhs: ContextKey<Value>) -> Bool` |
| 57 | func | public | ContextKey.hash(into:) | `public func hash(into hasher: inout Hasher)` |
| 66 | var | public | ContextKey.userID | `public static let userID: ContextKey<String>` |
| 69 | var | public | ContextKey.sessionID | `public static let sessionID: ContextKey<String>` |
| 72 | var | public | ContextKey.correlationID | `public static let correlationID: ContextKey<String>` |
| 75 | var | public | ContextKey.language | `public static let language: ContextKey<String>` |
| 78 | var | public | ContextKey.apiVersion | `public static let apiVersion: ContextKey<String>` |
| 81 | var | public | ContextKey.originalInput | `public static let originalInput: ContextKey<String>` |
| 84 | var | public | ContextKey.previousOutput | `public static let previousOutput: ContextKey<String>` |
| 87 | var | public | ContextKey.currentAgentName | `public static let currentAgentName: ContextKey<String>` |
| 94 | var | public | ContextKey.requestCount | `public static let requestCount: ContextKey<Int>` |
| 97 | var | public | ContextKey.retryCount | `public static let retryCount: ContextKey<Int>` |
| 100 | var | public | ContextKey.iterationCount | `public static let iterationCount: ContextKey<Int>` |
| 103 | var | public | ContextKey.depth | `public static let depth: ContextKey<Int>` |
| 110 | var | public | ContextKey.isAuthenticated | `public static let isAuthenticated: ContextKey<Bool>` |
| 113 | var | public | ContextKey.isDebugMode | `public static let isDebugMode: ContextKey<Bool>` |
| 116 | var | public | ContextKey.verboseLogging | `public static let verboseLogging: ContextKey<Bool>` |
| 119 | var | public | ContextKey.isDryRun | `public static let isDryRun: ContextKey<Bool>` |
| 126 | var | public | ContextKey.permissions | `public static let permissions: ContextKey<[String]>` |
| 129 | var | public | ContextKey.tags | `public static let tags: ContextKey<[String]>` |
| 132 | var | public | ContextKey.featureFlags | `public static let featureFlags: ContextKey<[String]>` |
| 135 | var | public | ContextKey.executionPath | `public static let executionPath: ContextKey<[String]>` |
| 142 | var | public | ContextKey.timestamp | `public static let timestamp: ContextKey<Date>` |
| 145 | var | public | ContextKey.expiresAt | `public static let expiresAt: ContextKey<Date>` |
| 148 | var | public | ContextKey.startTime | `public static let startTime: ContextKey<Date>` |
| 166 | func | public | AgentContext.set(_:_:) | `public func set(_ key: ContextKey<String>, _ value: String)` |
| 173 | func | public | AgentContext.get(_:) | `public func get(_ key: ContextKey<String>) -> String?` |
| 178 | func | public | AgentContext.set(_:_:) | `public func set(_ key: ContextKey<Int>, _ value: Int)` |
| 184 | func | public | AgentContext.get(_:) | `public func get(_ key: ContextKey<Int>) -> Int?` |
| 189 | func | public | AgentContext.set(_:_:) | `public func set(_ key: ContextKey<Bool>, _ value: Bool)` |
| 195 | func | public | AgentContext.get(_:) | `public func get(_ key: ContextKey<Bool>) -> Bool?` |
| 200 | func | public | AgentContext.set(_:_:) | `public func set(_ key: ContextKey<Double>, _ value: Double)` |
| 206 | func | public | AgentContext.get(_:) | `public func get(_ key: ContextKey<Double>) -> Double?` |
| 211 | func | public | AgentContext.set(_:_:) | `public func set(_ key: ContextKey<[String]>, _ value: [String])` |
| 217 | func | public | AgentContext.get(_:) | `public func get(_ key: ContextKey<[String]>) -> [String]?` |
| 225 | func | public | AgentContext.set(_:_:) | `public func set(_ key: ContextKey<Date>, _ value: Date)` |
| 231 | func | public | AgentContext.get(_:) | `public func get(_ key: ContextKey<Date>) -> Date?` |
| 256 | func | public | AgentContext.setTyped(_:value:) | `public func setTyped<T>(_ key: ContextKey<T>, value: T) where T : Encodable, T : Sendable` |
| 273 | func | public | AgentContext.getTyped(_:) | `public func getTyped<T>(_ key: ContextKey<T>) -> T? where T : Decodable, T : Sendable` |
| 289 | func | public | AgentContext.getTyped(_:default:) | `public func getTyped<T>(_ key: ContextKey<T>, default defaultValue: T) -> T where T : Decodable, T : Sendable` |
| 304 | func | public | AgentContext.removeTyped(_:) | `public func removeTyped(_ key: ContextKey<some Sendable>)` |
| 319 | func | public | AgentContext.hasTyped(_:) | `public func hasTyped(_ key: ContextKey<some Sendable>) -> Bool` |

### Core/Handoff/Handoff.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 29 | struct | public | HandoffRequest | `public struct HandoffRequest` |
| 31 | var | public | HandoffRequest.sourceAgentName | `public let sourceAgentName: String` |
| 34 | var | public | HandoffRequest.targetAgentName | `public let targetAgentName: String` |
| 37 | var | public | HandoffRequest.input | `public let input: String` |
| 40 | var | public | HandoffRequest.reason | `public let reason: String?` |
| 43 | var | public | HandoffRequest.context | `public let context: [String : SendableValue]` |
| 53 | func | public | HandoffRequest.init(sourceAgentName:targetAgentName:input:reason:context:) | `public init(sourceAgentName: String, targetAgentName: String, input: String, reason: String? = nil, context: [String : SendableValue] = [:])` |
| 83 | struct | public | HandoffResult | `public struct HandoffResult` |
| 85 | var | public | HandoffResult.targetAgentName | `public let targetAgentName: String` |
| 88 | var | public | HandoffResult.input | `public let input: String` |
| 91 | var | public | HandoffResult.result | `public let result: AgentResult` |
| 94 | var | public | HandoffResult.transferredContext | `public let transferredContext: [String : SendableValue]` |
| 97 | var | public | HandoffResult.timestamp | `public let timestamp: Date` |
| 107 | func | public | HandoffResult.init(targetAgentName:input:result:transferredContext:timestamp:) | `public init(targetAgentName: String, input: String, result: AgentResult, transferredContext: [String : SendableValue], timestamp: Date = Date())` |
| 159 | protocol | public | HandoffReceiver | `public protocol HandoffReceiver : AgentRuntime` |
| 174 | func | public | HandoffReceiver.handleHandoff(_:context:) | `public func handleHandoff(_ request: HandoffRequest, context: AgentContext) async throws -> AgentResult` |
| 197 | func | public | HandoffReceiver.handleHandoff(_:context:) | `public func handleHandoff(_ request: HandoffRequest, context: AgentContext) async throws -> AgentResult` |
| 457 | var | public | HandoffRequest.description | `public var description: String { get }` |
| 472 | var | public | HandoffResult.description | `public var description: String { get }` |

### Core/Handoff/HandoffBuilder.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 23 | struct | public | AnyHandoffConfiguration | `public struct AnyHandoffConfiguration` |
| 25 | var | public | AnyHandoffConfiguration.targetAgent | `public let targetAgent: any AgentRuntime` |
| 28 | var | public | AnyHandoffConfiguration.toolNameOverride | `public let toolNameOverride: String?` |
| 31 | var | public | AnyHandoffConfiguration.toolDescription | `public let toolDescription: String?` |
| 34 | var | public | AnyHandoffConfiguration.onTransfer | `public let onTransfer: OnTransferCallback?` |
| 37 | var | public | AnyHandoffConfiguration.transform | `public let transform: TransformCallback?` |
| 40 | var | public | AnyHandoffConfiguration.when | `public let when: WhenCallback?` |
| 43 | var | public | AnyHandoffConfiguration.nestHandoffHistory | `public let nestHandoffHistory: Bool` |
| 50 | func | public | AnyHandoffConfiguration.init(_:) | `public init(_ configuration: HandoffConfiguration<some AgentRuntime>)` |
| 70 | func | public | AnyHandoffConfiguration.init(targetAgent:toolNameOverride:toolDescription:onTransfer:transform:when:nestHandoffHistory:) | `public init(targetAgent: any AgentRuntime, toolNameOverride: String? = nil, toolDescription: String? = nil, onTransfer: OnTransferCallback? = nil, transform: TransformCallback? = nil, when: WhenCallback? = nil, nestHandoffHistory: Bool = false)` |
| 93 | var | public | AnyHandoffConfiguration.effectiveToolName | `public var effectiveToolName: String { get }` |
| 102 | var | public | AnyHandoffConfiguration.effectiveToolDescription | `public var effectiveToolDescription: String { get }` |

### Core/Handoff/HandoffConfiguration.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 29 | struct | public | HandoffInputData | `public struct HandoffInputData` |
| 31 | var | public | HandoffInputData.sourceAgentName | `public let sourceAgentName: String` |
| 34 | var | public | HandoffInputData.targetAgentName | `public let targetAgentName: String` |
| 37 | var | public | HandoffInputData.input | `public let input: String` |
| 43 | var | public | HandoffInputData.context | `public let context: [String : SendableValue]` |
| 49 | var | public | HandoffInputData.metadata | `public var metadata: [String : SendableValue]` |
| 61 | func | public | HandoffInputData.init(sourceAgentName:targetAgentName:input:context:metadata:) | `public init(sourceAgentName: String, targetAgentName: String, input: String, context: [String : SendableValue] = [:], metadata: [String : SendableValue] = [:])` |
| 79 | var | public | HandoffInputData.description | `public var description: String { get }` |
| 111 | typealias | public | OnTransferCallback | `public typealias OnTransferCallback = (AgentContext, HandoffInputData) async throws -> Void` |
| 131 | typealias | public | TransformCallback | `public typealias TransformCallback = (HandoffInputData) -> HandoffInputData` |
| 150 | typealias | public | WhenCallback | `public typealias WhenCallback = (AgentContext, any AgentRuntime) async -> Bool` |
| 187 | struct | public | HandoffConfiguration | `public struct HandoffConfiguration<Target> where Target : AgentRuntime` |
| 189 | var | public | HandoffConfiguration.targetAgent | `public let targetAgent: Target` |
| 196 | var | public | HandoffConfiguration.toolNameOverride | `public let toolNameOverride: String?` |
| 202 | var | public | HandoffConfiguration.toolDescription | `public let toolDescription: String?` |
| 209 | var | public | HandoffConfiguration.onTransfer | `public let onTransfer: OnTransferCallback?` |
| 216 | var | public | HandoffConfiguration.transform | `public let transform: TransformCallback?` |
| 222 | var | public | HandoffConfiguration.when | `public let when: WhenCallback?` |
| 229 | var | public | HandoffConfiguration.nestHandoffHistory | `public let nestHandoffHistory: Bool` |
| 243 | func | public | HandoffConfiguration.init(targetAgent:toolNameOverride:toolDescription:onTransfer:transform:when:nestHandoffHistory:) | `public init(targetAgent: Target, toolNameOverride: String? = nil, toolDescription: String? = nil, onTransfer: OnTransferCallback? = nil, transform: TransformCallback? = nil, when: WhenCallback? = nil, nestHandoffHistory: Bool = false)` |
| 269 | var | public | HandoffConfiguration.effectiveToolName | `public var effectiveToolName: String { get }` |
| 282 | var | public | HandoffConfiguration.effectiveToolDescription | `public var effectiveToolDescription: String { get }` |

### Core/Handoff/HandoffOptions.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | enum | public | HandoffHistory | `public enum HandoffHistory` |
| 11 | case | public | HandoffHistory.none | `public case none` |
| 14 | case | public | HandoffHistory.nested | `public case nested` |
| 20 | case | public | HandoffHistory.summarized(maxTokens:) | `public case summarized(maxTokens: Int = 600)` |
| 33 | enum | public | HandoffPolicy | `public enum HandoffPolicy` |
| 35 | case | public | HandoffPolicy.minimal | `public case minimal` |
| 38 | case | public | HandoffPolicy.balanced | `public case balanced` |
| 41 | case | public | HandoffPolicy.strict | `public case strict` |
| 56 | struct | public | HandoffMetadataKey | `public struct HandoffMetadataKey<Value> where Value : Sendable` |
| 57 | var | public | HandoffMetadataKey.rawValue | `public let rawValue: String` |
| 61 | func | public | HandoffMetadataKey.init(_:encode:decode:) | `public init(_ rawValue: String, encode: @escaping (Value) -> SendableValue, decode: @escaping (SendableValue) -> Value?)` |
| 73 | func | public | HandoffMetadataKey.string(_:) | `public static func string(_ rawValue: String) -> HandoffMetadataKey<Value>` |
| 83 | func | public | HandoffMetadataKey.int(_:) | `public static func int(_ rawValue: String) -> HandoffMetadataKey<Value>` |
| 93 | func | public | HandoffMetadataKey.bool(_:) | `public static func bool(_ rawValue: String) -> HandoffMetadataKey<Value>` |
| 104 | func | public | HandoffInputData.metadata(for:) | `public func metadata<Value>(for key: HandoffMetadataKey<Value>) -> Value? where Value : Sendable` |
| 110 | func | public | HandoffInputData.settingMetadata(_:_:) | `public func settingMetadata<Value>(_ key: HandoffMetadataKey<Value>, _ value: Value) -> HandoffInputData where Value : Sendable` |
| 118 | struct | public | HandoffOptions | `public struct HandoffOptions<Target> where Target : AgentRuntime` |
| 128 | func | public | HandoffOptions.init() | `public init()` |
| 139 | func | public | HandoffOptions.name(_:) | `public func name(_ value: String) -> HandoffOptions<Target>` |
| 144 | func | public | HandoffOptions.description(_:) | `public func description(_ value: String) -> HandoffOptions<Target>` |
| 149 | func | public | HandoffOptions.onTransfer(_:) | `public func onTransfer(_ callback: @escaping OnTransferCallback) -> HandoffOptions<Target>` |
| 154 | func | public | HandoffOptions.transform(_:) | `public func transform(_ callback: @escaping TransformCallback) -> HandoffOptions<Target>` |
| 159 | func | public | HandoffOptions.when(_:) | `public func when(_ callback: @escaping WhenCallback) -> HandoffOptions<Target>` |
| 164 | func | public | HandoffOptions.history(_:) | `public func history(_ strategy: HandoffHistory) -> HandoffOptions<Target>` |
| 172 | func | public | HandoffOptions.policy(_:) | `public func policy(_ policy: HandoffPolicy) -> HandoffOptions<Target>` |
| 252 | func | public | AgentRuntime.asHandoff() | `public func asHandoff() -> AnyHandoffConfiguration` |
| 257 | func | public | AgentRuntime.asHandoff(_:) | `public func asHandoff(_ configure: (HandoffOptions<Self>) -> HandoffOptions<Self>) -> AnyHandoffConfiguration` |

### Core/Handoff/WorkflowError.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | enum | public | WorkflowError | `public enum WorkflowError` |
| 15 | case | public | WorkflowError.agentNotFound(name:) | `public case agentNotFound(name: String)` |
| 18 | case | public | WorkflowError.noAgentsConfigured | `public case noAgentsConfigured` |
| 23 | case | public | WorkflowError.handoffFailed(source:target:reason:) | `public case handoffFailed(source: String, target: String, reason: String)` |
| 26 | case | public | WorkflowError.handoffSkipped(from:to:reason:) | `public case handoffSkipped(from: String, to: String, reason: String)` |
| 31 | case | public | WorkflowError.routingFailed(reason:) | `public case routingFailed(reason: String)` |
| 34 | case | public | WorkflowError.invalidRouteCondition(reason:) | `public case invalidRouteCondition(reason: String)` |
| 39 | case | public | WorkflowError.mergeStrategyFailed(reason:) | `public case mergeStrategyFailed(reason: String)` |
| 42 | case | public | WorkflowError.allAgentsFailed(errors:) | `public case allAgentsFailed(errors: [String])` |
| 45 | case | public | WorkflowError.durableRuntimeUnavailable(reason:) | `public case durableRuntimeUnavailable(reason: String)` |
| 50 | case | public | WorkflowError.workflowInterrupted(reason:) | `public case workflowInterrupted(reason: String)` |
| 53 | case | public | WorkflowError.invalidGraph(_:) | `public case invalidGraph(WorkflowValidationError)` |
| 56 | case | public | WorkflowError.humanApprovalTimeout(prompt:) | `public case humanApprovalTimeout(prompt: String)` |
| 59 | case | public | WorkflowError.humanApprovalRejected(prompt:reason:) | `public case humanApprovalRejected(prompt: String, reason: String)` |
| 62 | case | public | WorkflowError.invalidWorkflow(reason:) | `public case invalidWorkflow(reason: String)` |
| 65 | case | public | WorkflowError.checkpointStoreRequired | `public case checkpointStoreRequired` |
| 68 | case | public | WorkflowError.checkpointNotFound(id:) | `public case checkpointNotFound(id: String)` |
| 71 | case | public | WorkflowError.resumeDefinitionMismatch(reason:) | `public case resumeDefinitionMismatch(reason: String)` |
| 77 | var | public | WorkflowError.errorDescription | `public var errorDescription: String? { get }` |
| 121 | var | public | WorkflowError.debugDescription | `public var debugDescription: String { get }` |

### Core/Handoff/WorkflowValidationError.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | enum | public | WorkflowValidationError | `public enum WorkflowValidationError` |
| 11 | case | public | WorkflowValidationError.emptyGraph | `public case emptyGraph` |
| 14 | case | public | WorkflowValidationError.duplicateNode(name:) | `public case duplicateNode(name: String)` |
| 17 | case | public | WorkflowValidationError.unknownDependency(node:dependency:availableNodes:) | `public case unknownDependency(node: String, dependency: String, availableNodes: [String])` |
| 20 | case | public | WorkflowValidationError.cycleDetected(nodes:) | `public case cycleDetected(nodes: [String])` |
| 24 | var | public | WorkflowValidationError.errorDescription | `public var errorDescription: String? { get }` |

### Core/InferenceStreamEvent.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 14 | enum | public | InferenceStreamEvent | `public enum InferenceStreamEvent` |
| 16 | case | public | InferenceStreamEvent.textDelta(_:) | `public case textDelta(String)` |
| 24 | case | public | InferenceStreamEvent.toolCallDelta(index:id:name:arguments:) | `public case toolCallDelta(index: Int, id: String?, name: String?, arguments: String)` |
| 27 | case | public | InferenceStreamEvent.finishReason(_:) | `public case finishReason(String)` |
| 30 | case | public | InferenceStreamEvent.usage(promptTokens:completionTokens:) | `public case usage(promptTokens: Int, completionTokens: Int)` |
| 33 | case | public | InferenceStreamEvent.done | `public case done` |

### Core/Logger+Swarm.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 35 | enum | public | Log | `public enum Log` |
| 43 | var | public | Log.agents | `public static let agents: Logger` |
| 52 | var | public | Log.memory | `public static let memory: Logger` |
| 61 | var | public | Log.tracing | `public static let tracing: Logger` |
| 70 | var | public | Log.metrics | `public static let metrics: Logger` |
| 79 | var | public | Log.orchestration | `public static let orchestration: Logger` |
| 90 | func | public | Log.bootstrap() | `public static func bootstrap()` |
| 109 | func | public | Log.bootstrap(_:) | `public static func bootstrap(_ factory: @escaping (String) -> any LogHandler)` |

### Core/ModelSettings.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 41 | func | public | ModelSettings.frequencyPenalty(_:) | `public @discardableResult func frequencyPenalty(_ value: Double?) -> ModelSettings` |
| 41 | func | public | ModelSettings.maxTokens(_:) | `public @discardableResult func maxTokens(_ value: Int?) -> ModelSettings` |
| 41 | func | public | ModelSettings.minP(_:) | `public @discardableResult func minP(_ value: Double?) -> ModelSettings` |
| 41 | func | public | ModelSettings.parallelToolCalls(_:) | `public @discardableResult func parallelToolCalls(_ value: Bool?) -> ModelSettings` |
| 41 | func | public | ModelSettings.presencePenalty(_:) | `public @discardableResult func presencePenalty(_ value: Double?) -> ModelSettings` |
| 41 | func | public | ModelSettings.promptCacheRetention(_:) | `public @discardableResult func promptCacheRetention(_ value: CacheRetention?) -> ModelSettings` |
| 41 | func | public | ModelSettings.providerSettings(_:) | `public @discardableResult func providerSettings(_ value: [String : SendableValue]?) -> ModelSettings` |
| 41 | func | public | ModelSettings.repetitionPenalty(_:) | `public @discardableResult func repetitionPenalty(_ value: Double?) -> ModelSettings` |
| 41 | func | public | ModelSettings.seed(_:) | `public @discardableResult func seed(_ value: Int?) -> ModelSettings` |
| 41 | func | public | ModelSettings.stopSequences(_:) | `public @discardableResult func stopSequences(_ value: [String]?) -> ModelSettings` |
| 41 | func | public | ModelSettings.temperature(_:) | `public @discardableResult func temperature(_ value: Double?) -> ModelSettings` |
| 41 | func | public | ModelSettings.toolChoice(_:) | `public @discardableResult func toolChoice(_ value: ToolChoice?) -> ModelSettings` |
| 41 | func | public | ModelSettings.topK(_:) | `public @discardableResult func topK(_ value: Int?) -> ModelSettings` |
| 41 | func | public | ModelSettings.topP(_:) | `public @discardableResult func topP(_ value: Double?) -> ModelSettings` |
| 41 | func | public | ModelSettings.truncation(_:) | `public @discardableResult func truncation(_ value: TruncationStrategy?) -> ModelSettings` |
| 41 | func | public | ModelSettings.verbosity(_:) | `public @discardableResult func verbosity(_ value: Verbosity?) -> ModelSettings` |
| 42 | struct | public | ModelSettings | `public struct ModelSettings` |
| 50 | var | public | ModelSettings.temperature | `public var temperature: Double?` |
| 57 | var | public | ModelSettings.topP | `public var topP: Double?` |
| 64 | var | public | ModelSettings.topK | `public var topK: Int?` |
| 70 | var | public | ModelSettings.maxTokens | `public var maxTokens: Int?` |
| 77 | var | public | ModelSettings.frequencyPenalty | `public var frequencyPenalty: Double?` |
| 84 | var | public | ModelSettings.presencePenalty | `public var presencePenalty: Double?` |
| 89 | var | public | ModelSettings.stopSequences | `public var stopSequences: [String]?` |
| 95 | var | public | ModelSettings.seed | `public var seed: Int?` |
| 102 | var | public | ModelSettings.toolChoice | `public var toolChoice: ToolChoice?` |
| 108 | var | public | ModelSettings.parallelToolCalls | `public var parallelToolCalls: Bool?` |
| 115 | var | public | ModelSettings.truncation | `public var truncation: TruncationStrategy?` |
| 120 | var | public | ModelSettings.verbosity | `public var verbosity: Verbosity?` |
| 125 | var | public | ModelSettings.promptCacheRetention | `public var promptCacheRetention: CacheRetention?` |
| 133 | var | public | ModelSettings.repetitionPenalty | `public var repetitionPenalty: Double?` |
| 139 | var | public | ModelSettings.minP | `public var minP: Double?` |
| 156 | var | public | ModelSettings.providerSettings | `public var providerSettings: [String : SendableValue]?` |
| 164 | func | public | ModelSettings.init(temperature:topP:topK:maxTokens:frequencyPenalty:presencePenalty:stopSequences:seed:toolChoice:parallelToolCalls:truncation:verbosity:promptCacheRetention:repetitionPenalty:minP:providerSettings:) | `public init(temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil, maxTokens: Int? = nil, frequencyPenalty: Double? = nil, presencePenalty: Double? = nil, stopSequences: [String]? = nil, seed: Int? = nil, toolChoice: ToolChoice? = nil, parallelToolCalls: Bool? = nil, truncation: TruncationStrategy? = nil, verbosity: Verbosity? = nil, promptCacheRetention: CacheRetention? = nil, repetitionPenalty: Double? = nil, minP: Double? = nil, providerSettings: [String : SendableValue]? = nil)` |
| 207 | var | public | ModelSettings.default | `public static var `default`: ModelSettings { get }` |
| 215 | var | public | ModelSettings.creative | `public static var creative: ModelSettings { get }` |
| 223 | var | public | ModelSettings.precise | `public static var precise: ModelSettings { get }` |
| 231 | var | public | ModelSettings.balanced | `public static var balanced: ModelSettings { get }` |
| 254 | func | public | ModelSettings.validate() | `public func validate() throws` |
| 331 | func | public | ModelSettings.merged(with:) | `public func merged(with other: ModelSettings) throws -> ModelSettings` |
| 372 | enum | public | ModelSettingsValidationError | `public enum ModelSettingsValidationError` |
| 375 | var | public | ModelSettingsValidationError.errorDescription | `public var errorDescription: String? { get }` |
| 397 | case | public | ModelSettingsValidationError.invalidTemperature(_:) | `public case invalidTemperature(Double)` |
| 400 | case | public | ModelSettingsValidationError.invalidTopP(_:) | `public case invalidTopP(Double)` |
| 403 | case | public | ModelSettingsValidationError.invalidTopK(_:) | `public case invalidTopK(Int)` |
| 406 | case | public | ModelSettingsValidationError.invalidMaxTokens(_:) | `public case invalidMaxTokens(Int)` |
| 409 | case | public | ModelSettingsValidationError.invalidFrequencyPenalty(_:) | `public case invalidFrequencyPenalty(Double)` |
| 412 | case | public | ModelSettingsValidationError.invalidPresencePenalty(_:) | `public case invalidPresencePenalty(Double)` |
| 415 | case | public | ModelSettingsValidationError.invalidMinP(_:) | `public case invalidMinP(Double)` |
| 418 | case | public | ModelSettingsValidationError.invalidRepetitionPenalty(_:) | `public case invalidRepetitionPenalty(Double)` |
| 424 | enum | public | ToolChoice | `public enum ToolChoice` |
| 427 | func | public | ToolChoice.init(from:) | `public init(from decoder: any Decoder) throws` |
| 451 | func | public | ToolChoice.encode(to:) | `public func encode(to encoder: any Encoder) throws` |
| 468 | case | public | ToolChoice.auto | `public case auto` |
| 471 | case | public | ToolChoice.none | `public case none` |
| 474 | case | public | ToolChoice.required | `public case required` |
| 477 | case | public | ToolChoice.specific(toolName:) | `public case specific(toolName: String)` |
| 492 | enum | public | TruncationStrategy | `public enum TruncationStrategy` |
| 494 | case | public | TruncationStrategy.auto | `public case auto` |
| 497 | case | public | TruncationStrategy.disabled | `public case disabled` |
| 503 | enum | public | Verbosity | `public enum Verbosity` |
| 505 | case | public | Verbosity.low | `public case low` |
| 508 | case | public | Verbosity.medium | `public case medium` |
| 511 | case | public | Verbosity.high | `public case high` |
| 517 | enum | public | CacheRetention | `public enum CacheRetention` |
| 519 | case | public | CacheRetention.inMemory | `public case inMemory` |
| 522 | case | public | CacheRetention.twentyFourHours | `public case twentyFourHours` |
| 525 | case | public | CacheRetention.fiveMinutes | `public case fiveMinutes` |
| 531 | var | public | ModelSettings.description | `public var description: String { get }` |

### Core/ObservedAgent.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 54 | func | public | AgentRuntime.observed(by:) | `public func observed(by observer: some AgentObserver) -> some AgentRuntime` |

### Core/PartialToolCallUpdate.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 12 | struct | public | PartialToolCallUpdate | `public struct PartialToolCallUpdate` |
| 14 | var | public | PartialToolCallUpdate.providerCallId | `public let providerCallId: String` |
| 17 | var | public | PartialToolCallUpdate.toolName | `public let toolName: String` |
| 20 | var | public | PartialToolCallUpdate.index | `public let index: Int` |
| 25 | var | public | PartialToolCallUpdate.argumentsFragment | `public let argumentsFragment: String` |
| 27 | func | public | PartialToolCallUpdate.init(providerCallId:toolName:index:argumentsFragment:) | `public init(providerCallId: String, toolName: String, index: Int, argumentsFragment: String)` |

### Core/ResponseTracker.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 15 | struct | public | SessionMetadata | `public struct SessionMetadata` |
| 17 | var | public | SessionMetadata.sessionId | `public let sessionId: String` |
| 20 | var | public | SessionMetadata.lastAccessTime | `public let lastAccessTime: Date` |
| 23 | var | public | SessionMetadata.responseCount | `public let responseCount: Int` |
| 31 | func | public | SessionMetadata.init(sessionId:lastAccessTime:responseCount:) | `public init(sessionId: String, lastAccessTime: Date, responseCount: Int)` |
| 106 | class | public | ResponseTracker | `public actor ResponseTracker` |
| 115 | var | public | ResponseTracker.maxHistorySize | `public nonisolated let maxHistorySize: Int` |
| 125 | var | public | ResponseTracker.maxSessions | `public nonisolated let maxSessions: Int?` |
| 156 | func | public | ResponseTracker.init(maxHistorySize:maxSessions:now:) | `public init(maxHistorySize: Int = 100, maxSessions: Int? = 1000, now: @escaping @Sendable () -> Date = { TurnEnvironment.live.now() })` |
| 194 | func | public | ResponseTracker.recordResponse(_:sessionId:) | `public func recordResponse(_ response: AgentResponse, sessionId: String)` |
| 248 | func | public | ResponseTracker.getLatestResponseId(for:) | `public func getLatestResponseId(for sessionId: String) -> String?` |
| 272 | func | public | ResponseTracker.getResponse(responseId:sessionId:) | `public func getResponse(responseId: String, sessionId: String) -> AgentResponse?` |
| 303 | func | public | ResponseTracker.getHistory(for:limit:) | `public func getHistory(for sessionId: String, limit: Int? = nil) -> [AgentResponse]` |
| 333 | func | public | ResponseTracker.clearHistory(for:) | `public func clearHistory(for sessionId: String)` |
| 352 | func | public | ResponseTracker.clearAllHistory() | `public func clearAllHistory()` |
| 370 | func | public | ResponseTracker.getCount(for:) | `public func getCount(for sessionId: String) -> Int` |
| 391 | func | public | ResponseTracker.getAllSessionIds() | `public func getAllSessionIds() -> [String]` |
| 405 | func | public | ResponseTracker.getTotalResponseCount() | `public func getTotalResponseCount() -> Int` |
| 438 | func | public | ResponseTracker.removeSessions(lastAccessedBefore:) | `public @discardableResult func removeSessions(lastAccessedBefore date: Date) -> Int` |
| 468 | func | public | ResponseTracker.removeSessions(notAccessedWithin:) | `public @discardableResult func removeSessions(notAccessedWithin interval: TimeInterval) -> Int` |
| 496 | func | public | ResponseTracker.getSessionMetadata(for:) | `public func getSessionMetadata(for sessionId: String) -> SessionMetadata?` |
| 534 | func | public | ResponseTracker.getAllSessionMetadata() | `public func getAllSessionMetadata() -> [SessionMetadata]` |

### Core/RunHooks.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 43 | protocol | public | AgentObserver | `public protocol AgentObserver : Sendable` |
| 51 | func | public | AgentObserver.onAgentStart(context:agent:input:) | `public func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async` |
| 59 | func | public | AgentObserver.onAgentEnd(context:agent:result:) | `public func onAgentEnd(context: AgentContext?, agent: any AgentRuntime, result: AgentResult) async` |
| 67 | func | public | AgentObserver.onError(context:agent:error:) | `public func onError(context: AgentContext?, agent: any AgentRuntime, error: any Error) async` |
| 75 | func | public | AgentObserver.onHandoff(context:fromAgent:toAgent:) | `public func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async` |
| 84 | func | public | AgentObserver.onToolStart(context:agent:call:) | `public func onToolStart(context: AgentContext?, agent: any AgentRuntime, call: ToolCall) async` |
| 89 | func | public | AgentObserver.onToolCallPartial(context:agent:update:) | `public func onToolCallPartial(context: AgentContext?, agent: any AgentRuntime, update: PartialToolCallUpdate) async` |
| 98 | func | public | AgentObserver.onToolEnd(context:agent:result:) | `public func onToolEnd(context: AgentContext?, agent: any AgentRuntime, result: ToolResult) async` |
| 115 | func | public | AgentObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `public func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [InferenceMessage]) async` |
| 131 | func | public | AgentObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `@available(*, deprecated, message: "Use onLLMStart(context:agent:systemPrompt:inputMessages:) with [InferenceMessage]. InferenceMessage is the source of truth; this MemoryMessage requirement will be removed in 0.7.") public func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [MemoryMessage]) async` |
| 140 | func | public | AgentObserver.onLLMEnd(context:agent:response:usage:) | `public func onLLMEnd(context: AgentContext?, agent: any AgentRuntime, response: String, usage: TokenUsage?) async` |
| 125 | func | public | AgentObserver.onGuardrailTriggered(context:guardrailName:guardrailType:result:) | `public func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async` |
| 133 | func | public | AgentObserver.onThinking(context:agent:thought:) | `public func onThinking(context: AgentContext?, agent: any AgentRuntime, thought: String) async` |
| 141 | func | public | AgentObserver.onThinkingPartial(context:agent:partialThought:) | `public func onThinkingPartial(context: AgentContext?, agent: any AgentRuntime, partialThought: String) async` |
| 149 | func | public | AgentObserver.onOutputToken(context:agent:token:) | `public func onOutputToken(context: AgentContext?, agent: any AgentRuntime, token: String) async` |
| 157 | func | public | AgentObserver.onIterationStart(context:agent:number:) | `public func onIterationStart(context: AgentContext?, agent: any AgentRuntime, number: Int) async` |
| 165 | func | public | AgentObserver.onIterationEnd(context:agent:number:) | `public func onIterationEnd(context: AgentContext?, agent: any AgentRuntime, number: Int) async` |
| 172 | func | public | AgentObserver.onAgentStart(context:agent:input:) | `public func onAgentStart(context _: AgentContext?, agent _: any AgentRuntime, input _: String) async` |
| 175 | func | public | AgentObserver.onAgentEnd(context:agent:result:) | `public func onAgentEnd(context _: AgentContext?, agent _: any AgentRuntime, result _: AgentResult) async` |
| 178 | func | public | AgentObserver.onError(context:agent:error:) | `public func onError(context _: AgentContext?, agent _: any AgentRuntime, error _: any Error) async` |
| 181 | func | public | AgentObserver.onHandoff(context:fromAgent:toAgent:) | `public func onHandoff(context _: AgentContext?, fromAgent _: any AgentRuntime, toAgent _: any AgentRuntime) async` |
| 184 | func | public | AgentObserver.onToolStart(context:agent:call:) | `public func onToolStart(context: AgentContext?, agent: any AgentRuntime, call: ToolCall) async` |
| 187 | func | public | AgentObserver.onToolCallPartial(context:agent:update:) | `public func onToolCallPartial(context: AgentContext?, agent: any AgentRuntime, update: PartialToolCallUpdate) async` |
| 190 | func | public | AgentObserver.onToolEnd(context:agent:result:) | `public func onToolEnd(context: AgentContext?, agent: any AgentRuntime, result: ToolResult) async` |
| 230 | func | public | AgentObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `public func onLLMStart(context _: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages _: [InferenceMessage]) async` |
| 234 | func | public | AgentObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `@available(*, deprecated, message: "Use onLLMStart(context:agent:systemPrompt:inputMessages:) with [InferenceMessage]. InferenceMessage is the source of truth; this MemoryMessage requirement will be removed in 0.7.") public func onLLMStart(context _: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages _: [MemoryMessage]) async` |
| 237 | func | public | AgentObserver.onLLMEnd(context:agent:response:usage:) | `public func onLLMEnd(context _: AgentContext?, agent _: any AgentRuntime, response _: String, usage _: TokenUsage?) async` |
| 199 | func | public | AgentObserver.onGuardrailTriggered(context:guardrailName:guardrailType:result:) | `public func onGuardrailTriggered(context _: AgentContext?, guardrailName _: String, guardrailType _: GuardrailType, result _: GuardrailResult) async` |
| 202 | func | public | AgentObserver.onThinking(context:agent:thought:) | `public func onThinking(context _: AgentContext?, agent _: any AgentRuntime, thought _: String) async` |
| 205 | func | public | AgentObserver.onThinkingPartial(context:agent:partialThought:) | `public func onThinkingPartial(context _: AgentContext?, agent _: any AgentRuntime, partialThought _: String) async` |
| 208 | func | public | AgentObserver.onOutputToken(context:agent:token:) | `public func onOutputToken(context _: AgentContext?, agent _: any AgentRuntime, token _: String) async` |
| 211 | func | public | AgentObserver.onIterationStart(context:agent:number:) | `public func onIterationStart(context _: AgentContext?, agent _: any AgentRuntime, number _: Int) async` |
| 214 | func | public | AgentObserver.onIterationEnd(context:agent:number:) | `public func onIterationEnd(context _: AgentContext?, agent _: any AgentRuntime, number _: Int) async` |
| 246 | struct | public | CompositeObserver | `public struct CompositeObserver` |
| 254 | func | public | CompositeObserver.init(observers:) | `public init(observers: [any AgentObserver])` |
| 260 | func | public | CompositeObserver.onAgentStart(context:agent:input:) | `public func onAgentStart(context: AgentContext?, agent: any AgentRuntime, input: String) async` |
| 270 | func | public | CompositeObserver.onAgentEnd(context:agent:result:) | `public func onAgentEnd(context: AgentContext?, agent: any AgentRuntime, result: AgentResult) async` |
| 280 | func | public | CompositeObserver.onError(context:agent:error:) | `public func onError(context: AgentContext?, agent: any AgentRuntime, error: any Error) async` |
| 290 | func | public | CompositeObserver.onHandoff(context:fromAgent:toAgent:) | `public func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async` |
| 300 | func | public | CompositeObserver.onToolStart(context:agent:call:) | `public func onToolStart(context: AgentContext?, agent: any AgentRuntime, call: ToolCall) async` |
| 310 | func | public | CompositeObserver.onToolCallPartial(context:agent:update:) | `public func onToolCallPartial(context: AgentContext?, agent: any AgentRuntime, update: PartialToolCallUpdate) async` |
| 320 | func | public | CompositeObserver.onToolEnd(context:agent:result:) | `public func onToolEnd(context: AgentContext?, agent: any AgentRuntime, result: ToolResult) async` |
| 399 | func | public | CompositeObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `public func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [InferenceMessage]) async` |
| 410 | func | public | CompositeObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `@available(*, deprecated, message: "Use onLLMStart(context:agent:systemPrompt:inputMessages:) with [InferenceMessage]. InferenceMessage is the source of truth; this MemoryMessage requirement will be removed in 0.7.") package func onLLMStart(context: AgentContext?, agent: any AgentRuntime, systemPrompt: String?, inputMessages: [MemoryMessage]) async` |
| 420 | func | public | CompositeObserver.onLLMEnd(context:agent:response:usage:) | `public func onLLMEnd(context: AgentContext?, agent: any AgentRuntime, response: String, usage: TokenUsage?) async` |
| 350 | func | public | CompositeObserver.onGuardrailTriggered(context:guardrailName:guardrailType:result:) | `public func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async` |
| 360 | func | public | CompositeObserver.onThinking(context:agent:thought:) | `public func onThinking(context: AgentContext?, agent: any AgentRuntime, thought: String) async` |
| 370 | func | public | CompositeObserver.onThinkingPartial(context:agent:partialThought:) | `public func onThinkingPartial(context: AgentContext?, agent: any AgentRuntime, partialThought: String) async` |
| 380 | func | public | CompositeObserver.onOutputToken(context:agent:token:) | `public func onOutputToken(context: AgentContext?, agent: any AgentRuntime, token: String) async` |
| 390 | func | public | CompositeObserver.onIterationStart(context:agent:number:) | `public func onIterationStart(context: AgentContext?, agent: any AgentRuntime, number: Int) async` |
| 400 | func | public | CompositeObserver.onIterationEnd(context:agent:number:) | `public func onIterationEnd(context: AgentContext?, agent: any AgentRuntime, number: Int) async` |
| 437 | struct | public | LoggingObserver | `public struct LoggingObserver` |
| 443 | func | public | LoggingObserver.init() | `public init()` |
| 447 | func | public | LoggingObserver.onAgentStart(context:agent:input:) | `public func onAgentStart(context: AgentContext?, agent _: any AgentRuntime, input: String) async` |
| 457 | func | public | LoggingObserver.onAgentEnd(context:agent:result:) | `public func onAgentEnd(context: AgentContext?, agent _: any AgentRuntime, result: AgentResult) async` |
| 466 | func | public | LoggingObserver.onError(context:agent:error:) | `public func onError(context: AgentContext?, agent _: any AgentRuntime, error: any Error) async` |
| 475 | func | public | LoggingObserver.onHandoff(context:fromAgent:toAgent:) | `public func onHandoff(context: AgentContext?, fromAgent: any AgentRuntime, toAgent: any AgentRuntime) async` |
| 486 | func | public | LoggingObserver.onToolStart(context:agent:call:) | `public func onToolStart(context: AgentContext?, agent _: any AgentRuntime, call: ToolCall) async` |
| 495 | func | public | LoggingObserver.onToolEnd(context:agent:result:) | `public func onToolEnd(context: AgentContext?, agent _: any AgentRuntime, result: ToolResult) async` |
| 507 | func | public | LoggingObserver.onLLMStart(context:agent:systemPrompt:inputMessages:) | `public func onLLMStart(context: AgentContext?, agent _: any AgentRuntime, systemPrompt _: String?, inputMessages: [InferenceMessage]) async` |
| 516 | func | public | LoggingObserver.onLLMEnd(context:agent:response:usage:) | `public func onLLMEnd(context: AgentContext?, agent _: any AgentRuntime, response _: String, usage: TokenUsage?) async` |
| 530 | func | public | LoggingObserver.onGuardrailTriggered(context:guardrailName:guardrailType:result:) | `public func onGuardrailTriggered(context: AgentContext?, guardrailName: String, guardrailType: GuardrailType, result: GuardrailResult) async` |
| 540 | func | public | LoggingObserver.onThinking(context:agent:thought:) | `public func onThinking(context: AgentContext?, agent _: any AgentRuntime, thought: String) async` |
| 550 | func | public | LoggingObserver.onOutputToken(context:agent:token:) | `public func onOutputToken(context: AgentContext?, agent _: any AgentRuntime, token: String) async` |
| 559 | func | public | LoggingObserver.onIterationStart(context:agent:number:) | `public func onIterationStart(context: AgentContext?, agent _: any AgentRuntime, number: Int) async` |

### Core/SendableValue.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 12 | enum | public | SendableValue | `public enum SendableValue` |
| 18 | var | public | SendableValue.boolValue | `public var boolValue: Bool? { get }` |
| 24 | var | public | SendableValue.intValue | `public var intValue: Int? { get }` |
| 30 | var | public | SendableValue.doubleValue | `public var doubleValue: Double? { get }` |
| 39 | var | public | SendableValue.stringValue | `public var stringValue: String? { get }` |
| 45 | var | public | SendableValue.arrayValue | `public var arrayValue: [SendableValue]? { get }` |
| 51 | var | public | SendableValue.dictionaryValue | `public var dictionaryValue: [String : SendableValue]? { get }` |
| 57 | var | public | SendableValue.isNull | `public var isNull: Bool { get }` |
| 64 | func | public | SendableValue.init(_:) | `public init(_ value: Bool)` |
| 65 | func | public | SendableValue.init(_:) | `public init(_ value: Int)` |
| 66 | func | public | SendableValue.init(_:) | `public init(_ value: Double)` |
| 67 | func | public | SendableValue.init(_:) | `public init(_ value: String)` |
| 68 | func | public | SendableValue.init(_:) | `public init(_ value: [SendableValue])` |
| 69 | func | public | SendableValue.init(_:) | `public init(_ value: [String : SendableValue])` |
| 74 | subscript | public | SendableValue.subscript(_:) | `public subscript(key: String) -> SendableValue? { get }` |
| 80 | subscript | public | SendableValue.subscript(_:) | `public subscript(index: Int) -> SendableValue? { get }` |
| 85 | case | public | SendableValue.null | `public case null` |
| 86 | case | public | SendableValue.bool(_:) | `public case bool(Bool)` |
| 87 | case | public | SendableValue.int(_:) | `public case int(Int)` |
| 88 | case | public | SendableValue.double(_:) | `public case double(Double)` |
| 89 | case | public | SendableValue.string(_:) | `public case string(String)` |
| 90 | case | public | SendableValue.array(_:) | `public case array([SendableValue])` |
| 91 | case | public | SendableValue.dictionary(_:) | `public case dictionary([String : SendableValue])` |
| 97 | func | public | SendableValue.init(nilLiteral:) | `public init(nilLiteral _: ())` |
| 103 | func | public | SendableValue.init(booleanLiteral:) | `public init(booleanLiteral value: Bool)` |
| 109 | func | public | SendableValue.init(integerLiteral:) | `public init(integerLiteral value: Int)` |
| 115 | func | public | SendableValue.init(floatLiteral:) | `public init(floatLiteral value: Double)` |
| 121 | func | public | SendableValue.init(stringLiteral:) | `public init(stringLiteral value: String)` |
| 127 | func | public | SendableValue.init(arrayLiteral:) | `public init(arrayLiteral elements: SendableValue...)` |
| 133 | func | public | SendableValue.init(dictionaryLiteral:) | `public init(dictionaryLiteral elements: (String, SendableValue)...)` |
| 141 | var | public | SendableValue.description | `public var description: String { get }` |
| 166 | var | public | SendableValue.debugDescription | `public var debugDescription: String { get }` |
| 185 | enum | public | SendableValue.ConversionError | `public enum ConversionError` |
| 188 | var | public | SendableValue.ConversionError.errorDescription | `public var errorDescription: String? { get }` |
| 199 | case | public | SendableValue.ConversionError.encodingFailed(_:) | `public case encodingFailed(String)` |
| 200 | case | public | SendableValue.ConversionError.decodingFailed(_:) | `public case decodingFailed(String)` |
| 201 | case | public | SendableValue.ConversionError.unsupportedType(_:) | `public case unsupportedType(String)` |
| 224 | func | public | SendableValue.init(encoding:) | `public init(encoding value: some Encodable) throws` |
| 283 | func | public | SendableValue.decode() | `public func decode<T>() throws -> T where T : Decodable` |

### Core/StreamHelper.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 26 | enum | public | StreamHelper | `public enum StreamHelper` |
| 28 | var | public | StreamHelper.defaultBufferSize | `public static let defaultBufferSize: Int` |
| 39 | func | public | StreamHelper.makeStream(bufferSize:) | `public static func makeStream<T>(bufferSize: Int = defaultBufferSize) -> (stream: AsyncThrowingStream<T, any Error>, continuation: AsyncThrowingStream<T, any Error>.Continuation) where T : Sendable` |
| 89 | func | public | StreamHelper.makeTrackedStream(bufferSize:operation:) | `public static func makeTrackedStream<T>(bufferSize: Int = defaultBufferSize, operation: @escaping (AsyncThrowingStream<T, any Error>.Continuation) async throws -> Void) -> AsyncThrowingStream<T, any Error> where T : Sendable` |
| 127 | func | public | StreamHelper.makeTrackedStream(for:bufferSize:operation:) | `public static func makeTrackedStream<A, T>(for actor: A, bufferSize: Int = defaultBufferSize, operation: @escaping (A, AsyncThrowingStream<T, any Error>.Continuation) async throws -> Void) -> AsyncThrowingStream<T, any Error> where A : Actor, T : Sendable` |

### Core/StreamOperations.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 12 | typealias | public | ToolCallInfo | `public typealias ToolCallInfo = ToolCall` |
| 16 | typealias | public | ToolResultInfo | `public typealias ToolResultInfo = ToolResult` |
| 31 | var | public | AsyncThrowingStream.thoughts | `public var thoughts: AsyncThrowingStream<String, any Error> { get }` |
| 43 | var | public | AsyncThrowingStream.toolCalls | `public var toolCalls: AsyncThrowingStream<ToolCall, any Error> { get }` |
| 62 | var | public | AsyncThrowingStream.toolResults | `public var toolResults: AsyncThrowingStream<ToolResult, any Error> { get }` |
| 104 | func | public | AsyncThrowingStream.retry(maxAttempts:delay:factory:) | `public static func retry(maxAttempts: Int = 3, delay: Duration = .zero, factory: @escaping () async -> AsyncThrowingStream<AgentEvent, any Error>) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 158 | func | public | AsyncThrowingStream.filterThinking() | `public func filterThinking() -> AsyncThrowingStream<AgentEvent, any Error>` |
| 173 | func | public | AsyncThrowingStream.filterToolEvents() | `public func filterToolEvents() -> AsyncThrowingStream<AgentEvent, any Error>` |
| 201 | func | public | AsyncThrowingStream.filter(_:) | `public func filter(_ predicate: @escaping (AgentEvent) -> Bool) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 228 | func | public | AsyncThrowingStream.map(_:) | `public func map<T>(_ transform: @escaping (AgentEvent) -> T) -> AsyncThrowingStream<T, any Error> where T : Sendable` |
| 249 | func | public | AsyncThrowingStream.mapToThoughts() | `public func mapToThoughts() -> AsyncThrowingStream<String, any Error>` |
| 271 | func | public | AsyncThrowingStream.collect() | `public func collect() async throws -> [AgentEvent]` |
| 289 | func | public | AsyncThrowingStream.collect(maxCount:) | `public func collect(maxCount: Int) async throws -> [AgentEvent]` |
| 313 | func | public | AsyncThrowingStream.first(where:) | `public func first(where predicate: @escaping (AgentEvent) -> Bool) async throws -> AgentEvent?` |
| 333 | func | public | AsyncThrowingStream.last() | `public func last() async throws -> AgentEvent?` |
| 360 | func | public | AsyncThrowingStream.reduce(_:_:) | `public func reduce<T>(_ initial: T, _ combine: @escaping (T, AgentEvent) -> T) async throws -> T where T : Sendable` |
| 384 | func | public | AsyncThrowingStream.take(_:) | `public func take(_ count: Int) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 407 | func | public | AsyncThrowingStream.drop(_:) | `public func drop(_ count: Int) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 434 | func | public | AsyncThrowingStream.timeout(after:) | `public func timeout(after duration: Duration) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 476 | func | public | AsyncThrowingStream.onEach(_:) | `public func onEach(_ action: @escaping (AgentEvent) -> Void) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 499 | func | public | AsyncThrowingStream.onComplete(_:) | `public func onComplete(_ action: @escaping (AgentResult) -> Void) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 520 | func | public | AsyncThrowingStream.onError(_:) | `public func onError(_ action: @escaping (AgentError) -> Void) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 543 | func | public | AsyncThrowingStream.catchErrors(_:) | `public func catchErrors(_ handler: @escaping (any Error) -> AgentEvent) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 580 | func | public | AsyncThrowingStream.debounce(for:) | `public func debounce(for duration: Duration) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 633 | func | public | AsyncThrowingStream.throttle(for:) | `public func throttle(for interval: Duration) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 678 | func | public | AsyncThrowingStream.buffer(count:) | `public func buffer(count: Int) -> AsyncThrowingStream<[AgentEvent], any Error>` |
| 719 | func | public | AsyncThrowingStream.compactMap(_:) | `public func compactMap<T>(_ transform: @escaping (AgentEvent) async throws -> T?) -> AsyncThrowingStream<T, any Error> where T : Sendable` |
| 747 | func | public | AsyncThrowingStream.distinctUntilChanged() | `public func distinctUntilChanged() -> AsyncThrowingStream<AgentEvent, any Error>` |
| 798 | func | public | AsyncThrowingStream.scan(_:_:) | `public func scan<T>(_ initial: T, _ combine: @escaping (T, AgentEvent) async throws -> T) -> AsyncThrowingStream<T, any Error> where T : Sendable` |

### Core/SwarmConfiguration.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 44 | var | public | Swarm.defaultProvider | `public static var defaultProvider: (any InferenceProvider)? { get async }` |
| 49 | var | public | Swarm.webConfiguration | `public static var webConfiguration: WebSearchTool.Configuration? { get async }` |
| 63 | func | public | Swarm.configure(provider:) | `public static func configure(provider: some InferenceProvider) async` |
| 74 | func | public | Swarm.configure(web:) | `public static func configure(web configuration: WebSearchTool.Configuration) async` |
| 79 | func | public | Swarm.reset() | `public static func reset() async` |

### Core/TokenUsage.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 14 | struct | public | TokenUsage | `public struct TokenUsage` |
| 16 | var | public | TokenUsage.inputTokens | `public let inputTokens: Int` |
| 19 | var | public | TokenUsage.outputTokens | `public let outputTokens: Int` |
| 22 | var | public | TokenUsage.totalTokens | `public var totalTokens: Int { get }` |
| 30 | func | public | TokenUsage.init(inputTokens:outputTokens:) | `public init(inputTokens: Int, outputTokens: Int)` |
| 36 | func | public | TokenUsage.merging(_:) | `public func merging(_ other: TokenUsage) -> TokenUsage` |
| 51 | var | public | TokenUsage.description | `public var description: String { get }` |

## 3. Agents

### Agents/Agent.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 45 | struct | public | Agent | `public struct Agent` |
| 50 | var | public | Agent.tools | `public let tools: [any AnyJSONTool]` |
| 51 | var | public | Agent.instructions | `public let instructions: String` |
| 52 | var | public | Agent.configuration | `public let configuration: AgentConfiguration` |
| 53 | var | public | Agent.memory | `public let memory: (any Memory)?` |
| 54 | var | public | Agent.inferenceProvider | `public let inferenceProvider: (any InferenceProvider)?` |
| 55 | var | public | Agent.inputGuardrails | `public let inputGuardrails: [any InputGuardrail]` |
| 56 | var | public | Agent.outputGuardrails | `public let outputGuardrails: [any OutputGuardrail]` |
| 57 | var | public | Agent.tracer | `public private(set) var tracer: (any Tracer)?` |
| 200 | var | public | Agent.metricsCollector | `public private(set) var metricsCollector: MetricsCollector?` |
| 58 | var | public | Agent.guardrailRunnerConfiguration | `public let guardrailRunnerConfiguration: GuardrailRunnerConfiguration` |
| 61 | var | public | Agent.handoffs | `public var handoffs: [AnyHandoffConfiguration] { get }` |
| 80 | func | public | Agent.init(tools:instructions:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:) | `public init(tools: [any AnyJSONTool] = [], instructions: String = "", configuration: AgentConfiguration = .default, memory: (any Memory)? = nil, inferenceProvider: (any InferenceProvider)? = nil, tracer: (any Tracer)? = nil, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffs: [AnyHandoffConfiguration] = []) throws` |
| 111 | func | public | Agent.init(_:tools:instructions:configuration:memory:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:) | `public init(_ inferenceProvider: any InferenceProvider, tools: [any AnyJSONTool] = [], instructions: String = "", configuration: AgentConfiguration = .default, memory: (any Memory)? = nil, tracer: (any Tracer)? = nil, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffs: [AnyHandoffConfiguration] = []) throws` |
| 150 | func | public | Agent.init(tools:instructions:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:) | `public init(tools: [some Tool] = [], instructions: String = "", configuration: AgentConfiguration = .default, memory: (any Memory)? = nil, inferenceProvider: (any InferenceProvider)? = nil, tracer: (any Tracer)? = nil, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffs: [AnyHandoffConfiguration] = []) throws` |
| 203 | func | public | Agent.init(tools:instructions:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffAgents:) | `public init(tools: [any AnyJSONTool] = [], instructions: String = "", configuration: AgentConfiguration = .default, memory: (any Memory)? = nil, inferenceProvider: (any InferenceProvider)? = nil, tracer: (any Tracer)? = nil, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffAgents: [any AgentRuntime]) throws` |
| 260 | func | public | Agent.init(_:configuration:memory:inferenceProvider:tracer:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:tools:) | `public init(_ instructions: String, configuration: AgentConfiguration = .default, memory: (any Memory)? = nil, inferenceProvider: (any InferenceProvider)? = nil, tracer: (any Tracer)? = nil, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffs: [AnyHandoffConfiguration] = [], @ToolBuilder tools: () -> [any AnyJSONTool] = { [] }) throws` |
| 1130 | func | public | Agent.makeDefaultMemory() | `public static func makeDefaultMemory() throws -> any Memory` _(Integrations: `DefaultAgentMemory`; lean: `SlidingWindowMemory`)_ |
| 295 | func | public | Agent.run(_:session:observer:) | `public func run(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) async throws -> AgentResult` |
| 303 | func | public | Agent.cancel() | `public func cancel() async` |
| 313 | func | public | Agent.stream(_:session:observer:) | `public func stream(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, any Error>` |
| 336 | func | public | Agent.runWithResponse(_:session:observer:) | `public func runWithResponse(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) async throws -> AgentResponse` |
| 1259 | struct | public | Agent.Builder | `public struct Builder` |
| 1265 | func | public | Agent.Builder.init() | `public init()` |
| 1273 | func | public | Agent.Builder.tools(_:) | `public @discardableResult func tools(_ tools: [any AnyJSONTool]) -> Agent.Builder` |
| 1283 | func | public | Agent.Builder.tools(_:) | `public @discardableResult func tools(_ tools: [some Tool]) -> Agent.Builder` |
| 1293 | func | public | Agent.Builder.addTool(_:) | `public @discardableResult func addTool(_ tool: some AnyJSONTool) -> Agent.Builder` |
| 1303 | func | public | Agent.Builder.addTool(_:) | `public @discardableResult func addTool(_ tool: any AnyJSONTool) -> Agent.Builder` |
| 1313 | func | public | Agent.Builder.addTool(_:) | `public @discardableResult func addTool(_ tool: some Tool) -> Agent.Builder` |
| 1322 | func | public | Agent.Builder.withBuiltInTools() | `public @discardableResult func withBuiltInTools() -> Agent.Builder` |
| 1332 | func | public | Agent.Builder.instructions(_:) | `public @discardableResult func instructions(_ instructions: String) -> Agent.Builder` |
| 1342 | func | public | Agent.Builder.configuration(_:) | `public @discardableResult func configuration(_ configuration: AgentConfiguration) -> Agent.Builder` |
| 1352 | func | public | Agent.Builder.memory(_:) | `public @discardableResult func memory(_ memory: any Memory) -> Agent.Builder` |
| 1362 | func | public | Agent.Builder.inferenceProvider(_:) | `public @discardableResult func inferenceProvider(_ provider: any InferenceProvider) -> Agent.Builder` |
| 1372 | func | public | Agent.Builder.tracer(_:) | `public @discardableResult func tracer(_ tracer: any Tracer) -> Agent.Builder` |
| 1382 | func | public | Agent.Builder.inputGuardrails(_:) | `public @discardableResult func inputGuardrails(_ guardrails: [any InputGuardrail]) -> Agent.Builder` |
| 1392 | func | public | Agent.Builder.addInputGuardrail(_:) | `public @discardableResult func addInputGuardrail(_ guardrail: any InputGuardrail) -> Agent.Builder` |
| 1402 | func | public | Agent.Builder.outputGuardrails(_:) | `public @discardableResult func outputGuardrails(_ guardrails: [any OutputGuardrail]) -> Agent.Builder` |
| 1412 | func | public | Agent.Builder.addOutputGuardrail(_:) | `public @discardableResult func addOutputGuardrail(_ guardrail: any OutputGuardrail) -> Agent.Builder` |
| 1422 | func | public | Agent.Builder.guardrailRunnerConfiguration(_:) | `public @discardableResult func guardrailRunnerConfiguration(_ configuration: GuardrailRunnerConfiguration) -> Agent.Builder` |
| 1432 | func | public | Agent.Builder.handoffs(_:) | `public @discardableResult func handoffs(_ handoffs: [AnyHandoffConfiguration]) -> Agent.Builder` |
| 1442 | func | public | Agent.Builder.addHandoff(_:) | `public @discardableResult func addHandoff(_ handoff: AnyHandoffConfiguration) -> Agent.Builder` |
| 1457 | func | public | Agent.Builder.handoff(to:configure:) | `public @discardableResult func handoff<Target>(to target: Target, configure: (HandoffOptions<Target>) -> HandoffOptions<Target> = { $0 }) -> Agent.Builder where Target : AgentRuntime` |
| 1476 | func | public | Agent.Builder.handoffs(_:) | `public @discardableResult func handoffs<each Target>(_ targets: repeat each Target) -> Agent.Builder where repeat each Target : AgentRuntime` |
| 1485 | func | public | Agent.Builder.build() | `public func build() throws -> Agent` |
| 1542 | func | public | Agent.init(name:instructions:tools:inferenceProvider:memory:tracer:configuration:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffs:) | `public init(name: String, instructions: String = "", tools: [any AnyJSONTool] = [], inferenceProvider: (any InferenceProvider)? = nil, memory: (any Memory)? = nil, tracer: (any Tracer)? = nil, configuration: AgentConfiguration = .default, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffs: [AnyHandoffConfiguration] = []) throws` |
| 1604 | func | public | Agent.init(name:instructions:tools:inferenceProvider:memory:tracer:configuration:inputGuardrails:outputGuardrails:guardrailRunnerConfiguration:handoffAgents:) | `public init(name: String, instructions: String = "", tools: [any AnyJSONTool] = [], inferenceProvider: (any InferenceProvider)? = nil, memory: (any Memory)? = nil, tracer: (any Tracer)? = nil, configuration: AgentConfiguration = .default, inputGuardrails: [any InputGuardrail] = [], outputGuardrails: [any OutputGuardrail] = [], guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default, handoffAgents: [any AgentRuntime]) throws` |

## 4. Tools

### Tools/AgentTool.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 35 | struct | public | AgentTool | `public struct AgentTool` |
| 38 | var | public | AgentTool.name | `public let name: String` |
| 39 | var | public | AgentTool.description | `public let description: String` |
| 40 | var | public | AgentTool.parameters | `public let parameters: [ToolParameter]` |
| 42 | func | public | AgentTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 68 | func | public | AgentTool.init(agent:name:description:) | `public init(agent: any AgentRuntime, name: String? = nil, description: String? = nil)` |
| 106 | func | public | AgentRuntime.asTool(name:description:) | `public func asTool(name: String? = nil, description: String? = nil) -> AgentTool` |

### Tools/BuiltInTools.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 27 | struct | public | CalculatorTool | `public struct CalculatorTool` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 30 | var | public | CalculatorTool.name | `public let name: String` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 31 | var | public | CalculatorTool.description | `public let description: String` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 36 | var | public | CalculatorTool.parameters | `public let parameters: [ToolParameter]` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 46 | func | public | CalculatorTool.init() | `public init()` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 48 | func | public | CalculatorTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 109 | struct | public | DateTimeTool | `public struct DateTimeTool` |
| 110 | var | public | DateTimeTool.name | `public let name: String` |
| 111 | var | public | DateTimeTool.description | `public let description: String` |
| 113 | var | public | DateTimeTool.parameters | `public let parameters: [ToolParameter]` |
| 133 | func | public | DateTimeTool.init() | `public init()` |
| 135 | func | public | DateTimeTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 201 | struct | public | StringTool | `public struct StringTool` |
| 202 | var | public | StringTool.name | `public let name: String` |
| 203 | var | public | StringTool.description | `public let description: String` |
| 208 | var | public | StringTool.parameters | `public let parameters: [ToolParameter]` |
| 251 | func | public | StringTool.init() | `public init()` |
| 253 | func | public | StringTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 345 | func | public | WebSearchTool.fromEnvironment() | `public static func fromEnvironment() -> WebSearchTool` |
| 362 | enum | public | BuiltInTools | `public enum BuiltInTools` |
| 367 | var | public | BuiltInTools.calculator | `public static let calculator: CalculatorTool` _(Availability: Darwin-only (`#if canImport(Darwin)`))_ |
| 371 | var | public | BuiltInTools.dateTime | `public static let dateTime: DateTimeTool` |
| 374 | var | public | BuiltInTools.string | `public static let string: StringTool` |
| 377 | var | public | BuiltInTools.semanticCompactor | `public static let semanticCompactor: SemanticCompactorTool` |
| 383 | var | public | BuiltInTools.all | `public static var all: [any AnyJSONTool] { get }` |

### Tools/FunctionTool.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | struct | public | ToolArguments | `public struct ToolArguments` |
| 10 | var | public | ToolArguments.raw | `public let raw: [String : SendableValue]` |
| 11 | var | public | ToolArguments.toolName | `public let toolName: String` |
| 13 | func | public | ToolArguments.init(_:toolName:) | `public init(_ arguments: [String : SendableValue], toolName: String = "tool")` |
| 19 | func | public | ToolArguments.require(_:as:) | `public func require<T>(_ key: String, as type: T.Type = T.self) throws -> T` |
| 45 | func | public | ToolArguments.optional(_:as:) | `public func optional<T>(_ key: String, as type: T.Type = T.self) -> T?` |
| 57 | func | public | ToolArguments.string(_:default:) | `public func string(_ key: String, default defaultValue: String = "") -> String` |
| 62 | func | public | ToolArguments.int(_:default:) | `public func int(_ key: String, default defaultValue: Int = 0) -> Int` |
| 96 | struct | public | FunctionTool | `public struct FunctionTool` |
| 99 | var | public | FunctionTool.name | `public let name: String` |
| 100 | var | public | FunctionTool.description | `public let description: String` |
| 101 | var | public | FunctionTool.parameters | `public let parameters: [ToolParameter]` |
| 109 | func | public | FunctionTool.init(name:description:parameters:handler:) | `public init(name: String, description: String, parameters: [ToolParameter] = [], handler: @escaping (ToolArguments) async throws -> SendableValue)` |
| 121 | func | public | FunctionTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |

### Tools/ParallelToolExecutor.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 73 | class | public | ParallelToolExecutor | `public actor ParallelToolExecutor` |
| 79 | func | public | ParallelToolExecutor.init() | `public init()` |
| 122 | func | public | ParallelToolExecutor.executeInParallel(_:using:agent:context:) | `public func executeInParallel(_ calls: [ToolCall], using registry: ToolRegistry, agent: any AgentRuntime, context: AgentContext?) async throws -> [ToolExecutionResult]` |
| 237 | func | public | ParallelToolExecutor.executeInParallel(_:using:agent:context:errorStrategy:) | `public func executeInParallel(_ calls: [ToolCall], using registry: ToolRegistry, agent: any AgentRuntime, context: AgentContext?, errorStrategy: ParallelExecutionErrorStrategy) async throws -> [ToolExecutionResult]` |
| 365 | func | public | ParallelToolExecutor.executeAllCapturingErrors(_:using:agent:context:) | `public func executeAllCapturingErrors(_ calls: [ToolCall], using registry: ToolRegistry, agent: any AgentRuntime, context: AgentContext? = nil) async throws -> [ToolExecutionResult]` |
| 393 | func | public | ParallelToolExecutor.executeAllOrFail(_:using:agent:context:) | `public func executeAllOrFail(_ calls: [ToolCall], using registry: ToolRegistry, agent: any AgentRuntime, context: AgentContext? = nil) async throws -> [ToolExecutionResult]` |

### Tools/SemanticCompactorTool.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 17 | var | public | SemanticCompactorTool.description | `public let description: String` |
| 17 | func | public | SemanticCompactorTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 17 | var | public | SemanticCompactorTool.name | `public let name: String` |
| 17 | var | public | SemanticCompactorTool.parameters | `public let parameters: [ToolParameter]` |
| 18 | struct | public | SemanticCompactorTool | `public struct SemanticCompactorTool` |
| 40 | func | public | SemanticCompactorTool.init(summarizer:) | `public init(summarizer: (any Summarizer)? = nil)` |
| 66 | func | public | SemanticCompactorTool.execute() | `public func execute() async throws -> String` |

### Tools/Tool.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 32 | protocol | public | AnyJSONTool | `public protocol AnyJSONTool : Sendable` |
| 34 | var | public | AnyJSONTool.name | `public var name: String { get }` |
| 37 | var | public | AnyJSONTool.description | `public var description: String { get }` |
| 40 | var | public | AnyJSONTool.parameters | `public var parameters: [ToolParameter] { get }` |
| 43 | var | public | AnyJSONTool.inputGuardrails | `public var inputGuardrails: [any ToolInputGuardrail] { get }` |
| 46 | var | public | AnyJSONTool.outputGuardrails | `public var outputGuardrails: [any ToolOutputGuardrail] { get }` |
| 55 | var | public | AnyJSONTool.isEnabled | `public var isEnabled: Bool { get }` |
| 61 | func | public | AnyJSONTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 68 | var | public | AnyJSONTool.schema | `public var schema: ToolSchema { get }` |
| 73 | var | public | AnyJSONTool.inputGuardrails | `public var inputGuardrails: [any ToolInputGuardrail] { get }` |
| 76 | var | public | AnyJSONTool.outputGuardrails | `public var outputGuardrails: [any ToolOutputGuardrail] { get }` |
| 79 | var | public | AnyJSONTool.isEnabled | `public var isEnabled: Bool { get }` |
| 84 | func | public | AnyJSONTool.validateArguments(_:) | `public func validateArguments(_ arguments: [String : SendableValue]) throws` |
| 100 | func | public | AnyJSONTool.normalizeArguments(_:) | `public func normalizeArguments(_ arguments: [String : SendableValue]) throws -> [String : SendableValue]` |
| 114 | func | public | AnyJSONTool.requiredString(_:from:) | `public func requiredString(_ key: String, from arguments: [String : SendableValue]) throws -> String` |
| 130 | func | public | AnyJSONTool.optionalString(_:from:default:) | `public func optionalString(_ key: String, from arguments: [String : SendableValue], default defaultValue: String? = nil) -> String?` |
| 445 | struct | public | ToolParameter | `public struct ToolParameter` |
| 447 | enum | public | ToolParameter.ParameterType | `public indirect enum ParameterType` |
| 450 | var | public | ToolParameter.ParameterType.description | `public var description: String { get }` |
| 463 | case | public | ToolParameter.ParameterType.string | `public case string` |
| 464 | case | public | ToolParameter.ParameterType.int | `public case int` |
| 465 | case | public | ToolParameter.ParameterType.double | `public case double` |
| 466 | case | public | ToolParameter.ParameterType.bool | `public case bool` |
| 467 | case | public | ToolParameter.ParameterType.array(elementType:) | `public case array(elementType: ToolParameter.ParameterType)` |
| 468 | case | public | ToolParameter.ParameterType.object(properties:) | `public case object(properties: [ToolParameter])` |
| 469 | case | public | ToolParameter.ParameterType.oneOf(_:) | `public case oneOf([String])` |
| 470 | case | public | ToolParameter.ParameterType.any | `public case any` |
| 474 | var | public | ToolParameter.name | `public let name: String` |
| 477 | var | public | ToolParameter.description | `public let description: String` |
| 480 | var | public | ToolParameter.type | `public let type: ToolParameter.ParameterType` |
| 483 | var | public | ToolParameter.isRequired | `public let isRequired: Bool` |
| 486 | var | public | ToolParameter.defaultValue | `public let defaultValue: SendableValue?` |
| 495 | func | public | ToolParameter.init(name:description:type:isRequired:defaultValue:) | `public init(name: String, description: String, type: ToolParameter.ParameterType, isRequired: Bool = true, defaultValue: SendableValue? = nil)` |
| 526 | enum | public | ToolRegistryError | `public enum ToolRegistryError` |
| 528 | case | public | ToolRegistryError.duplicateToolName(name:) | `public case duplicateToolName(name: String)` |
| 531 | class | public | ToolRegistry | `public actor ToolRegistry` |
| 535 | var | public | ToolRegistry.allTools | `public var allTools: [any AnyJSONTool] { get }` |
| 540 | var | public | ToolRegistry.toolNames | `public var toolNames: [String] { get }` |
| 545 | var | public | ToolRegistry.schemas | `public var schemas: [ToolSchema] { get }` |
| 550 | var | public | ToolRegistry.count | `public var count: Int { get }` |
| 555 | func | public | ToolRegistry.init() | `public init()` |
| 560 | func | public | ToolRegistry.init(tools:) | `public init(tools: [any AnyJSONTool]) throws` |
| 572 | func | public | ToolRegistry.init(tools:) | `public init(tools: [some Tool]) throws` |
| 585 | func | public | ToolRegistry.register(_:) | `public func register(_ tool: any AnyJSONTool) throws` |
| 595 | func | public | ToolRegistry.register(_:) | `public func register(_ tool: some Tool) throws` |
| 606 | func | public | ToolRegistry.register(_:) | `public func register(_ newTools: [some Tool]) throws` |
| 619 | func | public | ToolRegistry.register(_:) | `public func register(_ newTools: [any AnyJSONTool]) throws` |
| 630 | func | public | ToolRegistry.unregister(named:) | `public func unregister(named name: String)` |
| 637 | func | public | ToolRegistry.tool(named:) | `public func tool(named name: String) -> (any AnyJSONTool)?` |
| 644 | func | public | ToolRegistry.contains(named:) | `public func contains(named name: String) -> Bool` |
| 659 | func | public | ToolRegistry.execute(toolNamed:arguments:agent:context:observer:) | `public func execute(toolNamed name: String, arguments: [String : SendableValue], agent: (any AgentRuntime)? = nil, context: AgentContext? = nil, observer: (any AgentObserver)? = nil) async throws -> SendableValue` |

### Tools/ToolBridging.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | struct | public | AnyJSONToolAdapter | `public struct AnyJSONToolAdapter<T> where T : Tool` |
| 14 | var | public | AnyJSONToolAdapter.tool | `public let tool: T` |
| 16 | var | public | AnyJSONToolAdapter.name | `public var name: String { get }` |
| 17 | var | public | AnyJSONToolAdapter.description | `public var description: String { get }` |
| 18 | var | public | AnyJSONToolAdapter.parameters | `public var parameters: [ToolParameter] { get }` |
| 19 | var | public | AnyJSONToolAdapter.inputGuardrails | `public var inputGuardrails: [any ToolInputGuardrail] { get }` |
| 20 | var | public | AnyJSONToolAdapter.outputGuardrails | `public var outputGuardrails: [any ToolOutputGuardrail] { get }` |
| 22 | func | public | AnyJSONToolAdapter.init(_:) | `public init(_ tool: T)` |
| 26 | func | public | AnyJSONToolAdapter.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 54 | func | public | Tool.asAnyJSONTool() | `public func asAnyJSONTool() -> AnyJSONToolAdapter<Self>` |

### Tools/ToolExecutionResult.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 37 | enum | public | ParallelExecutionErrorStrategy | `public enum ParallelExecutionErrorStrategy` |
| 43 | case | public | ParallelExecutionErrorStrategy.failFast | `public case failFast` |
| 50 | case | public | ParallelExecutionErrorStrategy.collectErrors | `public case collectErrors` |
| 57 | case | public | ParallelExecutionErrorStrategy.continueOnError | `public case continueOnError` |
| 86 | struct | public | ToolExecutionResult | `public struct ToolExecutionResult` |
| 88 | var | public | ToolExecutionResult.toolName | `public let toolName: String` |
| 91 | var | public | ToolExecutionResult.arguments | `public let arguments: [String : SendableValue]` |
| 97 | var | public | ToolExecutionResult.result | `public let result: Result<SendableValue, any Error>` |
| 103 | var | public | ToolExecutionResult.duration | `public let duration: Duration` |
| 106 | var | public | ToolExecutionResult.timestamp | `public let timestamp: Date` |
| 109 | var | public | ToolExecutionResult.isSuccess | `public var isSuccess: Bool { get }` |
| 119 | var | public | ToolExecutionResult.value | `public var value: SendableValue? { get }` |
| 129 | var | public | ToolExecutionResult.error | `public var error: (any Error)? { get }` |
| 148 | func | public | ToolExecutionResult.init(toolName:arguments:result:duration:timestamp:) | `public init(toolName: String, arguments: [String : SendableValue], result: Result<SendableValue, any Error>, duration: Duration, timestamp: Date = Date())` |
| 171 | func | public | ToolExecutionResult.success(toolName:arguments:value:duration:timestamp:) | `public static func success(toolName: String, arguments: [String : SendableValue], value: SendableValue, duration: Duration, timestamp: Date = Date()) -> ToolExecutionResult` |
| 196 | func | public | ToolExecutionResult.failure(toolName:arguments:error:duration:timestamp:) | `public static func failure(toolName: String, arguments: [String : SendableValue], error: any Error, duration: Duration, timestamp: Date = Date()) -> ToolExecutionResult` |
| 216 | var | public | ToolExecutionResult.description | `public var description: String { get }` |
| 237 | var | public | ToolExecutionResult.debugDescription | `public var debugDescription: String { get }` |
| 256 | func | public | ToolExecutionResult.==(_:_:) | `public static func == (lhs: ToolExecutionResult, rhs: ToolExecutionResult) -> Bool` |

### Tools/ToolParameterBuilder.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 37 | @resultBuilder | public | ToolParameterBuilder | `public @resultBuilder struct ToolParameterBuilder` |
| 39 | func | public | ToolParameterBuilder.buildBlock(_:) | `public static func buildBlock(_ components: ToolParameter...) -> [ToolParameter]` |
| 44 | func | public | ToolParameterBuilder.buildBlock() | `public static func buildBlock() -> [ToolParameter]` |
| 49 | func | public | ToolParameterBuilder.buildBlock(_:) | `public static func buildBlock(_ components: [ToolParameter]...) -> [ToolParameter]` |
| 54 | func | public | ToolParameterBuilder.buildOptional(_:) | `public static func buildOptional(_ component: [ToolParameter]?) -> [ToolParameter]` |
| 59 | func | public | ToolParameterBuilder.buildEither(first:) | `public static func buildEither(first component: [ToolParameter]) -> [ToolParameter]` |
| 64 | func | public | ToolParameterBuilder.buildEither(second:) | `public static func buildEither(second component: [ToolParameter]) -> [ToolParameter]` |
| 69 | func | public | ToolParameterBuilder.buildArray(_:) | `public static func buildArray(_ components: [[ToolParameter]]) -> [ToolParameter]` |
| 74 | func | public | ToolParameterBuilder.buildExpression(_:) | `public static func buildExpression(_ expression: ToolParameter) -> [ToolParameter]` |
| 79 | func | public | ToolParameterBuilder.buildExpression(_:) | `public static func buildExpression(_ expression: [ToolParameter]) -> [ToolParameter]` |
| 84 | func | public | ToolParameterBuilder.buildLimitedAvailability(_:) | `public static func buildLimitedAvailability(_ component: [ToolParameter]) -> [ToolParameter]` |
| 89 | func | public | ToolParameterBuilder.buildFinalResult(_:) | `public static func buildFinalResult(_ component: [ToolParameter]) -> [ToolParameter]` |
| 119 | func | public | Parameter(_:description:type:required:default:) | `public func Parameter(_ name: String, description: String, type: ToolParameter.ParameterType, required: Bool = true, default defaultValue: SendableValue? = nil) -> ToolParameter` |
| 144 | func | public | Parameter(_:description:type:required:default:) | `public func Parameter(_ name: String, description: String, type: ToolParameter.ParameterType, required: Bool = true, default defaultValue: Int) -> ToolParameter` |
| 169 | func | public | Parameter(_:description:type:required:default:) | `public func Parameter(_ name: String, description: String, type: ToolParameter.ParameterType, required: Bool = true, default defaultValue: String) -> ToolParameter` |
| 194 | func | public | Parameter(_:description:type:required:default:) | `public func Parameter(_ name: String, description: String, type: ToolParameter.ParameterType, required: Bool = true, default defaultValue: Bool) -> ToolParameter` |
| 219 | func | public | Parameter(_:description:type:required:default:) | `public func Parameter(_ name: String, description: String, type: ToolParameter.ParameterType, required: Bool = true, default defaultValue: Double) -> ToolParameter` |
| 253 | @resultBuilder | public | ToolBuilder | `public @resultBuilder struct ToolBuilder` |
| 255 | func | public | ToolBuilder.buildBlock() | `public static func buildBlock() -> [any AnyJSONTool]` |
| 260 | func | public | ToolBuilder.buildBlock(_:) | `public static func buildBlock(_ components: any AnyJSONTool...) -> [any AnyJSONTool]` |
| 265 | func | public | ToolBuilder.buildBlock(_:) | `public static func buildBlock(_ components: [any AnyJSONTool]...) -> [any AnyJSONTool]` |
| 270 | func | public | ToolBuilder.buildOptional(_:) | `public static func buildOptional(_ component: [any AnyJSONTool]?) -> [any AnyJSONTool]` |
| 275 | func | public | ToolBuilder.buildEither(first:) | `public static func buildEither(first component: [any AnyJSONTool]) -> [any AnyJSONTool]` |
| 280 | func | public | ToolBuilder.buildEither(second:) | `public static func buildEither(second component: [any AnyJSONTool]) -> [any AnyJSONTool]` |
| 285 | func | public | ToolBuilder.buildArray(_:) | `public static func buildArray(_ components: [[any AnyJSONTool]]) -> [any AnyJSONTool]` |
| 290 | func | public | ToolBuilder.buildExpression(_:) | `public static func buildExpression(_ expression: any AnyJSONTool) -> [any AnyJSONTool]` |
| 295 | func | public | ToolBuilder.buildExpression(_:) | `public static func buildExpression<T>(_ expression: T) -> [any AnyJSONTool] where T : Tool` |
| 300 | func | public | ToolBuilder.buildExpression(_:) | `public static func buildExpression(_ expression: [any AnyJSONTool]) -> [any AnyJSONTool]` |
| 305 | func | public | ToolBuilder.buildExpression(_:) | `public static func buildExpression(_ expression: FoundationModelsNativeTool) -> ToolCollection` _(Availability: macOS 26.0+, iOS 26.0+, visionOS 26.0+; Requires FoundationModels)_ |
| 315 | func | public | ToolBuilder.buildExpression(_:) | `public static func buildExpression<T>(_ expression: T) -> ToolCollection where T : FoundationModels.Tool` _(Availability: macOS 26.0+, iOS 26.0+, visionOS 26.0+; Requires FoundationModels)_ |
| 305 | func | public | ToolBuilder.buildLimitedAvailability(_:) | `public static func buildLimitedAvailability(_ component: [any AnyJSONTool]) -> [any AnyJSONTool]` |
| 312 | typealias | public | ToolArrayBuilder | `public typealias ToolArrayBuilder = ToolBuilder` _(Availability: * (deprecated); renamed to ToolBuilder)_ |

### Tools/ToolSchema.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | struct | public | ToolSchema | `public struct ToolSchema` |
| 12 | var | public | ToolSchema.name | `public let name: String` |
| 13 | var | public | ToolSchema.description | `public let description: String` |
| 14 | var | public | ToolSchema.parameters | `public let parameters: [ToolParameter]` |
| 16 | func | public | ToolSchema.init(name:description:parameters:) | `public init(name: String, description: String, parameters: [ToolParameter])` |

### Tools/TypedToolProtocol.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 15 | protocol | public | Tool | `public protocol Tool : Sendable` |
| 16 | associatedtype | public | Tool.Input | `public associatedtype Input : Decodable, Encodable, Sendable` |
| 17 | associatedtype | public | Tool.Output | `public associatedtype Output : Encodable, Sendable` |
| 20 | var | public | Tool.name | `public var name: String { get }` |
| 23 | var | public | Tool.description | `public var description: String { get }` |
| 26 | var | public | Tool.parameters | `public var parameters: [ToolParameter] { get }` |
| 29 | var | public | Tool.inputGuardrails | `public var inputGuardrails: [any ToolInputGuardrail] { get }` |
| 32 | var | public | Tool.outputGuardrails | `public var outputGuardrails: [any ToolOutputGuardrail] { get }` |
| 35 | func | public | Tool.execute(_:) | `public func execute(_ input: Self.Input) async throws -> Self.Output` |
| 39 | var | public | Tool.inputGuardrails | `public var inputGuardrails: [any ToolInputGuardrail] { get }` |
| 40 | var | public | Tool.outputGuardrails | `public var outputGuardrails: [any ToolOutputGuardrail] { get }` |
| 42 | var | public | Tool.schema | `public var schema: ToolSchema { get }` |

### Tools/WebSearchTool.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 21 | var | public | WebSearchTool.description | `public let description: String` |
| 21 | func | public | WebSearchTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 21 | var | public | WebSearchTool.name | `public let name: String` |
| 21 | var | public | WebSearchTool.parameters | `public let parameters: [ToolParameter]` |
| 22 | struct | public | WebSearchTool | `public struct WebSearchTool` |
| 57 | func | public | WebSearchTool.init(apiKey:) | `public init(apiKey: String)` |
| 68 | func | public | WebSearchTool.execute() | `public func execute() async throws -> String` |

### Tools/ZoniSearchTool.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 15 | var | public | ZoniSearchTool.description | `public let description: String` |
| 15 | func | public | ZoniSearchTool.execute(arguments:) | `public func execute(arguments: [String : SendableValue]) async throws -> SendableValue` |
| 15 | var | public | ZoniSearchTool.name | `public let name: String` |
| 15 | var | public | ZoniSearchTool.parameters | `public let parameters: [ToolParameter]` |
| 16 | struct | public | ZoniSearchTool | `public struct ZoniSearchTool` |
| 17 | enum | public | ZoniSearchTool.Error | `public enum Error` |
| 18 | case | public | ZoniSearchTool.Error.pipelineNotConfigured | `public case pipelineNotConfigured` |
| 20 | var | public | ZoniSearchTool.Error.errorDescription | `public var errorDescription: String? { get }` |
| 38 | func | public | ZoniSearchTool.init() | `public init()` |
| 47 | func | public | ZoniSearchTool.execute() | `public func execute() async throws -> String` |

## 5. Memory

### Memory/AgentMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 101 | protocol | public | Memory | `public protocol Memory : Actor` |
| 110 | var | public | Memory.count | `public var count: Int { get async }` |
| 120 | var | public | Memory.isEmpty | `public var isEmpty: Bool { get async }` |
| 132 | func | public | Memory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 158 | func | public | Memory.context(for:tokenLimit:) | `public func context(for query: String, tokenLimit: Int) async -> String` |
| 169 | func | public | Memory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 176 | func | public | Memory.clear() | `public func clear() async` |
| 188 | func | public | Memory.beginMemorySession() | `public func beginMemorySession() async` |
| 196 | func | public | Memory.endMemorySession() | `public func endMemorySession() async` |
| 205 | func | public | Memory.context(for:) | `public func context(for query: MemoryQuery) async -> String` |
| 212 | func | public | Memory.importSessionHistory(_:) | `public func importSessionHistory(_ messages: [MemoryMessage]) async` |
| 219 | func | public | Memory.shouldImportSessionHistory() | `public func shouldImportSessionHistory() async -> Bool` |
| 226 | var | public | Memory.trackedSessionMemory | `public nonisolated var trackedSessionMemory: (any Memory)? { get }` |
| 231 | var | public | Memory.allowsAutomaticSessionSeeding | `public nonisolated var allowsAutomaticSessionSeeding: Bool { get }` |
| 238 | var | public | Memory.memoryPromptMetadata | `public nonisolated var memoryPromptMetadata: MemoryPromptMetadata? { get }` |
| 274 | func | public | MemoryMessage.formatContext(_:tokenLimit:tokenEstimator:) | `public static func formatContext(_ messages: [MemoryMessage], tokenLimit: Int, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared) -> String` |
| 318 | func | public | MemoryMessage.formatContext(_:tokenLimit:separator:tokenEstimator:) | `public static func formatContext(_ messages: [MemoryMessage], tokenLimit: Int, separator: String, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared) -> String` |
### Memory/Backends/InMemoryBackend.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 26 | class | public | InMemoryBackend | `public actor InMemoryBackend` |
| 30 | var | public | InMemoryBackend.totalMessageCount | `public var totalMessageCount: Int { get }` |
| 35 | var | public | InMemoryBackend.conversationCount | `public var conversationCount: Int { get }` |
| 40 | func | public | InMemoryBackend.init() | `public init()` |
| 44 | func | public | InMemoryBackend.store(_:conversationId:) | `public func store(_ message: MemoryMessage, conversationId: String) async throws` |
| 49 | func | public | InMemoryBackend.fetchMessages(conversationId:) | `public func fetchMessages(conversationId: String) async throws -> [MemoryMessage]` |
| 54 | func | public | InMemoryBackend.fetchRecentMessages(conversationId:limit:) | `public func fetchRecentMessages(conversationId: String, limit: Int) async throws -> [MemoryMessage]` |
| 60 | func | public | InMemoryBackend.deleteMessages(conversationId:) | `public func deleteMessages(conversationId: String) async throws` |
| 64 | func | public | InMemoryBackend.messageCount(conversationId:) | `public func messageCount(conversationId: String) async throws -> Int` |
| 68 | func | public | InMemoryBackend.allConversationIds() | `public func allConversationIds() async throws -> [String]` |
| 72 | func | public | InMemoryBackend.storeAll(_:conversationId:) | `public func storeAll(_ messages: [MemoryMessage], conversationId: String) async throws` |
| 78 | func | public | InMemoryBackend.deleteOldestMessages(conversationId:keepRecent:) | `public func deleteOldestMessages(conversationId: String, keepRecent: Int) async throws` |
| 85 | func | public | InMemoryBackend.deleteLastMessage(conversationId:) | `public func deleteLastMessage(conversationId: String) async throws -> MemoryMessage?` |
| 100 | func | public | InMemoryBackend.clearAll() | `public func clearAll() async` |

### Memory/Backends/SwiftDataBackend.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 24 | class | public | SwiftDataBackend | `public actor SwiftDataBackend` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 30 | func | public | SwiftDataBackend.init(modelContainer:) | `public init(modelContainer: ModelContainer)` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 40 | func | public | SwiftDataBackend.inMemory() | `public static func inMemory() throws -> SwiftDataBackend` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 48 | func | public | SwiftDataBackend.persistent() | `public static func persistent() throws -> SwiftDataBackend` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 55 | func | public | SwiftDataBackend.store(_:conversationId:) | `public func store(_ message: MemoryMessage, conversationId: String) async throws` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 62 | func | public | SwiftDataBackend.fetchMessages(conversationId:) | `public func fetchMessages(conversationId: String) async throws -> [MemoryMessage]` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 68 | func | public | SwiftDataBackend.fetchRecentMessages(conversationId:limit:) | `public func fetchRecentMessages(conversationId: String, limit: Int) async throws -> [MemoryMessage]` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 78 | func | public | SwiftDataBackend.deleteMessages(conversationId:) | `public func deleteMessages(conversationId: String) async throws` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 88 | func | public | SwiftDataBackend.messageCount(conversationId:) | `public func messageCount(conversationId: String) async throws -> Int` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 93 | func | public | SwiftDataBackend.allConversationIds() | `public func allConversationIds() async throws -> [String]` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 99 | func | public | SwiftDataBackend.storeAll(_:conversationId:) | `public func storeAll(_ messages: [MemoryMessage], conversationId: String) async throws` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 131 | func | public | SwiftDataBackend.deleteOldestMessages(conversationId:keepRecent:) | `public func deleteOldestMessages(conversationId: String, keepRecent: Int) async throws` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 152 | func | public | SwiftDataBackend.deleteLastMessage(conversationId:) | `public func deleteLastMessage(conversationId: String) async throws -> MemoryMessage?` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |

### Memory/ConversationMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 29 | class | public | ConversationMemory | `public actor ConversationMemory` |
| 33 | var | public | ConversationMemory.maxMessages | `public let maxMessages: Int` |
| 35 | var | public | ConversationMemory.count | `public var count: Int { get }` |
| 40 | var | public | ConversationMemory.isEmpty | `public var isEmpty: Bool { get }` |
| 47 | func | public | ConversationMemory.init(maxMessages:tokenEstimator:) | `public init(maxMessages: Int = 100, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 57 | func | public | ConversationMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 66 | func | public | ConversationMemory.context(for:tokenLimit:) | `public func context(for _: String, tokenLimit: Int) async -> String` |
| 70 | func | public | ConversationMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 74 | func | public | ConversationMemory.clear() | `public func clear() async` |
| 96 | func | public | ConversationMemory.addAll(_:) | `public func addAll(_ newMessages: [MemoryMessage]) async` |
| 108 | func | public | ConversationMemory.getRecentMessages(_:) | `public func getRecentMessages(_ n: Int) async -> [MemoryMessage]` |
| 116 | func | public | ConversationMemory.getOldestMessages(_:) | `public func getOldestMessages(_ n: Int) async -> [MemoryMessage]` |
| 125 | var | public | ConversationMemory.lastMessage | `public var lastMessage: MemoryMessage? { get }` |
| 130 | var | public | ConversationMemory.firstMessage | `public var firstMessage: MemoryMessage? { get }` |
| 138 | func | public | ConversationMemory.filter(_:) | `public func filter(_ predicate: (MemoryMessage) -> Bool) async -> [MemoryMessage]` |
| 146 | func | public | ConversationMemory.messages(withRole:) | `public func messages(withRole role: MemoryMessage.Role) async -> [MemoryMessage]` |
| 155 | func | public | ConversationMemory.diagnostics() | `public func diagnostics() async -> ConversationMemoryDiagnostics` |
| 169 | struct | public | ConversationMemoryDiagnostics | `public struct ConversationMemoryDiagnostics` |
| 171 | var | public | ConversationMemoryDiagnostics.messageCount | `public let messageCount: Int` |
| 173 | var | public | ConversationMemoryDiagnostics.maxMessages | `public let maxMessages: Int` |
| 175 | var | public | ConversationMemoryDiagnostics.utilizationPercent | `public let utilizationPercent: Double` |
| 177 | var | public | ConversationMemoryDiagnostics.oldestTimestamp | `public let oldestTimestamp: Date?` |
| 179 | var | public | ConversationMemoryDiagnostics.newestTimestamp | `public let newestTimestamp: Date?` |

### Memory/EmbeddingProvider.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 35 | protocol | public | EmbeddingProvider | `public protocol EmbeddingProvider : Sendable` |
| 40 | var | public | EmbeddingProvider.dimensions | `public var dimensions: Int { get }` |
| 43 | var | public | EmbeddingProvider.modelIdentifier | `public var modelIdentifier: String { get }` |
| 50 | func | public | EmbeddingProvider.embed(_:) | `public func embed(_ text: String) async throws -> [Float]` |
| 60 | func | public | EmbeddingProvider.embed(_:) | `public func embed(_ texts: [String]) async throws -> [[Float]]` |
| 67 | var | public | EmbeddingProvider.modelIdentifier | `public var modelIdentifier: String { get }` |
| 72 | func | public | EmbeddingProvider.embed(_:) | `public func embed(_ texts: [String]) async throws -> [[Float]]` |
| 89 | enum | public | EmbeddingError | `public enum EmbeddingError` |
| 92 | var | public | EmbeddingError.description | `public var description: String { get }` |
| 117 | case | public | EmbeddingError.modelUnavailable(reason:) | `public case modelUnavailable(reason: String)` |
| 120 | case | public | EmbeddingError.dimensionMismatch(expected:got:) | `public case dimensionMismatch(expected: Int, got: Int)` |
| 123 | case | public | EmbeddingError.emptyInput | `public case emptyInput` |
| 126 | case | public | EmbeddingError.batchTooLarge(size:limit:) | `public case batchTooLarge(size: Int, limit: Int)` |
| 129 | case | public | EmbeddingError.networkError(underlying:) | `public case networkError(underlying: any Error)` |
| 132 | case | public | EmbeddingError.rateLimitExceeded(retryAfter:) | `public case rateLimitExceeded(retryAfter: TimeInterval?)` |
| 135 | case | public | EmbeddingError.authenticationFailed | `public case authenticationFailed` |
| 138 | case | public | EmbeddingError.embeddingFailed(reason:) | `public case embeddingFailed(reason: String)` |
| 144 | enum | public | EmbeddingUtils | `public enum EmbeddingUtils` |
| 151 | func | public | EmbeddingUtils.cosineSimilarity(_:_:) | `public static func cosineSimilarity(_ vec1: [Float], _ vec2: [Float]) -> Float` |
| 174 | func | public | EmbeddingUtils.euclideanDistance(_:_:) | `public static func euclideanDistance(_ embedding1: [Float], _ embedding2: [Float]) -> Float` |
| 190 | func | public | EmbeddingUtils.normalize(_:) | `public static func normalize(_ vector: [Float]) -> [Float]` |

### Memory/ContextCoreEmbeddingAdapter.swift (Integrations)

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| — | struct | public | ContextCoreEmbeddingAdapter | Bridges Swarm `EmbeddingProvider` into ContextCore |
| — | enum | public | SemanticEmbeddingAvailability | `ensureModelAvailable()`, `isAvailable`, `reprobe()` |
| — | struct | public | EmbeddingModelDeliveryConfiguration | Download URL, pinned SHA-256, cache directory |
| — | enum | public | EmbeddingModelCatalog | Publishing-target URL + `expectedSHA256` |
| — | var | public | ContextCoreMemoryConfiguration.downloadsEmbeddingModelAutomatically | Default `false`; failed auto-download does not block session start |
| — | var | public | ContextCoreMemoryConfiguration.embeddingModelDelivery | Delivery config used when auto-download is on |

### Memory/HybridMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 45 | class | public | HybridMemory | `public actor HybridMemory` |
| 49 | struct | public | HybridMemory.Configuration | `public struct Configuration` |
| 51 | var | public | HybridMemory.Configuration.default | `public static let `default`: HybridMemory.Configuration` |
| 54 | var | public | HybridMemory.Configuration.shortTermMaxMessages | `public let shortTermMaxMessages: Int` |
| 57 | var | public | HybridMemory.Configuration.longTermSummaryTokens | `public let longTermSummaryTokens: Int` |
| 60 | var | public | HybridMemory.Configuration.summaryTokenRatio | `public let summaryTokenRatio: Double` |
| 63 | var | public | HybridMemory.Configuration.summarizationThreshold | `public let summarizationThreshold: Int` |
| 72 | func | public | HybridMemory.Configuration.init(shortTermMaxMessages:longTermSummaryTokens:summaryTokenRatio:summarizationThreshold:) | `public init(shortTermMaxMessages: Int = 30, longTermSummaryTokens: Int = 1000, summaryTokenRatio: Double = 0.3, summarizationThreshold: Int = 60)` |
| 86 | var | public | HybridMemory.configuration | `public let configuration: HybridMemory.Configuration` |
| 88 | var | public | HybridMemory.count | `public var count: Int { get async }` |
| 95 | var | public | HybridMemory.isEmpty | `public var isEmpty: Bool { get async }` |
| 102 | var | public | HybridMemory.summary | `public var summary: String { get }` |
| 107 | var | public | HybridMemory.hasSummary | `public var hasSummary: Bool { get }` |
| 112 | var | public | HybridMemory.totalMessages | `public var totalMessages: Int { get }` |
| 122 | func | public | HybridMemory.init(configuration:summarizer:tokenEstimator:) | `public init(configuration: HybridMemory.Configuration = .default, summarizer: any Summarizer = TruncatingSummarizer.shared, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 138 | func | public | HybridMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 149 | func | public | HybridMemory.context(for:tokenLimit:) | `public func context(for query: String, tokenLimit: Int) async -> String` |
| 183 | func | public | HybridMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 187 | func | public | HybridMemory.clear() | `public func clear() async` |
| 311 | func | public | HybridMemory.forceSummarize() | `public func forceSummarize() async` |
| 319 | func | public | HybridMemory.setSummary(_:) | `public func setSummary(_ newSummary: String) async` |
| 324 | func | public | HybridMemory.clearSummary() | `public func clearSummary() async` |
| 334 | func | public | HybridMemory.diagnostics() | `public func diagnostics() async -> HybridMemoryDiagnostics` |
| 351 | struct | public | HybridMemoryDiagnostics | `public struct HybridMemoryDiagnostics` |
| 353 | var | public | HybridMemoryDiagnostics.shortTermMessageCount | `public let shortTermMessageCount: Int` |
| 355 | var | public | HybridMemoryDiagnostics.shortTermMaxMessages | `public let shortTermMaxMessages: Int` |
| 357 | var | public | HybridMemoryDiagnostics.pendingMessages | `public let pendingMessages: Int` |
| 359 | var | public | HybridMemoryDiagnostics.totalMessagesProcessed | `public let totalMessagesProcessed: Int` |
| 361 | var | public | HybridMemoryDiagnostics.hasSummary | `public let hasSummary: Bool` |
| 363 | var | public | HybridMemoryDiagnostics.summaryTokenCount | `public let summaryTokenCount: Int` |
| 365 | var | public | HybridMemoryDiagnostics.summarizationCount | `public let summarizationCount: Int` |
| 367 | var | public | HybridMemoryDiagnostics.nextSummarizationIn | `public let nextSummarizationIn: Int` |

### Memory/InMemorySession.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 40 | class | public | InMemorySession | `public actor InMemorySession` |
| 44 | var | public | InMemorySession.sessionId | `public nonisolated let sessionId: String` |
| 49 | var | public | InMemorySession.itemCount | `public var itemCount: Int { get }` |
| 54 | var | public | InMemorySession.isEmpty | `public var isEmpty: Bool { get }` |
| 64 | func | public | InMemorySession.init(sessionId:) | `public init(sessionId: String = UUID().uuidString)` |
| 74 | func | public | InMemorySession.getItemCount() | `public func getItemCount() async throws -> Int` |
| 91 | func | public | InMemorySession.getItems(limit:) | `public func getItems(limit: Int?) async throws -> [MemoryMessage]` |
| 111 | func | public | InMemorySession.addItems(_:) | `public func addItems(_ newItems: [MemoryMessage]) async throws` |
| 120 | func | public | InMemorySession.popItem() | `public func popItem() async throws -> MemoryMessage?` |
| 131 | func | public | InMemorySession.clearSession() | `public func clearSession() async throws` |

### Memory/InferenceProviderSummarizer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 37 | class | public | InferenceProviderSummarizer | `public actor InferenceProviderSummarizer` |
| 40 | var | public | InferenceProviderSummarizer.isAvailable | `public var isAvailable: Bool { get async }` |
| 50 | func | public | InferenceProviderSummarizer.init(provider:systemPrompt:temperature:) | `public init(provider: any InferenceProvider, systemPrompt: String = "Summarize the following conversation concisely, preserving key information and context:", temperature: Double = 0.3)` |
| 62 | func | public | InferenceProviderSummarizer.summarize(_:maxTokens:) | `public func summarize(_ text: String, maxTokens: Int) async throws -> String` |
| 115 | func | public | InferenceProviderSummarizer.conversationSummarizer(provider:) | `public static func conversationSummarizer(provider: any InferenceProvider) -> InferenceProviderSummarizer` |
| 137 | func | public | InferenceProviderSummarizer.reasoningSummarizer(provider:) | `public static func reasoningSummarizer(provider: any InferenceProvider) -> InferenceProviderSummarizer` |

### Memory/MemoryMessage.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 14 | struct | public | MemoryMessage | `public struct MemoryMessage` |
| 16 | enum | public | MemoryMessage.Role | `public enum Role` |
| 18 | case | public | MemoryMessage.Role.user | `public case user` |
| 20 | case | public | MemoryMessage.Role.assistant | `public case assistant` |
| 22 | case | public | MemoryMessage.Role.system | `public case system` |
| 24 | case | public | MemoryMessage.Role.tool | `public case tool` |
| 28 | var | public | MemoryMessage.id | `public let id: UUID` |
| 31 | var | public | MemoryMessage.role | `public let role: MemoryMessage.Role` |
| 34 | var | public | MemoryMessage.content | `public let content: String` |
| 37 | var | public | MemoryMessage.timestamp | `public let timestamp: Date` |
| 40 | var | public | MemoryMessage.metadata | `public let metadata: [String : String]` |
| 43 | var | public | MemoryMessage.formattedContent | `public var formattedContent: String { get }` |
| 55 | func | public | MemoryMessage.init(id:role:content:timestamp:metadata:) | `public init(id: UUID = UUID(), role: MemoryMessage.Role, content: String, timestamp: Date = Date(), metadata: [String : String] = [:])` |
| 79 | func | public | MemoryMessage.user(_:metadata:) | `public static func user(_ content: String, metadata: [String : String] = [:]) -> MemoryMessage` |
| 89 | func | public | MemoryMessage.assistant(_:metadata:) | `public static func assistant(_ content: String, metadata: [String : String] = [:]) -> MemoryMessage` |
| 99 | func | public | MemoryMessage.system(_:metadata:) | `public static func system(_ content: String, metadata: [String : String] = [:]) -> MemoryMessage` |
| 109 | func | public | MemoryMessage.tool(_:toolName:) | `public static func tool(_ content: String, toolName: String) -> MemoryMessage` |
| 117 | var | public | MemoryMessage.description | `public var description: String { get }` |

### Memory/MemoryPromptDescriptor.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | enum | public | MemoryPriorityHint | `public enum MemoryPriorityHint` |
| 10 | case | public | MemoryPriorityHint.primary | `public case primary` |
| 11 | case | public | MemoryPriorityHint.secondary | `public case secondary` |
| 19 | struct | public | MemoryPromptMetadata | `public struct MemoryPromptMetadata: Sendable` |
| 21 | var | public | MemoryPromptMetadata.title | `public var title: String` |
| 24 | var | public | MemoryPromptMetadata.guidance | `public var guidance: String?` |
| 27 | var | public | MemoryPromptMetadata.priority | `public var priority: MemoryPriorityHint` |
| 29 | init | public | MemoryPromptMetadata.init(title:guidance:priority:) | `public init(title: String, guidance: String?, priority: MemoryPriorityHint)` |
| 47 | protocol | public | MemoryPromptDescriptor | `public protocol MemoryPromptDescriptor : Sendable` |
| 49 | var | public | MemoryPromptDescriptor.memoryPromptTitle | `public var memoryPromptTitle: String { get }` |
| 52 | var | public | MemoryPromptDescriptor.memoryPromptGuidance | `public var memoryPromptGuidance: String? { get }` |
| 55 | var | public | MemoryPromptDescriptor.memoryPriority | `public var memoryPriority: MemoryPriorityHint { get }` |

### Memory/MemorySessionLifecycle.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | protocol | public | MemorySessionLifecycle | `public protocol MemorySessionLifecycle : Memory` |
| 11 | func | public | MemorySessionLifecycle.beginMemorySession() | `public func beginMemorySession() async` |
| 14 | func | public | MemorySessionLifecycle.endMemorySession() | `public func endMemorySession() async` |
| 24 | protocol | public | MemorySessionReplayAware | `public protocol MemorySessionReplayAware : Memory` |
| 26 | func | public | MemorySessionReplayAware.importSessionHistory(_:) | `public func importSessionHistory(_ messages: [MemoryMessage]) async` |

### Memory/PersistentMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 32 | class | public | PersistentMemory | `public actor PersistentMemory` |
| 36 | var | public | PersistentMemory.conversationId | `public let conversationId: String` |
| 39 | var | public | PersistentMemory.maxMessages | `public let maxMessages: Int` |
| 42 | var | public | PersistentMemory.tokenEstimator | `public let tokenEstimator: any TokenEstimator` |
| 44 | var | public | PersistentMemory.count | `public var count: Int { get async }` |
| 54 | var | public | PersistentMemory.isEmpty | `public var isEmpty: Bool { get async }` |
| 72 | func | public | PersistentMemory.init(backend:conversationId:maxMessages:tokenEstimator:) | `public init(backend: any PersistentMemoryBackend, conversationId: String = UUID().uuidString, maxMessages: Int = 0, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 86 | func | public | PersistentMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 98 | func | public | PersistentMemory.context(for:tokenLimit:) | `public func context(for _: String, tokenLimit: Int) async -> String` |
| 107 | func | public | PersistentMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 116 | func | public | PersistentMemory.clear() | `public func clear() async` |
| 130 | func | public | PersistentMemory.getRecentMessages(limit:) | `public func getRecentMessages(limit: Int) async -> [MemoryMessage]` |
| 145 | func | public | PersistentMemory.addAll(_:) | `public func addAll(_ messages: [MemoryMessage]) async` |

### Memory/PersistentMemoryBackend.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 40 | protocol | public | PersistentMemoryBackend | `public protocol PersistentMemoryBackend : Actor` |
| 46 | func | public | PersistentMemoryBackend.store(_:conversationId:) | `public func store(_ message: MemoryMessage, conversationId: String) async throws` |
| 52 | func | public | PersistentMemoryBackend.fetchMessages(conversationId:) | `public func fetchMessages(conversationId: String) async throws -> [MemoryMessage]` |
| 60 | func | public | PersistentMemoryBackend.fetchRecentMessages(conversationId:limit:) | `public func fetchRecentMessages(conversationId: String, limit: Int) async throws -> [MemoryMessage]` |
| 65 | func | public | PersistentMemoryBackend.deleteMessages(conversationId:) | `public func deleteMessages(conversationId: String) async throws` |
| 71 | func | public | PersistentMemoryBackend.messageCount(conversationId:) | `public func messageCount(conversationId: String) async throws -> Int` |
| 76 | func | public | PersistentMemoryBackend.allConversationIds() | `public func allConversationIds() async throws -> [String]` |
| 86 | func | public | PersistentMemoryBackend.storeAll(_:conversationId:) | `public func storeAll(_ messages: [MemoryMessage], conversationId: String) async throws` |
| 96 | func | public | PersistentMemoryBackend.deleteOldestMessages(conversationId:keepRecent:) | `public func deleteOldestMessages(conversationId: String, keepRecent: Int) async throws` |
| 108 | func | public | PersistentMemoryBackend.deleteLastMessage(conversationId:) | `public func deleteLastMessage(conversationId: String) async throws -> MemoryMessage?` |
| 114 | func | public | PersistentMemoryBackend.storeAll(_:conversationId:) | `public func storeAll(_ messages: [MemoryMessage], conversationId: String) async throws` |
| 120 | func | public | PersistentMemoryBackend.deleteOldestMessages(conversationId:keepRecent:) | `public func deleteOldestMessages(conversationId: String, keepRecent: Int) async throws` |
| 130 | func | public | PersistentMemoryBackend.deleteLastMessage(conversationId:) | `public func deleteLastMessage(conversationId: String) async throws -> MemoryMessage?` |
| 151 | enum | public | PersistentMemoryError | `public enum PersistentMemoryError` |
| 154 | var | public | PersistentMemoryError.description | `public var description: String { get }` |
| 171 | case | public | PersistentMemoryError.storeFailed(_:) | `public case storeFailed(String)` |
| 172 | case | public | PersistentMemoryError.fetchFailed(_:) | `public case fetchFailed(String)` |
| 173 | case | public | PersistentMemoryError.deleteFailed(_:) | `public case deleteFailed(String)` |
| 174 | case | public | PersistentMemoryError.connectionFailed(_:) | `public case connectionFailed(String)` |
| 175 | case | public | PersistentMemoryError.notConfigured | `public case notConfigured` |
| 176 | case | public | PersistentMemoryError.invalidConversationId | `public case invalidConversationId` |

### Memory/PersistentSession.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 55 | class | public | PersistentSession | `public actor PersistentSession` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 62 | var | public | PersistentSession.sessionId | `public nonisolated let sessionId: String` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 79 | var | public | PersistentSession.itemCount | `public var itemCount: Int { get async }` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 94 | var | public | PersistentSession.isEmpty | `public var isEmpty: Bool { get async }` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 110 | func | public | PersistentSession.init(sessionId:backend:) | `public init(sessionId: String, backend: SwiftDataBackend)` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 125 | func | public | PersistentSession.persistent(sessionId:) | `public static func persistent(sessionId: String) throws -> PersistentSession` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 138 | func | public | PersistentSession.inMemory(sessionId:) | `public static func inMemory(sessionId: String) throws -> PersistentSession` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 150 | func | public | PersistentSession.getItemCount() | `public func getItemCount() async throws -> Int` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 175 | func | public | PersistentSession.getItems(limit:) | `public func getItems(limit: Int?) async throws -> [MemoryMessage]` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 197 | func | public | PersistentSession.addItems(_:) | `public func addItems(_ items: [MemoryMessage]) async throws` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 211 | func | public | PersistentSession.popItem() | `public func popItem() async throws -> MemoryMessage?` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |
| 221 | func | public | PersistentSession.clearSession() | `public func clearSession() async throws` _(Availability: macOS 14.0+, watchOS 10.0+, iOS 17.0+, tvOS 17.0+)_ |

### Memory/Session.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 31 | protocol | public | Session | `public protocol Session : Actor` |
| 39 | var | public | Session.sessionId | `public nonisolated var sessionId: String { get }` |
| 45 | var | public | Session.itemCount | `public var itemCount: Int { get async }` |
| 50 | var | public | Session.isEmpty | `public var isEmpty: Bool { get async }` |
| 59 | func | public | Session.getItemCount() | `public func getItemCount() async throws -> Int` |
| 73 | func | public | Session.getItems(limit:) | `public func getItems(limit: Int?) async throws -> [MemoryMessage]` |
| 82 | func | public | Session.addItems(_:) | `public func addItems(_ items: [MemoryMessage]) async throws` |
| 91 | func | public | Session.popItem() | `public func popItem() async throws -> MemoryMessage?` |
| 99 | func | public | Session.clearSession() | `public func clearSession() async throws` |
| 105 | enum | public | SessionError | `public enum SessionError` |
| 110 | case | public | SessionError.retrievalFailed(reason:underlyingError:) | `public case retrievalFailed(reason: String, underlyingError: String? = nil)` |
| 113 | case | public | SessionError.storageFailed(reason:underlyingError:) | `public case storageFailed(reason: String, underlyingError: String? = nil)` |
| 116 | case | public | SessionError.deletionFailed(reason:underlyingError:) | `public case deletionFailed(reason: String, underlyingError: String? = nil)` |
| 119 | case | public | SessionError.invalidState(reason:) | `public case invalidState(reason: String)` |
| 122 | case | public | SessionError.backendError(reason:underlyingError:) | `public case backendError(reason: String, underlyingError: String? = nil)` |
| 128 | func | public | SessionError.==(_:_:) | `public static func == (lhs: SessionError, rhs: SessionError) -> Bool` |
| 149 | var | public | SessionError.errorDescription | `public var errorDescription: String? { get }` |
| 191 | func | public | Session.addItem(_:) | `public func addItem(_ item: MemoryMessage) async throws` |
| 201 | func | public | Session.getAllItems() | `public func getAllItems() async throws -> [MemoryMessage]` |
| 208 | func | public | Session.getItemCount() | `public func getItemCount() async throws -> Int` |

### Memory/SlidingWindowMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 29 | class | public | SlidingWindowMemory | `public actor SlidingWindowMemory` |
| 33 | var | public | SlidingWindowMemory.maxTokens | `public let maxTokens: Int` |
| 35 | var | public | SlidingWindowMemory.count | `public var count: Int { get }` |
| 40 | var | public | SlidingWindowMemory.isEmpty | `public var isEmpty: Bool { get }` |
| 45 | var | public | SlidingWindowMemory.tokenCount | `public var tokenCount: Int { get }` |
| 50 | var | public | SlidingWindowMemory.remainingTokens | `public var remainingTokens: Int { get }` |
| 55 | var | public | SlidingWindowMemory.isNearCapacity | `public var isNearCapacity: Bool { get }` |
| 64 | func | public | SlidingWindowMemory.init(maxTokens:tokenEstimator:) | `public init(maxTokens: Int = 4000, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 74 | func | public | SlidingWindowMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 95 | func | public | SlidingWindowMemory.context(for:tokenLimit:) | `public func context(for _: String, tokenLimit: Int) async -> String` |
| 100 | func | public | SlidingWindowMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 104 | func | public | SlidingWindowMemory.clear() | `public func clear() async` |
| 143 | func | public | SlidingWindowMemory.addAll(_:) | `public func addAll(_ newMessages: [MemoryMessage]) async` |
| 153 | func | public | SlidingWindowMemory.getMessages(withinTokenBudget:) | `public func getMessages(withinTokenBudget tokenBudget: Int) async -> [MemoryMessage]` |
| 175 | func | public | SlidingWindowMemory.diagnostics() | `public func diagnostics() async -> SlidingWindowDiagnostics` |
| 190 | struct | public | SlidingWindowDiagnostics | `public struct SlidingWindowDiagnostics` |
| 192 | var | public | SlidingWindowDiagnostics.messageCount | `public let messageCount: Int` |
| 194 | var | public | SlidingWindowDiagnostics.currentTokens | `public let currentTokens: Int` |
| 196 | var | public | SlidingWindowDiagnostics.maxTokens | `public let maxTokens: Int` |
| 198 | var | public | SlidingWindowDiagnostics.utilizationPercent | `public let utilizationPercent: Double` |
| 200 | var | public | SlidingWindowDiagnostics.remainingTokens | `public let remainingTokens: Int` |
| 202 | var | public | SlidingWindowDiagnostics.averageTokensPerMessage | `public let averageTokensPerMessage: Double` |
| 212 | func | public | SlidingWindowMemory.recalculateTokenCount() | `public func recalculateTokenCount() async` |

### Memory/Summarizer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 14 | protocol | public | Summarizer | `public protocol Summarizer : Sendable` |
| 16 | var | public | Summarizer.isAvailable | `public var isAvailable: Bool { get async }` |
| 25 | func | public | Summarizer.summarize(_:maxTokens:) | `public func summarize(_ text: String, maxTokens: Int) async throws -> String` |
| 31 | enum | public | SummarizerError | `public enum SummarizerError` |
| 34 | var | public | SummarizerError.description | `public var description: String { get }` |
| 48 | case | public | SummarizerError.unavailable | `public case unavailable` |
| 50 | case | public | SummarizerError.summarizationFailed(underlying:) | `public case summarizationFailed(underlying: any Error)` |
| 52 | case | public | SummarizerError.inputTooShort | `public case inputTooShort` |
| 54 | case | public | SummarizerError.timeout | `public case timeout` |
| 70 | struct | public | TruncatingSummarizer | `public struct TruncatingSummarizer` |
| 74 | var | public | TruncatingSummarizer.shared | `public static let shared: TruncatingSummarizer` |
| 76 | var | public | TruncatingSummarizer.isAvailable | `public var isAvailable: Bool { get async }` |
| 83 | func | public | TruncatingSummarizer.init(tokenEstimator:) | `public init(tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 87 | func | public | TruncatingSummarizer.summarize(_:maxTokens:) | `public func summarize(_ text: String, maxTokens: Int) async throws -> String` |
| 138 | class | public | FoundationModelsSummarizer | `public actor FoundationModelsSummarizer` _(Availability: macOS 26.0+, watchOS 26.0+, iOS 26.0+, visionOS 26.0+, tvOS 26.0+; Requires FoundationModels (`#if canImport(FoundationModels)`))_ |
| 141 | var | public | FoundationModelsSummarizer.isAvailable | `public var isAvailable: Bool { get async }` _(Availability: macOS 26.0+, watchOS 26.0+, iOS 26.0+, visionOS 26.0+, tvOS 26.0+; Requires FoundationModels (`#if canImport(FoundationModels)`))_ |
| 150 | func | public | FoundationModelsSummarizer.init() | `public init()` _(Availability: macOS 26.0+, watchOS 26.0+, iOS 26.0+, visionOS 26.0+, tvOS 26.0+; Requires FoundationModels (`#if canImport(FoundationModels)`))_ |
| 152 | func | public | FoundationModelsSummarizer.summarize(_:maxTokens:) | `public func summarize(_ text: String, maxTokens _: Int) async throws -> String` _(Availability: macOS 26.0+, watchOS 26.0+, iOS 26.0+, visionOS 26.0+, tvOS 26.0+; Requires FoundationModels (`#if canImport(FoundationModels)`))_ |
| 185 | func | public | FoundationModelsSummarizer.resetSession() | `public func resetSession()` _(Availability: macOS 26.0+, watchOS 26.0+, iOS 26.0+, visionOS 26.0+, tvOS 26.0+; Requires FoundationModels (`#if canImport(FoundationModels)`))_ |
| 201 | struct | public | FallbackSummarizer | `public struct FallbackSummarizer` |
| 204 | var | public | FallbackSummarizer.isAvailable | `public var isAvailable: Bool { get async }` |
| 217 | func | public | FallbackSummarizer.init(primary:fallback:) | `public init(primary: any Summarizer, fallback: any Summarizer = TruncatingSummarizer.shared)` |
| 222 | func | public | FallbackSummarizer.summarize(_:maxTokens:) | `public func summarize(_ text: String, maxTokens: Int) async throws -> String` |

### Memory/SummaryMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 36 | class | public | SummaryMemory | `public actor SummaryMemory` |
| 40 | struct | public | SummaryMemory.Configuration | `public struct Configuration` |
| 42 | var | public | SummaryMemory.Configuration.default | `public static let `default`: SummaryMemory.Configuration` |
| 45 | var | public | SummaryMemory.Configuration.recentMessageCount | `public let recentMessageCount: Int` |
| 48 | var | public | SummaryMemory.Configuration.summarizationThreshold | `public let summarizationThreshold: Int` |
| 51 | var | public | SummaryMemory.Configuration.summaryTokenTarget | `public let summaryTokenTarget: Int` |
| 59 | func | public | SummaryMemory.Configuration.init(recentMessageCount:summarizationThreshold:summaryTokenTarget:) | `public init(recentMessageCount: Int = 20, summarizationThreshold: Int = 50, summaryTokenTarget: Int = 500)` |
| 72 | var | public | SummaryMemory.configuration | `public let configuration: SummaryMemory.Configuration` |
| 74 | var | public | SummaryMemory.count | `public var count: Int { get }` |
| 79 | var | public | SummaryMemory.isEmpty | `public var isEmpty: Bool { get }` |
| 84 | var | public | SummaryMemory.currentSummary | `public var currentSummary: String { get }` |
| 89 | var | public | SummaryMemory.hasSummary | `public var hasSummary: Bool { get }` |
| 94 | var | public | SummaryMemory.totalMessages | `public var totalMessages: Int { get }` |
| 105 | func | public | SummaryMemory.init(configuration:summarizer:fallbackSummarizer:tokenEstimator:) | `public init(configuration: SummaryMemory.Configuration = .default, summarizer: any Summarizer = TruncatingSummarizer.shared, fallbackSummarizer: any Summarizer = TruncatingSummarizer.shared, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 119 | func | public | SummaryMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 129 | func | public | SummaryMemory.context(for:tokenLimit:) | `public func context(for _: String, tokenLimit: Int) async -> String` |
| 158 | func | public | SummaryMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 162 | func | public | SummaryMemory.clear() | `public func clear() async` |
| 244 | func | public | SummaryMemory.forceSummarize() | `public func forceSummarize() async` |
| 252 | func | public | SummaryMemory.setSummary(_:) | `public func setSummary(_ newSummary: String) async` |
| 261 | func | public | SummaryMemory.diagnostics() | `public func diagnostics() async -> SummaryMemoryDiagnostics` |
| 276 | struct | public | SummaryMemoryDiagnostics | `public struct SummaryMemoryDiagnostics` |
| 278 | var | public | SummaryMemoryDiagnostics.recentMessageCount | `public let recentMessageCount: Int` |
| 280 | var | public | SummaryMemoryDiagnostics.totalMessagesProcessed | `public let totalMessagesProcessed: Int` |
| 282 | var | public | SummaryMemoryDiagnostics.hasSummary | `public let hasSummary: Bool` |
| 284 | var | public | SummaryMemoryDiagnostics.summaryTokenCount | `public let summaryTokenCount: Int` |
| 286 | var | public | SummaryMemoryDiagnostics.summarizationCount | `public let summarizationCount: Int` |
| 288 | var | public | SummaryMemoryDiagnostics.nextSummarizationIn | `public let nextSummarizationIn: Int` |

### Memory/SwiftDataMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 28 | class | public | SwiftDataMemory | `public actor SwiftDataMemory` |
| 32 | var | public | SwiftDataMemory.conversationId | `public let conversationId: String` |
| 35 | var | public | SwiftDataMemory.maxMessages | `public let maxMessages: Int` |
| 37 | var | public | SwiftDataMemory.count | `public var count: Int { get async }` |
| 51 | var | public | SwiftDataMemory.isEmpty | `public var isEmpty: Bool { get async }` |
| 71 | func | public | SwiftDataMemory.init(modelContainer:conversationId:maxMessages:tokenEstimator:) | `public init(modelContainer: ModelContainer, conversationId: String = "default", maxMessages: Int = 0, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 86 | func | public | SwiftDataMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 103 | func | public | SwiftDataMemory.context(for:tokenLimit:) | `public func context(for _: String, tokenLimit: Int) async -> String` |
| 108 | func | public | SwiftDataMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 120 | func | public | SwiftDataMemory.clear() | `public func clear() async` |
| 174 | func | public | SwiftDataMemory.addAll(_:) | `public func addAll(_ messages: [MemoryMessage]) async` |
| 195 | func | public | SwiftDataMemory.getRecentMessages(_:) | `public func getRecentMessages(_ n: Int) async -> [MemoryMessage]` |
| 215 | func | public | SwiftDataMemory.allConversationIds() | `public func allConversationIds() async -> [String]` |
| 229 | func | public | SwiftDataMemory.deleteConversation(_:) | `public func deleteConversation(_ id: String) async` |
| 247 | func | public | SwiftDataMemory.messageCount(forConversation:) | `public func messageCount(forConversation id: String) async -> Int` |
| 263 | func | public | SwiftDataMemory.diagnostics() | `public func diagnostics() async -> SwiftDataMemoryDiagnostics` |
| 278 | struct | public | SwiftDataMemoryDiagnostics | `public struct SwiftDataMemoryDiagnostics` |
| 280 | var | public | SwiftDataMemoryDiagnostics.conversationId | `public let conversationId: String` |
| 282 | var | public | SwiftDataMemoryDiagnostics.messageCount | `public let messageCount: Int` |
| 284 | var | public | SwiftDataMemoryDiagnostics.maxMessages | `public let maxMessages: Int` |
| 286 | var | public | SwiftDataMemoryDiagnostics.totalConversations | `public let totalConversations: Int` |
| 288 | var | public | SwiftDataMemoryDiagnostics.isUnlimited | `public let isUnlimited: Bool` |
| 303 | func | public | SwiftDataMemory.inMemory(conversationId:maxMessages:) | `public static func inMemory(conversationId: String = "default", maxMessages: Int = 0) throws -> SwiftDataMemory` |
| 322 | func | public | SwiftDataMemory.persistent(conversationId:maxMessages:) | `public static func persistent(conversationId: String = "default", maxMessages: Int = 0) throws -> SwiftDataMemory` |

### Memory/TokenEstimator.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 14 | protocol | public | TokenEstimator | `public protocol TokenEstimator : Sendable` |
| 19 | func | public | TokenEstimator.estimateTokens(for:) | `public func estimateTokens(for text: String) -> Int` |
| 25 | func | public | TokenEstimator.estimateTokens(for:) | `public func estimateTokens(for texts: [String]) -> Int` |
| 31 | func | public | TokenEstimator.estimateTokens(for:) | `public func estimateTokens(for texts: [String]) -> Int` |
| 50 | struct | public | CharacterBasedTokenEstimator | `public struct CharacterBasedTokenEstimator` |
| 52 | var | public | CharacterBasedTokenEstimator.shared | `public static let shared: CharacterBasedTokenEstimator` |
| 55 | var | public | CharacterBasedTokenEstimator.charactersPerToken | `public let charactersPerToken: Int` |
| 60 | func | public | CharacterBasedTokenEstimator.init(charactersPerToken:) | `public init(charactersPerToken: Int = 4)` |
| 64 | func | public | CharacterBasedTokenEstimator.estimateTokens(for:) | `public func estimateTokens(for text: String) -> Int` |
| 83 | struct | public | WordBasedTokenEstimator | `public struct WordBasedTokenEstimator` |
| 85 | var | public | WordBasedTokenEstimator.shared | `public static let shared: WordBasedTokenEstimator` |
| 88 | var | public | WordBasedTokenEstimator.tokensPerWord | `public let tokensPerWord: Double` |
| 93 | func | public | WordBasedTokenEstimator.init(tokensPerWord:) | `public init(tokensPerWord: Double = 1.3)` |
| 97 | func | public | WordBasedTokenEstimator.estimateTokens(for:) | `public func estimateTokens(for text: String) -> Int` |
| 108 | struct | public | AveragingTokenEstimator | `public struct AveragingTokenEstimator` |
| 112 | var | public | AveragingTokenEstimator.shared | `public static let shared: AveragingTokenEstimator` |
| 120 | func | public | AveragingTokenEstimator.init(estimators:) | `public init(estimators: [any TokenEstimator])` |
| 126 | func | public | AveragingTokenEstimator.estimateTokens(for:) | `public func estimateTokens(for text: String) -> Int` |

### Memory/VectorMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 55 | class | public | VectorMemory | `public actor VectorMemory` |
| 59 | struct | public | VectorMemory.SearchResult | `public struct SearchResult` |
| 61 | var | public | VectorMemory.SearchResult.message | `public let message: MemoryMessage` |
| 63 | var | public | VectorMemory.SearchResult.similarity | `public let similarity: Float` |
| 69 | var | public | VectorMemory.similarityThreshold | `public let similarityThreshold: Float` |
| 72 | var | public | VectorMemory.maxResults | `public let maxResults: Int` |
| 75 | var | public | VectorMemory.embeddingProvider | `public let embeddingProvider: any EmbeddingProvider` |
| 79 | var | public | VectorMemory.count | `public var count: Int { get }` |
| 83 | var | public | VectorMemory.isEmpty | `public var isEmpty: Bool { get }` |
| 96 | func | public | VectorMemory.init(embeddingProvider:similarityThreshold:maxResults:tokenEstimator:) | `public init(embeddingProvider: any EmbeddingProvider, similarityThreshold: Float = 0.7, maxResults: Int = 10, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared)` |
| 119 | func | public | VectorMemory.cosineSimilarity(_:_:) | `public static func cosineSimilarity(_ vec1: [Float], _ vec2: [Float]) -> Float` |
| 137 | func | public | VectorMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 158 | func | public | VectorMemory.context(for:tokenLimit:) | `public func context(for query: String, tokenLimit: Int) async -> String` |
| 183 | func | public | VectorMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 188 | func | public | VectorMemory.clear() | `public func clear() async` |
| 198 | func | public | VectorMemory.search(query:) | `public func search(query: String) async throws -> [VectorMemory.SearchResult]` |
| 211 | func | public | VectorMemory.search(queryEmbedding:) | `public func search(queryEmbedding: [Float]) -> [VectorMemory.SearchResult]` |
| 244 | func | public | VectorMemory.addAll(_:) | `public func addAll(_ newMessages: [MemoryMessage]) async` |
| 270 | func | public | VectorMemory.filter(_:) | `public func filter(_ predicate: (MemoryMessage) -> Bool) async -> [MemoryMessage]` |
| 278 | func | public | VectorMemory.messages(withRole:) | `public func messages(withRole role: MemoryMessage.Role) async -> [MemoryMessage]` |
| 360 | func | public | VectorMemory.diagnostics() | `public func diagnostics() async -> VectorMemoryDiagnostics` |
| 376 | struct | public | VectorMemoryDiagnostics | `public struct VectorMemoryDiagnostics` |
| 378 | var | public | VectorMemoryDiagnostics.messageCount | `public let messageCount: Int` |
| 380 | var | public | VectorMemoryDiagnostics.embeddingDimensions | `public let embeddingDimensions: Int` |
| 382 | var | public | VectorMemoryDiagnostics.similarityThreshold | `public let similarityThreshold: Float` |
| 384 | var | public | VectorMemoryDiagnostics.maxResults | `public let maxResults: Int` |
| 386 | var | public | VectorMemoryDiagnostics.modelIdentifier | `public let modelIdentifier: String` |
| 388 | var | public | VectorMemoryDiagnostics.oldestTimestamp | `public let oldestTimestamp: Date?` |
| 390 | var | public | VectorMemoryDiagnostics.newestTimestamp | `public let newestTimestamp: Date?` |
| 458 | enum | public | VectorMemoryError | `public enum VectorMemoryError` |
| 461 | var | public | VectorMemoryError.description | `public var description: String { get }` |
| 471 | case | public | VectorMemoryError.missingEmbeddingProvider | `public case missingEmbeddingProvider` |
| 474 | case | public | VectorMemoryError.searchFailed(underlying:) | `public case searchFailed(underlying: any Error)` |

## 6. Guardrails

### Guardrails/Guardrail.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 12 | protocol | public | Guardrail | `public protocol Guardrail : Sendable` |
| 14 | var | public | Guardrail.name | `public var name: String { get }` |

### Guardrails/GuardrailError.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | enum | public | GuardrailError | `public enum GuardrailError` |
| 14 | var | public | GuardrailError.errorDescription | `public var errorDescription: String? { get }` |
| 30 | case | public | GuardrailError.inputTripwireTriggered(guardrailName:message:outputInfo:) | `public case inputTripwireTriggered(guardrailName: String, message: String, outputInfo: SendableValue?)` |
| 37 | case | public | GuardrailError.outputTripwireTriggered(guardrailName:agentName:message:outputInfo:) | `public case outputTripwireTriggered(guardrailName: String, agentName: String, message: String, outputInfo: SendableValue?)` |
| 45 | case | public | GuardrailError.toolInputTripwireTriggered(guardrailName:toolName:message:outputInfo:) | `public case toolInputTripwireTriggered(guardrailName: String, toolName: String, message: String, outputInfo: SendableValue?)` |
| 53 | case | public | GuardrailError.toolOutputTripwireTriggered(guardrailName:toolName:message:outputInfo:) | `public case toolOutputTripwireTriggered(guardrailName: String, toolName: String, message: String, outputInfo: SendableValue?)` |
| 61 | case | public | GuardrailError.executionFailed(guardrailName:underlyingError:) | `public case executionFailed(guardrailName: String, underlyingError: String)` |
| 67 | var | public | GuardrailError.debugDescription | `public var debugDescription: String { get }` |

### Guardrails/GuardrailResult.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 45 | enum | public | GuardrailResult | `public enum GuardrailResult` |
| 52 | case | public | GuardrailResult.passed | `case passed(message: String? = nil, outputInfo: SendableValue? = nil, metadata: [String : SendableValue] = [:])` |
| 64 | case | public | GuardrailResult.tripwire | `case tripwire(message: String, outputInfo: SendableValue? = nil, metadata: [String : SendableValue] = [:])` |
| 71 | var | public | GuardrailResult.tripwireTriggered | `public var tripwireTriggered: Bool { get }` |
| 81 | var | public | GuardrailResult.outputInfo | `public var outputInfo: SendableValue? { get }` |
| 92 | var | public | GuardrailResult.message | `public var message: String? { get }` |
| 102 | var | public | GuardrailResult.metadata | `public var metadata: [String : SendableValue] { get }` |
| 116 | func | public | GuardrailResult.init(tripwireTriggered:outputInfo:message:metadata:) | `public init(tripwireTriggered: Bool, outputInfo: SendableValue? = nil, message: String? = nil, metadata: [String : SendableValue] = [:])` |
| 140 | var | public | GuardrailResult.debugDescription | `public var debugDescription: String { get }` |

### Guardrails/GuardrailRunner.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 33 | struct | public | GuardrailRunnerConfiguration | `public struct GuardrailRunnerConfiguration` |
| 37 | var | public | GuardrailRunnerConfiguration.default | `public static let `default`: GuardrailRunnerConfiguration` |
| 40 | var | public | GuardrailRunnerConfiguration.parallel | `public static let parallel: GuardrailRunnerConfiguration` |
| 45 | var | public | GuardrailRunnerConfiguration.runInParallel | `public let runInParallel: Bool` |
| 50 | var | public | GuardrailRunnerConfiguration.stopOnFirstTripwire | `public let stopOnFirstTripwire: Bool` |
| 69 | func | public | GuardrailRunnerConfiguration.init(runInParallel:stopOnFirstTripwire:) | `public init(runInParallel: Bool = false, stopOnFirstTripwire: Bool = true)` |
| 94 | struct | public | GuardrailExecutionResult | `public struct GuardrailExecutionResult` |
| 96 | var | public | GuardrailExecutionResult.guardrailName | `public let guardrailName: String` |
| 99 | var | public | GuardrailExecutionResult.result | `public let result: GuardrailResult` |
| 104 | var | public | GuardrailExecutionResult.didTriggerTripwire | `public var didTriggerTripwire: Bool { get }` |
| 109 | var | public | GuardrailExecutionResult.passed | `public var passed: Bool { get }` |
| 120 | func | public | GuardrailExecutionResult.init(guardrailName:result:) | `public init(guardrailName: String, result: GuardrailResult)` |
| 165 | class | public | GuardrailRunner | `public actor GuardrailRunner` |
| 167 | var | public | GuardrailRunner.configuration | `public let configuration: GuardrailRunnerConfiguration` |
| 170 | var | public | GuardrailRunner.observer | `public let observer: (any AgentObserver)?` |
| 179 | func | public | GuardrailRunner.init(configuration:observer:) | `public init(configuration: GuardrailRunnerConfiguration = .default, observer: (any AgentObserver)? = nil)` |
| 218 | func | public | GuardrailRunner.runInputGuardrails(_:input:context:) | `public func runInputGuardrails(_ guardrails: [any InputGuardrail], input: String, context: AgentContext?) async throws -> [GuardrailExecutionResult]` |
| 247 | func | public | GuardrailRunner.runOutputGuardrails(_:output:agent:context:) | `public func runOutputGuardrails(_ guardrails: [any OutputGuardrail], output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> [GuardrailExecutionResult]` |
| 275 | func | public | GuardrailRunner.runToolInputGuardrails(_:data:) | `public func runToolInputGuardrails(_ guardrails: [any ToolInputGuardrail], data: ToolGuardrailData) async throws -> [GuardrailExecutionResult]` |
| 302 | func | public | GuardrailRunner.runToolOutputGuardrails(_:data:output:) | `public func runToolOutputGuardrails(_ guardrails: [any ToolOutputGuardrail], data: ToolGuardrailData, output: SendableValue) async throws -> [GuardrailExecutionResult]` |

### Guardrails/InputGuardrail.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 10 | typealias | public | InputValidationHandler | `public typealias InputValidationHandler = (String, AgentContext?) async throws -> GuardrailResult` |
| 37 | protocol | public | InputGuardrail | `public protocol InputGuardrail : Guardrail` |
| 39 | var | public | InputGuardrail.name | `public override var name: String { get }` |
| 48 | func | public | InputGuardrail.validate(_:context:) | `public func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult` |
| 108 | struct | public | InputGuard | `public struct InputGuard` |
| 109 | var | public | InputGuard.name | `public let name: String` |
| 111 | func | public | InputGuard.init(_:_:) | `public init(_ name: String, _ validate: @escaping (String) async throws -> GuardrailResult)` |
| 121 | func | public | InputGuard.init(_:_:) | `public init(_ name: String, _ validate: @escaping (String, AgentContext?) async throws -> GuardrailResult)` |
| 129 | func | public | InputGuard.validate(_:context:) | `public func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult` |
| 258 | func | public | InputGuard.maxLength(_:name:) | `public static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard` |
| 280 | func | public | InputGuard.notEmpty(name:) | `public static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard` |
| 299 | func | public | InputGuard.custom(_:_:) | `public static func custom(_ name: String, _ validate: @escaping (String) async throws -> GuardrailResult) -> InputGuard` |

### Guardrails/OutputGuardrail.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | typealias | public | OutputValidationHandler | `public typealias OutputValidationHandler = (String, any AgentRuntime, AgentContext?) async throws -> GuardrailResult` |
| 47 | protocol | public | OutputGuardrail | `public protocol OutputGuardrail : Guardrail` |
| 49 | var | public | OutputGuardrail.name | `public override var name: String { get }` |
| 59 | func | public | OutputGuardrail.validate(_:agent:context:) | `public func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult` |
| 157 | struct | public | OutputGuard | `public struct OutputGuard` |
| 158 | var | public | OutputGuard.name | `public let name: String` |
| 160 | func | public | OutputGuard.init(_:_:) | `public init(_ name: String, _ validate: @escaping (String) async throws -> GuardrailResult)` |
| 170 | func | public | OutputGuard.init(_:_:) | `public init(_ name: String, _ validate: @escaping (String, AgentContext?) async throws -> GuardrailResult)` |
| 180 | func | public | OutputGuard.init(_:_:) | `public init(_ name: String, _ validate: @escaping OutputValidationHandler)` |
| 188 | func | public | OutputGuard.validate(_:agent:context:) | `public func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult` |
| 307 | func | public | OutputGuard.maxLength(_:name:) | `public static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard` |
| 327 | func | public | OutputGuard.custom(_:_:) | `public static func custom(_ name: String, _ validate: @escaping (String) async throws -> GuardrailResult) -> OutputGuard` |

### Guardrails/ToolGuardrails.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 10 | typealias | public | ToolInputValidationHandler | `public typealias ToolInputValidationHandler = (ToolGuardrailData) async throws -> GuardrailResult` |
| 13 | typealias | public | ToolOutputValidationHandler | `public typealias ToolOutputValidationHandler = (ToolGuardrailData, SendableValue) async throws -> GuardrailResult` |
| 33 | struct | public | ToolGuardrailData | `public struct ToolGuardrailData` |
| 35 | var | public | ToolGuardrailData.tool | `public let tool: any AnyJSONTool` |
| 38 | var | public | ToolGuardrailData.arguments | `public let arguments: [String : SendableValue]` |
| 41 | var | public | ToolGuardrailData.agent | `public let agent: (any AgentRuntime)?` |
| 44 | var | public | ToolGuardrailData.context | `public let context: AgentContext?` |
| 55 | func | public | ToolGuardrailData.init(tool:arguments:agent:context:) | `public init(tool: any AnyJSONTool, arguments: [String : SendableValue], agent: (any AgentRuntime)?, context: AgentContext?)` |
| 93 | protocol | public | ToolInputGuardrail | `public protocol ToolInputGuardrail : Sendable` |
| 95 | var | public | ToolInputGuardrail.name | `public var name: String { get }` |
| 102 | func | public | ToolInputGuardrail.validate(_:) | `public func validate(_ data: ToolGuardrailData) async throws -> GuardrailResult` |
| 134 | protocol | public | ToolOutputGuardrail | `public protocol ToolOutputGuardrail : Sendable` |
| 136 | var | public | ToolOutputGuardrail.name | `public var name: String { get }` |
| 145 | func | public | ToolOutputGuardrail.validate(_:output:) | `public func validate(_ data: ToolGuardrailData, output: SendableValue) async throws -> GuardrailResult` |
| 165 | struct | public | ClosureToolInputGuardrail | `public struct ClosureToolInputGuardrail` |
| 169 | var | public | ClosureToolInputGuardrail.name | `public let name: String` |
| 178 | func | public | ClosureToolInputGuardrail.init(name:handler:) | `public init(name: String, handler: @escaping (ToolGuardrailData) async throws -> GuardrailResult)` |
| 193 | func | public | ClosureToolInputGuardrail.validate(_:) | `public func validate(_ data: ToolGuardrailData) async throws -> GuardrailResult` |
| 222 | struct | public | ClosureToolOutputGuardrail | `public struct ClosureToolOutputGuardrail` |
| 226 | var | public | ClosureToolOutputGuardrail.name | `public let name: String` |
| 235 | func | public | ClosureToolOutputGuardrail.init(name:handler:) | `public init(name: String, handler: @escaping (ToolGuardrailData, SendableValue) async throws -> GuardrailResult)` |
| 252 | func | public | ClosureToolOutputGuardrail.validate(_:output:) | `public func validate(_ data: ToolGuardrailData, output: SendableValue) async throws -> GuardrailResult` |

## 7. Observability

### Observability/AgentTracer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 50 | protocol | public | Tracer | `public protocol Tracer : Actor` |
| 57 | func | public | Tracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 63 | func | public | Tracer.flush() | `public func flush() async` |
| 72 | func | public | Tracer.flush() | `public func flush() async` |
| 101 | class | public | CompositeTracer | `public actor CompositeTracer` |
| 110 | func | public | CompositeTracer.init(tracers:minimumLevel:shouldExecuteInParallel:) | `public init(tracers: [any Tracer], minimumLevel: EventLevel = .trace, shouldExecuteInParallel: Bool = true)` |
| 126 | func | public | CompositeTracer.init(tracers:parallel:) | `public convenience init(tracers: [any Tracer], parallel: Bool)` _(Availability: * (deprecated); Use shouldExecuteInParallel instead of parallel)_ |
| 130 | func | public | CompositeTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 151 | func | public | CompositeTracer.flush() | `public func flush() async` |
| 196 | class | public | NoOpTracer | `public actor NoOpTracer` |
| 198 | func | public | NoOpTracer.init() | `public init()` |
| 201 | func | public | NoOpTracer.trace(_:) | `public func trace(_: TraceEvent) async` |
| 206 | func | public | NoOpTracer.flush() | `public func flush() async` |
| 243 | class | public | BufferedTracer | `public actor BufferedTracer` |
| 252 | func | public | BufferedTracer.init(destination:maxBufferSize:flushInterval:) | `public init(destination: any Tracer, maxBufferSize: Int = 100, flushInterval: Duration = .seconds(5))` |
| 265 | func | public | BufferedTracer.start() | `public func start()` |
| 274 | func | public | BufferedTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 283 | func | public | BufferedTracer.flush() | `public func flush() async` |
| 358 | func | public | Tracer.trace(_:) | `public func trace(_ events: [TraceEvent]) async` |
| 371 | class | public | AnyTracer | `public actor AnyTracer` |
| 377 | func | public | AnyTracer.init(_:) | `public init(_ tracer: some Tracer)` |
| 386 | func | public | AnyTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 390 | func | public | AnyTracer.flush() | `public func flush() async` |

### Observability/ConsoleTracer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 45 | class | public | ConsoleTracer | `public actor ConsoleTracer` |
| 55 | func | public | ConsoleTracer.init(minimumLevel:colorized:includeTimestamp:includeSource:) | `public init(minimumLevel: EventLevel = .trace, colorized: Bool = true, includeTimestamp: Bool = true, includeSource: Bool = false)` |
| 71 | func | public | ConsoleTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 276 | class | public | PrettyConsoleTracer | `public actor PrettyConsoleTracer` |
| 286 | func | public | PrettyConsoleTracer.init(minimumLevel:colorized:includeTimestamp:includeSource:) | `public init(minimumLevel: EventLevel = .trace, colorized: Bool = true, includeTimestamp: Bool = true, includeSource: Bool = false)` |
| 302 | func | public | PrettyConsoleTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |

### Observability/MetricsCollector.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 30 | struct | public | MetricsSnapshot | `public struct MetricsSnapshot` |
| 34 | var | public | MetricsSnapshot.totalExecutions | `public let totalExecutions: Int` |
| 37 | var | public | MetricsSnapshot.successfulExecutions | `public let successfulExecutions: Int` |
| 40 | var | public | MetricsSnapshot.failedExecutions | `public let failedExecutions: Int` |
| 43 | var | public | MetricsSnapshot.cancelledExecutions | `public let cancelledExecutions: Int` |
| 48 | var | public | MetricsSnapshot.executionDurations | `public let executionDurations: [TimeInterval]` |
| 53 | var | public | MetricsSnapshot.toolCalls | `public let toolCalls: [String : Int]` |
| 56 | var | public | MetricsSnapshot.toolErrors | `public let toolErrors: [String : Int]` |
| 59 | var | public | MetricsSnapshot.toolDurations | `public let toolDurations: [String : [TimeInterval]]` |
| 62 | var | public | MetricsSnapshot.inputTokens | `public let inputTokens: Int` |
| 65 | var | public | MetricsSnapshot.outputTokens | `public let outputTokens: Int` |
| 68 | var | public | MetricsSnapshot.totalTokens | `public var totalTokens: Int { get }` |
| 70 | var | public | MetricsSnapshot.timestamp | `public let timestamp: Date` |
| 69 | var | public | MetricsSnapshot.successRate | `public var successRate: Double { get }` |
| 75 | var | public | MetricsSnapshot.errorRate | `public var errorRate: Double { get }` |
| 81 | var | public | MetricsSnapshot.cancellationRate | `public var cancellationRate: Double { get }` |
| 87 | var | public | MetricsSnapshot.totalToolCalls | `public var totalToolCalls: Int { get }` |
| 92 | var | public | MetricsSnapshot.totalToolErrors | `public var totalToolErrors: Int { get }` |
| 97 | var | public | MetricsSnapshot.averageExecutionDuration | `public var averageExecutionDuration: TimeInterval { get }` |
| 103 | var | public | MetricsSnapshot.minimumExecutionDuration | `public var minimumExecutionDuration: TimeInterval? { get }` |
| 108 | var | public | MetricsSnapshot.maximumExecutionDuration | `public var maximumExecutionDuration: TimeInterval? { get }` |
| 113 | var | public | MetricsSnapshot.medianExecutionDuration | `public var medianExecutionDuration: TimeInterval? { get }` |
| 125 | var | public | MetricsSnapshot.p95ExecutionDuration | `public var p95ExecutionDuration: TimeInterval? { get }` |
| 130 | var | public | MetricsSnapshot.p99ExecutionDuration | `public var p99ExecutionDuration: TimeInterval? { get }` |
| 145 | func | public | MetricsSnapshot.init(totalExecutions:successfulExecutions:failedExecutions:cancelledExecutions:executionDurations:toolCalls:toolErrors:toolDurations:timestamp:inputTokens:outputTokens:) | `public init(totalExecutions: Int, successfulExecutions: Int, failedExecutions: Int, cancelledExecutions: Int, executionDurations: [TimeInterval], toolCalls: [String : Int], toolErrors: [String : Int], toolDurations: [String : [TimeInterval]], timestamp: Date = Date(), inputTokens: Int = 0, outputTokens: Int = 0)` |
| 201 | class | public | MetricsCollector | `public actor MetricsCollector` |
| 207 | var | public | MetricsCollector.maxMetricsHistory | `public let maxMetricsHistory: Int` |
| 213 | func | public | MetricsCollector.init(maxMetricsHistory:) | `public init(maxMetricsHistory: Int = 10000)` |
| 232 | func | public | MetricsCollector.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 303 | func | public | MetricsCollector.flush() | `public func flush() async` |
| 314 | func | public | MetricsCollector.snapshot() | `public func snapshot() -> MetricsSnapshot` |
| 339 | func | public | MetricsCollector.reset() | `public func reset()` |
| 354 | func | public | MetricsCollector.getTotalExecutions() | `public func getTotalExecutions() -> Int` |
| 359 | func | public | MetricsCollector.getSuccessfulExecutions() | `public func getSuccessfulExecutions() -> Int` |
| 364 | func | public | MetricsCollector.getFailedExecutions() | `public func getFailedExecutions() -> Int` |
| 369 | func | public | MetricsCollector.getCancelledExecutions() | `public func getCancelledExecutions() -> Int` |
| 374 | func | public | MetricsCollector.getToolCalls() | `public func getToolCalls() -> [String : Int]` |
| 379 | func | public | MetricsCollector.getToolErrors() | `public func getToolErrors() -> [String : Int]` |
| 384 | func | public | MetricsCollector.getToolDurations() | `public func getToolDurations() -> [String : [TimeInterval]]` |
| 471 | struct | public | JSONMetricsReporter | `public struct JSONMetricsReporter` |
| 473 | var | public | JSONMetricsReporter.outputPath | `public let outputPath: String?` |
| 476 | var | public | JSONMetricsReporter.prettyPrint | `public let prettyPrint: Bool` |
| 483 | func | public | JSONMetricsReporter.init(outputPath:prettyPrint:) | `public init(outputPath: String? = nil, prettyPrint: Bool = true)` |
| 492 | func | public | JSONMetricsReporter.report(_:) | `public func report(_ snapshot: MetricsSnapshot) async throws` |
| 525 | func | public | JSONMetricsReporter.jsonData(from:) | `public func jsonData(from snapshot: MetricsSnapshot) throws -> Data` |
| 543 | func | public | JSONMetricsReporter.jsonString(from:) | `public func jsonString(from snapshot: MetricsSnapshot) throws -> String` |
| 555 | enum | public | MetricsReporterError | `public enum MetricsReporterError` |
| 556 | case | public | MetricsReporterError.encodingFailed | `public case encodingFailed` |
| 557 | case | public | MetricsReporterError.writeFailed(_:) | `public case writeFailed(String)` |
| 558 | case | public | MetricsReporterError.invalidPath(_:) | `public case invalidPath(String)` |
| 564 | var | public | MetricsSnapshot.description | `public var description: String { get }` |

### Observability/OSLogTracer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 51 | class | public | OSLogTracer | `public actor OSLogTracer` |
| 63 | func | public | OSLogTracer.init(subsystem:category:minimumLevel:emitSignposts:) | `public init(subsystem: String, category: String, minimumLevel: EventLevel = .debug, emitSignposts: Bool = true)` |
| 79 | func | public | OSLogTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 290 | struct | public | OSLogTracer.Builder | `public struct Builder` |
| 296 | func | public | OSLogTracer.Builder.init(subsystem:) | `public init(subsystem: String)` |
| 307 | func | public | OSLogTracer.Builder.category(_:) | `public func category(_ category: String) -> OSLogTracer.Builder` |
| 317 | func | public | OSLogTracer.Builder.minimumLevel(_:) | `public func minimumLevel(_ level: EventLevel) -> OSLogTracer.Builder` |
| 327 | func | public | OSLogTracer.Builder.emitSignposts(_:) | `public func emitSignposts(_ emit: Bool) -> OSLogTracer.Builder` |
| 336 | func | public | OSLogTracer.Builder.build() | `public func build() -> OSLogTracer` |
| 366 | func | public | OSLogTracer.default(subsystem:) | `public static func `default`(subsystem: String) -> OSLogTracer` |
| 379 | func | public | OSLogTracer.production(subsystem:) | `public static func production(subsystem: String) -> OSLogTracer` |
| 395 | func | public | OSLogTracer.debug(subsystem:) | `public static func debug(subsystem: String) -> OSLogTracer` |

### Observability/PerformanceMetrics.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 46 | struct | public | PerformanceMetrics | `public struct PerformanceMetrics` |
| 51 | var | public | PerformanceMetrics.totalDuration | `public let totalDuration: Duration` |
| 57 | var | public | PerformanceMetrics.llmDuration | `public let llmDuration: Duration` |
| 63 | var | public | PerformanceMetrics.toolDuration | `public let toolDuration: Duration` |
| 69 | var | public | PerformanceMetrics.toolCount | `public let toolCount: Int` |
| 75 | var | public | PerformanceMetrics.usedParallelExecution | `public let usedParallelExecution: Bool` |
| 84 | var | public | PerformanceMetrics.estimatedSequentialDuration | `public let estimatedSequentialDuration: Duration?` |
| 108 | var | public | PerformanceMetrics.parallelSpeedup | `public var parallelSpeedup: Double? { get }` |
| 136 | func | public | PerformanceMetrics.init(totalDuration:llmDuration:toolDuration:toolCount:usedParallelExecution:estimatedSequentialDuration:) | `public init(totalDuration: Duration, llmDuration: Duration, toolDuration: Duration, toolCount: Int, usedParallelExecution: Bool, estimatedSequentialDuration: Duration? = nil)` |
| 202 | class | public | PerformanceTracker | `public actor PerformanceTracker` |
| 210 | func | public | PerformanceTracker.init() | `public init()` |
| 226 | func | public | PerformanceTracker.start() | `public func start()` |
| 242 | func | public | PerformanceTracker.recordLLMCall(duration:) | `public func recordLLMCall(duration: Duration)` |
| 265 | func | public | PerformanceTracker.recordToolExecution(duration:wasParallel:count:) | `public func recordToolExecution(duration: Duration, wasParallel: Bool, count: Int = 1)` |
| 284 | func | public | PerformanceTracker.recordSequentialEstimate(_:) | `public func recordSequentialEstimate(_ duration: Duration)` |
| 302 | func | public | PerformanceTracker.finish() | `public func finish() -> PerformanceMetrics` |
| 329 | func | public | PerformanceTracker.reset() | `public func reset()` |
| 364 | var | public | PerformanceMetrics.description | `public var description: String { get }` |
| 391 | var | public | PerformanceMetrics.debugDescription | `public var debugDescription: String { get }` |

### Observability/SwiftLogTracer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 36 | class | public | SwiftLogTracer | `public actor SwiftLogTracer` |
| 44 | func | public | SwiftLogTracer.init(label:minimumLevel:) | `public init(label: String = "com.swarm.tracer", minimumLevel: EventLevel = .debug)` |
| 54 | func | public | SwiftLogTracer.trace(_:) | `public func trace(_ event: TraceEvent) async` |
| 76 | func | public | SwiftLogTracer.flush() | `public func flush() async` |
| 147 | func | public | SwiftLogTracer.development() | `public static func development() -> SwiftLogTracer` |
| 154 | func | public | SwiftLogTracer.production() | `public static func production() -> SwiftLogTracer` |

### Observability/TraceContext.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 33 | class | public | TraceContext | `public actor TraceContext` |
| 66 | var | public | TraceContext.current | `public static var current: TraceContext? { get }` |
| 71 | var | public | TraceContext.name | `public let name: String` |
| 75 | var | public | TraceContext.traceId | `public let traceId: UUID` |
| 79 | var | public | TraceContext.groupId | `public let groupId: String?` |
| 82 | var | public | TraceContext.metadata | `public let metadata: [String : SendableValue]` |
| 85 | var | public | TraceContext.startTime | `public let startTime: Date` |
| 90 | var | public | TraceContext.duration | `public var duration: TimeInterval { get }` |
| 115 | func | public | TraceContext.withTrace(_:groupId:metadata:operation:) | `public static func withTrace<T>(_ name: String, groupId: String? = nil, metadata: [String : SendableValue] = [:], operation: () async throws -> T) async rethrows -> T where T : Sendable` |
| 148 | func | public | TraceContext.startSpan(_:metadata:) | `public func startSpan(_ name: String, metadata: [String : SendableValue] = [:]) -> TraceSpan` |
| 174 | func | public | TraceContext.endSpan(_:status:) | `public func endSpan(_ span: TraceSpan, status: SpanStatus = .ok)` |
| 192 | func | public | TraceContext.addSpan(_:) | `public func addSpan(_ span: TraceSpan)` |
| 199 | func | public | TraceContext.getSpans() | `public func getSpans() -> [TraceSpan]` |
| 240 | var | public | TraceContext.description | `public nonisolated var description: String { get }` |
| 266 | func | public | TraceContext.withSpan(_:metadata:operation:) | `public func withSpan<T>(_ name: String, metadata: [String : SendableValue] = [:], operation: () async throws -> T) async rethrows -> T where T : Sendable` |

### Observability/TraceContextHeaders.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 27 | struct | public | TraceContextHeaders | `public struct TraceContextHeaders` |
| 29 | var | public | TraceContextHeaders.traceparentHeaderName | `public static let traceparentHeaderName: String` |
| 32 | var | public | TraceContextHeaders.tracestateHeaderName | `public static let tracestateHeaderName: String` |
| 35 | var | public | TraceContextHeaders.traceparentPattern | `public static let traceparentPattern: String` |
| 38 | var | public | TraceContextHeaders.current | `public static var current: TraceContextHeaders? { get }` |
| 43 | var | public | TraceContextHeaders.traceparent | `public let traceparent: String` |
| 46 | var | public | TraceContextHeaders.tracestate | `public let tracestate: String?` |
| 64 | var | public | TraceContextHeaders.httpHeaders | `public var httpHeaders: [String : String] { get }` |
| 78 | func | public | TraceContextHeaders.init(traceparent:tracestate:) | `public init?(traceparent: String, tracestate: String? = nil)` |
| 92 | func | public | TraceContextHeaders.init(traceId:spanId:sampled:tracestate:) | `public init?(traceId: String, spanId: String, sampled: Bool = true, tracestate: String? = nil)` |
| 114 | func | public | TraceContextHeaders.withCurrent(_:operation:) | `public static func withCurrent<T>(_ headers: TraceContextHeaders?, operation: () async throws -> T) async rethrows -> T where T : Sendable` |
| 124 | func | public | TraceContextHeaders.applyCurrent(to:) | `public static func applyCurrent(to request: inout URLRequest)` |
| 129 | func | public | TraceContextHeaders.apply(to:) | `public func apply(to request: inout URLRequest)` |
| 137 | func | public | TraceContextHeaders.isValidTraceparent(_:) | `public static func isValidTraceparent(_ value: String) -> Bool` |

### Observability/TraceEvent.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 12 | enum | public | EventLevel | `public enum EventLevel` |
| 15 | func | public | EventLevel.<(_:_:) | `public static func < (lhs: EventLevel, rhs: EventLevel) -> Bool` |
| 19 | case | public | EventLevel.trace | `public case trace` |
| 20 | case | public | EventLevel.debug | `public case debug` |
| 21 | case | public | EventLevel.info | `public case info` |
| 22 | case | public | EventLevel.warning | `public case warning` |
| 23 | case | public | EventLevel.error | `public case error` |
| 24 | case | public | EventLevel.critical | `public case critical` |
| 30 | enum | public | EventKind | `public enum EventKind` |
| 32 | case | public | EventKind.agentStart | `public case agentStart` |
| 34 | case | public | EventKind.agentComplete | `public case agentComplete` |
| 36 | case | public | EventKind.agentError | `public case agentError` |
| 38 | case | public | EventKind.agentCancelled | `public case agentCancelled` |
| 41 | case | public | EventKind.toolCall | `public case toolCall` |
| 43 | case | public | EventKind.toolResult | `public case toolResult` |
| 45 | case | public | EventKind.toolError | `public case toolError` |
| 48 | case | public | EventKind.thought | `public case thought` |
| 50 | case | public | EventKind.decision | `public case decision` |
| 52 | case | public | EventKind.plan | `public case plan` |
| 55 | case | public | EventKind.memoryRead | `public case memoryRead` |
| 57 | case | public | EventKind.memoryWrite | `public case memoryWrite` |
| 60 | case | public | EventKind.checkpoint | `public case checkpoint` |
| 62 | case | public | EventKind.metric | `public case metric` |
| 64 | case | public | EventKind.custom | `public case custom` |
| 70 | struct | public | SourceLocation | `public struct SourceLocation` |
| 71 | var | public | SourceLocation.file | `public let file: String` |
| 72 | var | public | SourceLocation.function | `public let function: String` |
| 73 | var | public | SourceLocation.line | `public let line: Int` |
| 76 | var | public | SourceLocation.filename | `public var filename: String { get }` |
| 81 | var | public | SourceLocation.formatted | `public var formatted: String { get }` |
| 86 | func | public | SourceLocation.init(file:function:line:) | `public init(file: String = #file, function: String = #function, line: Int = #line)` |
| 100 | struct | public | ErrorInfo | `public struct ErrorInfo` |
| 101 | var | public | ErrorInfo.type | `public let type: String` |
| 102 | var | public | ErrorInfo.message | `public let message: String` |
| 103 | var | public | ErrorInfo.stackTrace | `public let stackTrace: [String]?` |
| 104 | var | public | ErrorInfo.underlyingError | `public let underlyingError: String?` |
| 107 | func | public | ErrorInfo.init(type:message:stackTrace:underlyingError:) | `public init(type: String, message: String, stackTrace: [String]? = nil, underlyingError: String? = nil)` |
| 120 | func | public | ErrorInfo.init(from:) | `public init(from error: any Error)` |
| 137 | struct | public | TraceEvent | `public struct TraceEvent` |
| 139 | var | public | TraceEvent.id | `public let id: UUID` |
| 142 | var | public | TraceEvent.traceId | `public let traceId: UUID` |
| 145 | var | public | TraceEvent.spanId | `public let spanId: UUID` |
| 148 | var | public | TraceEvent.parentSpanId | `public let parentSpanId: UUID?` |
| 151 | var | public | TraceEvent.timestamp | `public let timestamp: Date` |
| 154 | var | public | TraceEvent.duration | `public let duration: TimeInterval?` |
| 157 | var | public | TraceEvent.kind | `public let kind: EventKind` |
| 160 | var | public | TraceEvent.level | `public let level: EventLevel` |
| 163 | var | public | TraceEvent.message | `public let message: String` |
| 166 | var | public | TraceEvent.metadata | `public let metadata: [String : SendableValue]` |
| 169 | var | public | TraceEvent.agentName | `public let agentName: String?` |
| 172 | var | public | TraceEvent.toolName | `public let toolName: String?` |
| 175 | var | public | TraceEvent.error | `public let error: ErrorInfo?` |
| 178 | var | public | TraceEvent.source | `public let source: SourceLocation?` |
| 181 | func | public | TraceEvent.init(id:traceId:spanId:parentSpanId:timestamp:duration:kind:level:message:metadata:agentName:toolName:error:source:) | `public init(id: UUID = UUID(), traceId: UUID, spanId: UUID = UUID(), parentSpanId: UUID? = nil, timestamp: Date = Date(), duration: TimeInterval? = nil, kind: EventKind, level: EventLevel = .info, message: String, metadata: [String : SendableValue] = [:], agentName: String? = nil, toolName: String? = nil, error: ErrorInfo? = nil, source: SourceLocation? = nil)` |
| 218 | class | public | TraceEvent.Builder | `public final class Builder` |
| 222 | func | public | TraceEvent.Builder.init(traceId:kind:message:id:spanId:timestamp:level:) | `public init(traceId: UUID, kind: EventKind, message: String, id: UUID = UUID(), spanId: UUID = UUID(), timestamp: Date = Date(), level: EventLevel = .info)` |
| 243 | func | public | TraceEvent.Builder.parentSpan(_:) | `public @discardableResult func parentSpan(_ id: UUID) -> TraceEvent.Builder` |
| 250 | func | public | TraceEvent.Builder.timestamp(_:) | `public @discardableResult func timestamp(_ date: Date) -> TraceEvent.Builder` |
| 257 | func | public | TraceEvent.Builder.duration(_:) | `public @discardableResult func duration(_ duration: TimeInterval) -> TraceEvent.Builder` |
| 264 | func | public | TraceEvent.Builder.level(_:) | `public @discardableResult func level(_ level: EventLevel) -> TraceEvent.Builder` |
| 271 | func | public | TraceEvent.Builder.message(_:) | `public @discardableResult func message(_ message: String) -> TraceEvent.Builder` |
| 278 | func | public | TraceEvent.Builder.metadata(key:value:) | `public @discardableResult func metadata(key: String, value: SendableValue) -> TraceEvent.Builder` |
| 285 | func | public | TraceEvent.Builder.metadata(_:) | `public @discardableResult func metadata(_ metadata: [String : SendableValue]) -> TraceEvent.Builder` |
| 292 | func | public | TraceEvent.Builder.addingMetadata(_:) | `public @discardableResult func addingMetadata(_ additional: [String : SendableValue]) -> TraceEvent.Builder` |
| 299 | func | public | TraceEvent.Builder.agent(_:) | `public @discardableResult func agent(_ name: String) -> TraceEvent.Builder` |
| 306 | func | public | TraceEvent.Builder.tool(_:) | `public @discardableResult func tool(_ name: String) -> TraceEvent.Builder` |
| 313 | func | public | TraceEvent.Builder.error(_:) | `public @discardableResult func error(_ error: any Error) -> TraceEvent.Builder` |
| 320 | func | public | TraceEvent.Builder.error(_:) | `public @discardableResult func error(_ errorInfo: ErrorInfo) -> TraceEvent.Builder` |
| 327 | func | public | TraceEvent.Builder.source(file:function:line:) | `public @discardableResult func source(file: String = #file, function: String = #function, line: Int = #line) -> TraceEvent.Builder` |
| 338 | func | public | TraceEvent.Builder.source(_:) | `public @discardableResult func source(_ location: SourceLocation) -> TraceEvent.Builder` |
| 344 | func | public | TraceEvent.Builder.build() | `public func build() -> TraceEvent` |
| 386 | func | public | TraceEvent.agentStart(traceId:spanId:agentName:metadata:source:) | `public static func agentStart(traceId: UUID, spanId: UUID = UUID(), agentName: String, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 401 | func | public | TraceEvent.agentComplete(traceId:spanId:agentName:duration:metadata:source:) | `public static func agentComplete(traceId: UUID, spanId: UUID, agentName: String, duration: TimeInterval, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 418 | func | public | TraceEvent.agentError(traceId:spanId:agentName:error:metadata:source:) | `public static func agentError(traceId: UUID, spanId: UUID, agentName: String, error: any Error, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 435 | func | public | TraceEvent.toolCall(traceId:spanId:parentSpanId:toolName:metadata:source:) | `public static func toolCall(traceId: UUID, spanId: UUID = UUID(), parentSpanId: UUID?, toolName: String, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 452 | func | public | TraceEvent.toolResult(traceId:spanId:toolName:duration:metadata:source:) | `public static func toolResult(traceId: UUID, spanId: UUID, toolName: String, duration: TimeInterval, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 469 | func | public | TraceEvent.thought(traceId:spanId:agentName:thought:metadata:source:) | `public static func thought(traceId: UUID, spanId: UUID, agentName: String, thought: String, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 488 | func | public | TraceEvent.custom(traceId:spanId:message:level:metadata:source:) | `public static func custom(traceId: UUID, spanId: UUID = UUID(), message: String, level: EventLevel = .info, metadata: [String : SendableValue] = [:], source: SourceLocation? = nil) -> TraceEvent` |
| 506 | var | public | TraceEvent.description | `public var description: String { get }` |
| 533 | var | public | EventLevel.description | `public var description: String { get }` |

### Observability/TraceSpan.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | enum | public | SpanStatus | `public enum SpanStatus` |
| 13 | case | public | SpanStatus.active | `public case active` |
| 15 | case | public | SpanStatus.ok | `public case ok` |
| 17 | case | public | SpanStatus.error | `public case error` |
| 19 | case | public | SpanStatus.cancelled | `public case cancelled` |
| 38 | struct | public | TraceSpan | `public struct TraceSpan` |
| 40 | var | public | TraceSpan.id | `public let id: UUID` |
| 44 | var | public | TraceSpan.parentSpanId | `public let parentSpanId: UUID?` |
| 47 | var | public | TraceSpan.name | `public let name: String` |
| 50 | var | public | TraceSpan.startTime | `public let startTime: Date` |
| 54 | var | public | TraceSpan.endTime | `public let endTime: Date?` |
| 57 | var | public | TraceSpan.status | `public let status: SpanStatus` |
| 60 | var | public | TraceSpan.metadata | `public let metadata: [String : SendableValue]` |
| 66 | var | public | TraceSpan.duration | `public var duration: TimeInterval? { get }` |
| 85 | func | public | TraceSpan.init(id:parentSpanId:name:startTime:endTime:status:metadata:) | `public init(id: UUID = UUID(), parentSpanId: UUID? = nil, name: String, startTime: Date = Date(), endTime: Date? = nil, status: SpanStatus = .active, metadata: [String : SendableValue] = [:])` |
| 119 | func | public | TraceSpan.completed(status:) | `public func completed(status: SpanStatus = .ok) -> TraceSpan` |
| 135 | var | public | TraceSpan.description | `public var description: String { get }` |
| 154 | var | public | TraceSpan.debugDescription | `public var debugDescription: String { get }` |

### Observability/TracingHelper.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 28 | struct | public | TracingHelper | `public struct TracingHelper` |
| 32 | var | public | TracingHelper.tracer | `public let tracer: (any Tracer)?` |
| 35 | var | public | TracingHelper.traceId | `public let traceId: UUID` |
| 38 | var | public | TracingHelper.agentName | `public let agentName: String` |
| 45 | func | public | TracingHelper.init(tracer:agentName:) | `public init(tracer: (any Tracer)?, agentName: String)` |
| 57 | func | public | TracingHelper.traceStart(input:) | `public func traceStart(input: String) async` |
| 74 | func | public | TracingHelper.traceComplete(result:) | `public func traceComplete(result: AgentResult) async` |
| 88 | func | public | TracingHelper.traceComplete(result:tokenUsage:) | `public func traceComplete(result: AgentResult, tokenUsage: TokenUsage?) async` |
| 95 | func | public | TracingHelper.traceError(_:) | `public func traceError(_ error: any Error) async` |
| 119 | func | public | TracingHelper.traceThought(_:) | `public func traceThought(_ thought: String) async` |
| 137 | func | public | TracingHelper.tracePlan(_:) | `public func tracePlan(_ plan: String) async` |
| 158 | func | public | TracingHelper.traceToolCall(name:arguments:) | `public func traceToolCall(name: String, arguments: [String : SendableValue]) async -> UUID` |
| 185 | func | public | TracingHelper.traceToolResult(spanId:name:result:duration:) | `public func traceToolResult(spanId: UUID, name: String, result: String, duration: Duration) async` |
| 216 | func | public | TracingHelper.traceToolError(spanId:name:error:) | `public func traceToolError(spanId: UUID, name: String, error: any Error) async` |
| 242 | func | public | TracingHelper.traceMemoryRead(count:source:) | `public func traceMemoryRead(count: Int, source: String) async` |
| 262 | func | public | TracingHelper.traceMemoryWrite(count:destination:) | `public func traceMemoryWrite(count: Int, destination: String) async` |
| 284 | func | public | TracingHelper.traceDecision(_:options:) | `public func traceDecision(_ decision: String, options: [String] = []) async` |
| 308 | func | public | TracingHelper.traceCheckpoint(name:metadata:) | `public func traceCheckpoint(name: String, metadata: [String : SendableValue] = [:]) async` |
| 329 | func | public | TracingHelper.traceCustom(kind:message:metadata:) | `public func traceCustom(kind: EventKind, message: String, metadata: [String : SendableValue] = [:]) async` |

## 8. Resilience

### Resilience/CircuitBreaker.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 32 | class | public | CircuitBreaker | `public actor CircuitBreaker` |
| 38 | enum | public | CircuitBreaker.State | `public enum State` |
| 40 | case | public | CircuitBreaker.State.closed | `public case closed` |
| 43 | case | public | CircuitBreaker.State.open(until:) | `public case open(until: Date)` |
| 46 | case | public | CircuitBreaker.State.halfOpen | `public case halfOpen` |
| 50 | var | public | CircuitBreaker.name | `public let name: String` |
| 53 | var | public | CircuitBreaker.failureThreshold | `public let failureThreshold: Int` |
| 56 | var | public | CircuitBreaker.successThreshold | `public let successThreshold: Int` |
| 59 | var | public | CircuitBreaker.resetTimeout | `public let resetTimeout: TimeInterval` |
| 62 | var | public | CircuitBreaker.halfOpenMaxRequests | `public let halfOpenMaxRequests: Int` |
| 73 | func | public | CircuitBreaker.init(name:failureThreshold:successThreshold:resetTimeout:halfOpenMaxRequests:) | `public init(name: String, failureThreshold: Int = 5, successThreshold: Int = 2, resetTimeout: TimeInterval = 60.0, halfOpenMaxRequests: Int = 1)` |
| 93 | func | public | CircuitBreaker.execute(_:) | `public func execute<T>(_ operation: () async throws -> T) async throws -> T where T : Sendable` |
| 121 | func | public | CircuitBreaker.currentState() | `public func currentState() -> CircuitBreaker.State` |
| 126 | func | public | CircuitBreaker.reset() | `public func reset() async` |
| 134 | func | public | CircuitBreaker.trip() | `public func trip() async` |
| 141 | func | public | CircuitBreaker.statistics() | `public func statistics() -> Statistics` |
| 251 | struct | public | Statistics | `public struct Statistics` |
| 253 | var | public | Statistics.name | `public let name: String` |
| 256 | var | public | Statistics.state | `public let state: CircuitBreaker.State` |
| 259 | var | public | Statistics.failureCount | `public let failureCount: Int` |
| 262 | var | public | Statistics.successCount | `public let successCount: Int` |
| 265 | var | public | Statistics.lastFailureTime | `public let lastFailureTime: Date?` |
| 268 | var | public | Statistics.successRate | `public var successRate: Double? { get }` |
| 295 | class | public | CircuitBreakerRegistry | `public actor CircuitBreakerRegistry` |
| 301 | struct | public | CircuitBreakerRegistry.Configuration | `public struct Configuration` |
| 303 | var | public | CircuitBreakerRegistry.Configuration.failureThreshold | `public var failureThreshold: Int` |
| 306 | var | public | CircuitBreakerRegistry.Configuration.successThreshold | `public var successThreshold: Int` |
| 309 | var | public | CircuitBreakerRegistry.Configuration.resetTimeout | `public var resetTimeout: TimeInterval` |
| 312 | var | public | CircuitBreakerRegistry.Configuration.halfOpenMaxRequests | `public var halfOpenMaxRequests: Int` |
| 314 | func | public | CircuitBreakerRegistry.Configuration.init() | `public init()` |
| 321 | func | public | CircuitBreakerRegistry.init(defaultConfiguration:) | `public init(defaultConfiguration: CircuitBreakerRegistry.Configuration = Configuration())` |
| 332 | func | public | CircuitBreakerRegistry.breaker(named:configure:) | `public func breaker(named name: String, configure: ((inout CircuitBreakerRegistry.Configuration) -> Void)? = nil) -> CircuitBreaker` |
| 358 | func | public | CircuitBreakerRegistry.allBreakers() | `public func allBreakers() -> [CircuitBreaker]` |
| 363 | func | public | CircuitBreakerRegistry.resetAll() | `public func resetAll() async` |
| 371 | func | public | CircuitBreakerRegistry.remove(named:) | `public func remove(named name: String)` |
| 376 | func | public | CircuitBreakerRegistry.removeAll() | `public func removeAll()` |
| 381 | func | public | CircuitBreakerRegistry.allStatistics() | `public func allStatistics() async -> [Statistics]` |
| 403 | func | public | CircuitBreaker.isAllowingRequests() | `public func isAllowingRequests() -> Bool` |

### Resilience/FallbackChain.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | struct | public | StepError | `public struct StepError` |
| 13 | var | public | StepError.stepName | `public let stepName: String` |
| 16 | var | public | StepError.stepIndex | `public let stepIndex: Int` |
| 19 | var | public | StepError.error | `public let error: any Error` |
| 26 | func | public | StepError.init(stepName:stepIndex:error:) | `public init(stepName: String, stepIndex: Int, error: any Error)` |
| 32 | func | public | StepError.==(_:_:) | `public static func == (lhs: StepError, rhs: StepError) -> Bool` |
| 42 | var | public | StepError.debugDescription | `public var debugDescription: String { get }` |
| 50 | struct | public | ExecutionResult | `public struct ExecutionResult<Output> where Output : Sendable` |
| 52 | var | public | ExecutionResult.output | `public let output: Output` |
| 55 | var | public | ExecutionResult.stepName | `public let stepName: String` |
| 58 | var | public | ExecutionResult.stepIndex | `public let stepIndex: Int` |
| 61 | var | public | ExecutionResult.totalAttempts | `public let totalAttempts: Int` |
| 64 | var | public | ExecutionResult.errors | `public let errors: [StepError]` |
| 73 | func | public | ExecutionResult.init(output:stepName:stepIndex:totalAttempts:errors:) | `public init(output: Output, stepName: String, stepIndex: Int, totalAttempts: Int, errors: [StepError])` |
| 91 | var | public | ExecutionResult.debugDescription | `public var debugDescription: String { get }` |
| 115 | struct | public | FallbackChain | `public struct FallbackChain<Output> where Output : Sendable` |
| 121 | func | public | FallbackChain.init() | `public init()` |
| 131 | func | public | FallbackChain.from(_:) | `public static func from(_ operations: (name: String, operation: () async throws -> Output)...) -> FallbackChain<Output>` |
| 146 | func | public | FallbackChain.attempt(name:_:) | `public func attempt(name: String, _ operation: @escaping () async throws -> Output) -> FallbackChain<Output>` |
| 163 | func | public | FallbackChain.attemptIf(name:condition:_:) | `public func attemptIf(name: String, condition: @escaping () async -> Bool, _ operation: @escaping () async throws -> Output) -> FallbackChain<Output>` |
| 180 | func | public | FallbackChain.fallback(name:_:) | `public func fallback(name: String, _ value: Output) -> FallbackChain<Output>` |
| 197 | func | public | FallbackChain.fallback(name:_:) | `public func fallback(name: String, _ operation: @escaping () async -> Output) -> FallbackChain<Output>` |
| 215 | func | public | FallbackChain.onFailure(_:) | `public func onFailure(_ callback: @escaping (String, any Error) async -> Void) -> FallbackChain<Output>` |
| 226 | func | public | FallbackChain.execute() | `public func execute() async throws -> Output` |
| 234 | func | public | FallbackChain.executeWithResult() | `public func executeWithResult() async throws -> ExecutionResult<Output>` |
| 345 | var | public | FallbackChain.debugDescription | `public var debugDescription: String { get }` |

### Resilience/RateLimiter.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 30 | class | public | RateLimiter | `public actor RateLimiter` |
| 34 | var | public | RateLimiter.available | `public var available: Int { get }` |
| 40 | func | public | RateLimiter.init(maxRequestsPerMinute:) | `public init(maxRequestsPerMinute: Int)` |
| 49 | func | public | RateLimiter.init(maxTokens:refillRatePerSecond:) | `public init(maxTokens: Int, refillRatePerSecond: Double)` |
| 62 | func | public | RateLimiter.acquire() | `public func acquire() async throws` |
| 78 | func | public | RateLimiter.tryAcquire() | `public func tryAcquire() -> Bool` |
| 88 | func | public | RateLimiter.reset() | `public func reset()` |

### Resilience/Resilience.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 17 | typealias | public | Retry | `public typealias Retry = RetryPolicy` |
| 18 | typealias | public | Fallback | `public typealias Fallback = FallbackChain` |

### Resilience/ResilienceConfiguration.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 20 | struct | public | CircuitBreakerSettings | `public struct CircuitBreakerSettings` |
| 79 | struct | public | RateLimitSettings | `public struct RateLimitSettings` |
| 160 | struct | public | ResilienceConfiguration | `public struct ResilienceConfiguration` |
| 165 | var | public | ResilienceConfiguration.disabled | `public static let disabled: ResilienceConfiguration` |
| 172 | var | public | ResilienceConfiguration.retryPolicy | `public var retryPolicy: RetryPolicy` |
| 177 | var | public | ResilienceConfiguration.circuitBreaker | `public var circuitBreaker: CircuitBreakerSettings?` |
| 182 | var | public | ResilienceConfiguration.rateLimit | `public var rateLimit: RateLimitSettings?` |

### Resilience/InferenceRetryability.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 52 | enum | public | InferenceRetryability | `public enum InferenceRetryability` |
| 57 | func | public | InferenceRetryability.isRetryable(_:) | `public static func isRetryable(_ error: Error) -> Bool` |

### Resilience/RetryPolicy.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | enum | public | ResilienceError | `public enum ResilienceError` |
| 13 | case | public | ResilienceError.retriesExhausted(attempts:lastError:) | `public case retriesExhausted(attempts: Int, lastError: String)` |
| 16 | case | public | ResilienceError.circuitBreakerOpen(serviceName:) | `public case circuitBreakerOpen(serviceName: String)` |
| 19 | case | public | ResilienceError.allFallbacksFailed(errors:) | `public case allFallbacksFailed(errors: [String])` |
| 25 | var | public | ResilienceError.errorDescription | `public var errorDescription: String? { get }` |
| 40 | var | public | ResilienceError.debugDescription | `public var debugDescription: String { get }` |
| 55 | enum | public | BackoffStrategy | `public enum BackoffStrategy` |
| 61 | func | public | BackoffStrategy.delay(forAttempt:) | `public func delay(forAttempt attempt: Int) -> TimeInterval` |
| 97 | case | public | BackoffStrategy.fixed(delay:) | `public case fixed(delay: TimeInterval)` |
| 100 | case | public | BackoffStrategy.linear(initial:increment:maxDelay:) | `public case linear(initial: TimeInterval, increment: TimeInterval, maxDelay: TimeInterval)` |
| 103 | case | public | BackoffStrategy.exponential(base:multiplier:maxDelay:) | `public case exponential(base: TimeInterval, multiplier: Double, maxDelay: TimeInterval)` |
| 106 | case | public | BackoffStrategy.exponentialWithJitter(base:multiplier:maxDelay:) | `public case exponentialWithJitter(base: TimeInterval, multiplier: Double, maxDelay: TimeInterval)` |
| 109 | case | public | BackoffStrategy.decorrelatedJitter(base:maxDelay:) | `public case decorrelatedJitter(base: TimeInterval, maxDelay: TimeInterval)` |
| 112 | case | public | BackoffStrategy.immediate | `public case immediate` |
| 120 | case | public | BackoffStrategy.custom(_:) | `public case custom((Int) -> TimeInterval)` |
| 126 | func | public | BackoffStrategy.==(_:_:) | `public static func == (lhs: BackoffStrategy, rhs: BackoffStrategy) -> Bool` |
| 152 | struct | public | RetryPolicy | `public struct RetryPolicy` |
| 160 | var | public | RetryPolicy.noRetry | `public static let noRetry: RetryPolicy` |
| 163 | var | public | RetryPolicy.standard | `public static let standard: RetryPolicy` |
| 169 | var | public | RetryPolicy.aggressive | `public static let aggressive: RetryPolicy` |
| 175 | var | public | RetryPolicy.maxAttempts | `public let maxAttempts: Int` |
| 178 | var | public | RetryPolicy.backoff | `public let backoff: BackoffStrategy` |
| 181 | var | public | RetryPolicy.shouldRetry | `public let shouldRetry: (any Error) -> Bool` |
| 184 | var | public | RetryPolicy.onRetry | `public let onRetry: ((Int, any Error) async -> Void)?` |
| 194 | func | public | RetryPolicy.init(maxAttempts:backoff:shouldRetry:onRetry:) | `public init(maxAttempts: Int = 3, backoff: BackoffStrategy = .exponential(base: 1.0, multiplier: 2.0, maxDelay: 60.0), shouldRetry: @escaping (any Error) -> Bool = { _ in true }, onRetry: ((Int, any Error) async -> Void)? = nil)` |
| 213 | func | public | RetryPolicy.execute(_:) | `public func execute<T>(_ operation: () async throws -> T) async throws -> T where T : Sendable` |
| 271 | func | public | RetryPolicy.==(_:_:) | `public static func == (lhs: RetryPolicy, rhs: RetryPolicy) -> Bool` |

## 9. Workflow

### Workflow/Workflow+Durable.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 6 | var | public | Workflow.durable | `public var durable: Workflow.Durable { get }` |
| 8 | struct | public | Workflow.Durable | `public struct Durable` |

### Workflow/Workflow.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 89 | struct | public | Workflow | `public struct Workflow` |
| 126 | enum | public | Workflow.MergeStrategy | `public enum MergeStrategy` |
| 141 | case | public | Workflow.MergeStrategy.structured | `public case structured` |
| 158 | case | public | Workflow.MergeStrategy.indexed | `public case indexed` |
| 174 | case | public | Workflow.MergeStrategy.firstCompleted | `public case firstCompleted` |
| 182 | case | public | Workflow.MergeStrategy.first | `public case first` _(Availability: * (deprecated); renamed to firstCompleted)_ |
| 202 | case | public | Workflow.MergeStrategy.custom(_:) | `public case custom(@Sendable ([AgentResult]) -> String)` |
| 218 | func | public | Workflow.init() | `public init()` |
| 238 | func | public | Workflow.step(_:) | `public func step(_ agent: some AgentRuntime) -> Workflow` |
| 272 | func | public | Workflow.parallel(_:merge:customMergeSignature:fileID:line:) | `public func parallel(_ agents: [any AgentRuntime], merge: Workflow.MergeStrategy = .structured, customMergeSignature: String? = nil, fileID: StaticString = #fileID, line: UInt = #line) -> Workflow` |
| 325 | func | public | Workflow.route(_:signature:fileID:line:) | `public func route(_ condition: @escaping @Sendable (String) -> (any AgentRuntime)?, signature: String? = nil, fileID: StaticString = #fileID, line: UInt = #line) -> Workflow` |
| 341 | func | public | Workflow.route(signature:fileID:line:_:) | `public func route(signature: String, fileID: StaticString = #fileID, line: UInt = #line, _ condition: @escaping @Sendable (String) -> (any AgentRuntime)?) -> Workflow` |
| 377 | func | public | Workflow.repeatUntil(maxIterations:_:signature:fileID:line:) | `public func repeatUntil(maxIterations: Int = 100, _ condition: @escaping @Sendable (AgentResult) -> Bool, signature: String? = nil, fileID: StaticString = #fileID, line: UInt = #line) -> Workflow` |
| 397 | func | public | Workflow.repeatUntil(maxIterations:signature:fileID:line:_:) | `public func repeatUntil(maxIterations: Int = 100, signature: String, fileID: StaticString = #fileID, line: UInt = #line, _ condition: @escaping @Sendable (AgentResult) -> Bool) -> Workflow` |
| 423 | func | public | Workflow.timeout(_:) | `public func timeout(_ duration: Duration) -> Workflow` |
| 449 | func | public | Workflow.observed(by:) | `public func observed(by observer: some AgentObserver) -> Workflow` |
| 476 | func | public | Workflow.run(_:) | `public func run(_ input: String) async throws -> AgentResult` |
| 511 | func | public | Workflow.stream(_:) | `public func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error>` |

### Workflow/WorkflowCheckpointing.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 8 | struct | public | WorkflowCheckpointRetention | `public struct WorkflowCheckpointRetention` |
| 10 | var | public | WorkflowCheckpointRetention.default | `public static let \`default\`: WorkflowCheckpointRetention` |
| 15 | var | public | WorkflowCheckpointRetention.maxCheckpointsPerRun | `public var maxCheckpointsPerRun: Int` |
| 21 | func | public | WorkflowCheckpointRetention.init(maxCheckpointsPerRun:) | `public init(maxCheckpointsPerRun: Int = 16)` |
| 27 | struct | public | WorkflowCheckpointing | `public struct WorkflowCheckpointing` |
| 49 | func | public | WorkflowCheckpointing.inMemory() | `public static func inMemory() -> WorkflowCheckpointing` |
| 70 | func | public | WorkflowCheckpointing.fileSystem(directory:retention:) | `public static func fileSystem(directory: URL, retention: WorkflowCheckpointRetention = .default) -> WorkflowCheckpointing` |

## 10. MCP

### MCP/HTTPMCPServer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 50 | class | public | HTTPMCPServer | `public actor HTTPMCPServer` |
| 56 | var | public | HTTPMCPServer.name | `public let name: String` |
| 62 | var | public | HTTPMCPServer.capabilities | `public var capabilities: MCPCapabilities { get }` |
| 77 | func | public | HTTPMCPServer.init(url:name:apiKey:timeout:maxRetries:session:) | `public init(url: URL, name: String, apiKey: String? = nil, timeout: TimeInterval = 30.0, maxRetries: Int = 3, session: URLSession = .shared) throws` |
| 70 | var | public | HTTPMCPServer.negotiatedProtocolVersion | `public var negotiatedProtocolVersion: String? { get }` |
| 76 | var | public | HTTPMCPServer.sessionID | `public var sessionID: String? { get }` |
| 113 | func | public | HTTPMCPServer.initialize() | `public func initialize() async throws -> MCPCapabilities` |
| 142 | func | public | HTTPMCPServer.listTools() | `public func listTools() async throws -> [ToolSchema]` |
| 164 | func | public | HTTPMCPServer.callTool(name:arguments:) | `public func callTool(name: String, arguments: [String : SendableValue]) async throws -> SendableValue` |
| 180 | func | public | HTTPMCPServer.callToolRaw(name:arguments:) | `public func callToolRaw(name: String, arguments: [String : SendableValue]) async throws -> SendableValue` |
| 188 | func | public | HTTPMCPServer.listResources() | `public func listResources() async throws -> [MCPResource]` |
| 208 | func | public | HTTPMCPServer.readResource(uri:) | `public func readResource(uri: String) async throws -> MCPResourceContent` |
| 259 | func | public | HTTPMCPServer.close() | `public func close() async throws` |

### MCP/StdioMCPServer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| — | class | public | StdioMCPServer | `public actor StdioMCPServer` |
| — | func | public | StdioMCPServer.init(command:arguments:environment:workingDirectory:name:timeout:) | `public init(command: String, arguments: [String] = [], environment: [String: String]? = nil, workingDirectory: URL? = nil, name: String, timeout: TimeInterval = 30.0)` |
| — | func | public | StdioMCPServer.callToolRaw(name:arguments:) | `public func callToolRaw(name: String, arguments: [String : SendableValue]) async throws -> SendableValue` |

### MCP/MCPCapabilities.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 29 | struct | public | MCPCapabilities | `public struct MCPCapabilities` |
| 33 | var | public | MCPCapabilities.empty | `public static let empty: MCPCapabilities` |
| 39 | var | public | MCPCapabilities.tools | `public let tools: Bool` |
| 45 | var | public | MCPCapabilities.resources | `public let resources: Bool` |
| 51 | var | public | MCPCapabilities.prompts | `public let prompts: Bool` |
| 57 | var | public | MCPCapabilities.sampling | `public let sampling: Bool` |
| 68 | func | public | MCPCapabilities.init(tools:resources:prompts:sampling:) | `public init(tools: Bool = false, resources: Bool = false, prompts: Bool = false, sampling: Bool = false)` |
| 84 | var | public | MCPCapabilities.description | `public var description: String { get }` |

### MCP/MCPClient.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 56 | class | public | MCPClient | `public actor MCPClient` |
| 68 | var | public | MCPClient.connectedServers | `public var connectedServers: [String] { get }` |
| 77 | func | public | MCPClient.init() | `public init()` |
| 99 | func | public | MCPClient.addServer(_:) | `public func addServer(_ server: any MCPServerConnection) async throws` |
| 135 | func | public | MCPClient.removeServer(named:) | `public func removeServer(named name: String) async throws` |
| 174 | func | public | MCPClient.getAllTools() | `public func getAllTools() async throws -> [any AnyJSONTool]` |
| 279 | func | public | MCPClient.refreshTools() | `public func refreshTools() async throws -> [any AnyJSONTool]` |
| 295 | func | public | MCPClient.invalidateCache() | `public func invalidateCache()` |
| 340 | func | public | MCPClient.getAllResources() | `public func getAllResources() async throws -> [MCPResource]` |
| 403 | func | public | MCPClient.refreshResources() | `public func refreshResources() async throws -> [MCPResource]` |
| 425 | func | public | MCPClient.invalidateResourceCache() | `public func invalidateResourceCache()` |
| 446 | func | public | MCPClient.setResourceCacheTTL(_:) | `public func setResourceCacheTTL(_ ttl: TimeInterval)` |
| 468 | func | public | MCPClient.readResource(uri:) | `public func readResource(uri: String) async throws -> MCPResourceContent` |
| 546 | func | public | MCPClient.closeAll() | `public func closeAll() async throws` |

### MCP/MCPError.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 34 | struct | public | MCPError | `public struct MCPError` |
| 39 | var | public | MCPError.code | `public let code: Int` |
| 44 | var | public | MCPError.message | `public let message: String` |
| 50 | var | public | MCPError.data | `public let data: SendableValue?` |
| 60 | func | public | MCPError.init(code:message:data:) | `public init(code: Int, message: String, data: SendableValue? = nil)` |
| 71 | var | public | MCPError.parseErrorCode | `public static let parseErrorCode: Int` |
| 74 | var | public | MCPError.invalidRequestCode | `public static let invalidRequestCode: Int` |
| 77 | var | public | MCPError.methodNotFoundCode | `public static let methodNotFoundCode: Int` |
| 80 | var | public | MCPError.invalidParamsCode | `public static let invalidParamsCode: Int` |
| 83 | var | public | MCPError.internalErrorCode | `public static let internalErrorCode: Int` |
| 93 | func | public | MCPError.parseError(_:) | `public static func parseError(_ details: String? = nil) -> MCPError` |
| 104 | func | public | MCPError.invalidRequest(_:) | `public static func invalidRequest(_ details: String? = nil) -> MCPError` |
| 115 | func | public | MCPError.methodNotFound(_:) | `public static func methodNotFound(_ method: String? = nil) -> MCPError` |
| 128 | func | public | MCPError.invalidParams(_:) | `public static func invalidParams(_ details: String? = nil) -> MCPError` |
| 139 | func | public | MCPError.internalError(_:) | `public static func internalError(_ details: String? = nil) -> MCPError` |
| — | func | public | MCPError.unsupportedProtocolVersion(_:) | `public static func unsupportedProtocolVersion(_ version: String) -> MCPError` |
| 150 | var | public | MCPError.errorDescription | `public var errorDescription: String? { get }` |
| 162 | var | public | MCPError.debugDescription | `public var debugDescription: String { get }` |
| 176 | func | public | MCPError.init(from:) | `public init(from decoder: any Decoder) throws` |
| 183 | func | public | MCPError.encode(to:) | `public func encode(to encoder: any Encoder) throws` |

### MCP/MCPProtocol.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 43 | struct | public | MCPRequest | `public struct MCPRequest` |
| 47 | var | public | MCPRequest.jsonrpc | `public let jsonrpc: String` |
| 53 | var | public | MCPRequest.id | `public let id: String` |
| 65 | var | public | MCPRequest.method | `public let method: String` |
| 71 | var | public | MCPRequest.params | `public let params: [String : SendableValue]?` |
| 83 | func | public | MCPRequest.init(id:method:params:) | `public init(id: String = UUID().uuidString, method: String, params: [String : SendableValue]? = nil) throws` |
| 102 | func | public | MCPRequest.init(from:) | `public init(from decoder: any Decoder) throws` |
| 142 | func | public | MCPRequest.encode(to:) | `public func encode(to encoder: any Encoder) throws` |
| 187 | struct | public | MCPResponse | `public struct MCPResponse` |
| 191 | var | public | MCPResponse.jsonrpc | `public let jsonrpc: String` |
| 194 | var | public | MCPResponse.id | `public let id: String` |
| 200 | var | public | MCPResponse.result | `public let result: SendableValue?` |
| 206 | var | public | MCPResponse.error | `public let error: MCPErrorObject?` |
| 224 | func | public | MCPResponse.init(jsonrpc:id:result:error:) | `public init(jsonrpc: String = "2.0", id: String, result: SendableValue? = nil, error: MCPErrorObject? = nil) throws` |
| 249 | func | public | MCPResponse.init(from:) | `public init(from decoder: any Decoder) throws` |
| 291 | func | public | MCPResponse.encode(to:) | `public func encode(to encoder: any Encoder) throws` |
| 339 | func | public | MCPResponse.success(id:result:) | `public static func success(id: String, result: SendableValue) throws -> MCPResponse` |
| 358 | func | public | MCPResponse.failure(id:error:) | `public static func failure(id: String, error: MCPErrorObject) throws -> MCPResponse` |
| 399 | struct | public | MCPErrorObject | `public struct MCPErrorObject` |
| 405 | var | public | MCPErrorObject.code | `public let code: Int` |
| 411 | var | public | MCPErrorObject.message | `public let message: String` |
| 418 | var | public | MCPErrorObject.data | `public let data: SendableValue?` |
| 428 | func | public | MCPErrorObject.init(code:message:data:) | `public init(code: Int, message: String, data: SendableValue? = nil)` |
| 443 | func | public | MCPErrorObject.from(_:) | `public static func from(_ error: MCPError) -> MCPErrorObject` |
| 465 | var | public | MCPErrorObject.debugDescription | `public var debugDescription: String { get }` |

### MCP/MCPResource.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 24 | struct | public | MCPResource | `public struct MCPResource` |
| 29 | var | public | MCPResource.uri | `public let uri: String` |
| 35 | var | public | MCPResource.name | `public let name: String` |
| 40 | var | public | MCPResource.description | `public let description: String?` |
| 46 | var | public | MCPResource.mimeType | `public let mimeType: String?` |
| 55 | func | public | MCPResource.init(uri:name:description:mimeType:) | `public init(uri: String, name: String, description: String? = nil, mimeType: String? = nil)` |
| 92 | struct | public | MCPResourceContent | `public struct MCPResourceContent` |
| 94 | var | public | MCPResourceContent.uri | `public let uri: String` |
| 99 | var | public | MCPResourceContent.mimeType | `public let mimeType: String?` |
| 104 | var | public | MCPResourceContent.text | `public let text: String?` |
| 110 | var | public | MCPResourceContent.blob | `public let blob: String?` |
| 115 | var | public | MCPResourceContent.isText | `public var isText: Bool { get }` |
| 122 | var | public | MCPResourceContent.isBinary | `public var isBinary: Bool { get }` |
| 135 | func | public | MCPResourceContent.init(uri:mimeType:text:blob:) | `public init(uri: String, mimeType: String? = nil, text: String? = nil, blob: String? = nil) throws` |
| 153 | func | public | MCPResourceContent.init(from:) | `public init(from decoder: any Decoder) throws` |
| 189 | var | public | MCPResource.debugDescription | `public var debugDescription: String { get }` |
| 202 | var | public | MCPResourceContent.debugDescription | `public var debugDescription: String { get }` |

### MCP/MCPServer.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 90 | protocol | public | MCPServerConnection | `public protocol MCPServerConnection : Sendable` |
| 95 | var | public | MCPServerConnection.name | `public var name: String { get }` |
| 112 | var | public | MCPServerConnection.capabilities | `public var capabilities: MCPCapabilities { get async }` |
| 138 | func | public | MCPServerConnection.initialize() | `public func initialize() async throws -> MCPCapabilities` |
| 159 | func | public | MCPServerConnection.close() | `public func close() async throws` |
| 182 | func | public | MCPServerConnection.listTools() | `public func listTools() async throws -> [ToolSchema]` |
| 216 | func | public | MCPServerConnection.callTool(name:arguments:) | `public func callTool(name: String, arguments: [String : SendableValue]) async throws -> SendableValue` |
| 239 | func | public | MCPServerConnection.listResources() | `public func listResources() async throws -> [MCPResource]` |
| 265 | func | public | MCPServerConnection.readResource(uri:) | `public func readResource(uri: String) async throws -> MCPResourceContent` |
| 276 | func | public | MCPServerConnection.requireToolsCapability() | `public func requireToolsCapability() async throws` |
| 288 | func | public | MCPServerConnection.requireResourcesCapability() | `public func requireResourcesCapability() async throws` |
| — | typealias | public | MCPServer | `@available(*, deprecated, renamed: "MCPServerConnection") public typealias MCPServer = MCPServerConnection` |

### MCP/MCPToolBridge.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 36 | class | public | MCPToolBridge | `public actor MCPToolBridge` |
| 44 | func | public | MCPToolBridge.init(server:) | `public init(server: any MCPServerConnection)` |
| 69 | func | public | MCPToolBridge.bridgeTools() | `public func bridgeTools() async throws -> [any AnyJSONTool]` |

## 11. Providers

### Providers/OpenAICompatible/OpenAICompatibleProvider.swift

OpenAI-compatible Chat Completions provider (`URLSession` only). Covers OpenAI, Azure OpenAI, OpenRouter, Ollama, and LM Studio.

| Kind | Access | Name | Signature |
|------|--------|------|-----------|
| enum | public | OpenAICompatibleStructuredOutputMode | `public enum OpenAICompatibleStructuredOutputMode` |
| struct | public | OpenAICompatibleProviderConfiguration | `public struct OpenAICompatibleProviderConfiguration` |
| func | public | OpenAICompatibleProviderConfiguration.openAI(apiKey:model:) | `public static func openAI(apiKey: String, model: String = "gpt-4o") -> OpenAICompatibleProviderConfiguration` |
| func | public | OpenAICompatibleProviderConfiguration.azureOpenAI(resource:deployment:apiKey:apiVersion:model:) | `public static func azureOpenAI(resource: String, deployment: String, apiKey: String, apiVersion: String = "2024-10-21", model: String? = nil) -> OpenAICompatibleProviderConfiguration` |
| func | public | OpenAICompatibleProviderConfiguration.openRouter(apiKey:model:httpHeaders:) | `public static func openRouter(apiKey: String, model: String, httpHeaders: [String: String] = [:]) -> OpenAICompatibleProviderConfiguration` |
| func | public | OpenAICompatibleProviderConfiguration.ollama(model:baseURL:) | `public static func ollama(model: String, baseURL: URL = URL(string: "http://127.0.0.1:11434/v1")!) -> OpenAICompatibleProviderConfiguration` |
| func | public | OpenAICompatibleProviderConfiguration.lmStudio(model:baseURL:apiKey:) | `public static func lmStudio(model: String, baseURL: URL = URL(string: "http://127.0.0.1:1234/v1")!, apiKey: String? = nil) -> OpenAICompatibleProviderConfiguration` |
| struct | public | OpenAICompatibleProvider | `public struct OpenAICompatibleProvider` |
| func | public | InferenceProvider.openAICompatible(_:) | `public static func openAICompatible(_ configuration: OpenAICompatibleProviderConfiguration, session: URLSession = .shared) -> OpenAICompatibleProvider` |

### Providers/FoundationModels/FoundationModelsInferenceProvider.swift

First-class on-device Apple Foundation Models path. Gated by `#if canImport(FoundationModels)` and `@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)`.

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 16 | struct | public | FoundationModelsProviderConfiguration | `public struct FoundationModelsProviderConfiguration` |
| 24 | func | public | FoundationModelsProviderConfiguration.init(instructions:prewarmOnInit:) | `public init(instructions: String? = nil, prewarmOnInit: Bool = false)` |
| 30 | var | public | FoundationModelsProviderConfiguration.default | `public static let default: FoundationModelsProviderConfiguration` |
| 82 | struct | public | FoundationModelsInferenceProvider | `public struct FoundationModelsInferenceProvider` |
| 94 | var | public | FoundationModelsInferenceProvider.isAvailable | `public static var isAvailable: Bool { get }` |
| 99 | func | public | FoundationModelsInferenceProvider.ifAvailable(configuration:profile:) | `public static func ifAvailable(configuration: FoundationModelsProviderConfiguration = .default, profile: (any DynamicProfile)? = nil) -> FoundationModelsInferenceProvider?` |
| 112 | func | public | FoundationModelsInferenceProvider.init(configuration:profile:) | `public init(configuration: FoundationModelsProviderConfiguration = .default, profile: (any DynamicProfile)? = nil)` |
| 487 | func | public | InferenceProvider.foundationModels(configuration:) | `public static func foundationModels(configuration: FoundationModelsProviderConfiguration = .default) -> FoundationModelsInferenceProvider` |
| 493 | func | public | InferenceProvider.foundationModelsOwningToolLoop(configuration:) | `public static func foundationModelsOwningToolLoop(configuration: FoundationModelsProviderConfiguration = .default) -> FoundationModelsInferenceProvider` |
| 493 | func | public | InferenceProvider.foundationModels(instructions:prewarmOnInit:) | `public static func foundationModels(instructions: String, prewarmOnInit: Bool = false) -> FoundationModelsInferenceProvider` |
| 509 | func | public | InferenceProvider.foundationModels(profile:configuration:) | `public static func foundationModels(profile: some DynamicProfile, configuration: FoundationModelsProviderConfiguration = .default) -> FoundationModelsInferenceProvider` |

### Providers/ToolCallExecutor.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | struct | public | ToolCallExecutor | `public struct ToolCallExecutor : Sendable` |
| 15 | func | public | ToolCallExecutor.init(_:) | `public init(_ execute: @escaping @Sendable (_ name: String, _ arguments: [String : SendableValue]) async throws -> SendableValue)` |
| 29 | func | public | ToolCallExecutor.executeTool(named:arguments:) | `public func executeTool(named name: String, arguments: [String : SendableValue]) async throws -> SendableValue` |

### Providers/FoundationModels/FoundationModelsNativeTool.swift

Experimental adapter wrapping a user `FoundationModels.Tool` as a Swarm `AnyJSONTool`.

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 39 | struct | public | FoundationModelsNativeTool | `public struct FoundationModelsNativeTool` |
| 40 | var | public | FoundationModelsNativeTool.name | `public let name: String` |
| 41 | var | public | FoundationModelsNativeTool.description | `public let description: String` |
| 42 | var | public | FoundationModelsNativeTool.parameters | `public let parameters: [ToolParameter]` |
| 47 | func | public | FoundationModelsNativeTool.init(_:) | `public init<T>(_ tool: T) where T : FoundationModels.Tool` |
| 69 | func | public | FoundationModelsNativeTool.execute(arguments:) | `public func execute(arguments: [String: SendableValue]) async throws -> SendableValue` |

### Providers/FoundationModels/DynamicProfile.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 30 | struct | public | Profile | `public struct Profile` |
| 84 | enum | public | ProfileToolFilter | `public enum ProfileToolFilter` |
| 106 | struct | public | ProfileGenerationOverrides | `public struct ProfileGenerationOverrides` |
| 148 | enum | public | ProfileHistoryPolicy | `public enum ProfileHistoryPolicy` |
| 198 | struct | public | DynamicInstructions | `public struct DynamicInstructions` |
| 247 | protocol | public | DynamicProfile | `public protocol DynamicProfile` |
| 253 | struct | public | StaticDynamicProfile | `public struct StaticDynamicProfile` |
| 264 | struct | public | ClosureDynamicProfile | `public struct ClosureDynamicProfile` |
| 291 | class | public | ProfileMode | `public final class ProfileMode<Mode>` |
| 314 | struct | public | ModeSwitchingDynamicProfile | `public struct ModeSwitchingDynamicProfile<Mode>` |

### Providers/LanguageModelSession.swift

Apple's `LanguageModelSession` is not an `InferenceProvider`. Use ``FoundationModelsInferenceProvider``.

### Providers/MultiProvider.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 11 | enum | public | MultiProviderError | `public enum MultiProviderError` |
| 14 | var | public | MultiProviderError.errorDescription | `public var errorDescription: String? { get }` |
| 26 | case | public | MultiProviderError.emptyPrefix | `public case emptyPrefix` |
| 29 | case | public | MultiProviderError.providerNotFound(prefix:) | `public case providerNotFound(prefix: String)` |
| 32 | case | public | MultiProviderError.invalidModelFormat(model:) | `public case invalidModelFormat(model: String)` |
| 74 | class | public | MultiProvider | `public actor MultiProvider` |
| 78 | var | public | MultiProvider.registeredPrefixes | `public var registeredPrefixes: [String] { get }` |
| 83 | var | public | MultiProvider.providerCount | `public var providerCount: Int { get }` |
| 88 | var | public | MultiProvider.model | `public var model: String? { get }` |
| 102 | func | public | MultiProvider.init(defaultProvider:) | `public init(defaultProvider: any InferenceProvider)` |
| 118 | func | public | MultiProvider.register(prefix:provider:) | `public func register(prefix: String, provider: any InferenceProvider) throws` |
| 131 | func | public | MultiProvider.unregister(prefix:) | `public func unregister(prefix: String)` |
| 145 | func | public | MultiProvider.setModel(_:) | `public func setModel(_ model: String)` |
| 153 | func | public | MultiProvider.clearModel() | `public func clearModel()` |
| 168 | func | public | MultiProvider.generate(prompt:options:) | `public func generate(prompt: String, options: InferenceOptions) async throws -> String` |
| 181 | func | public | MultiProvider.stream(prompt:options:) | `public nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, any Error>` |
| 209 | func | public | MultiProvider.generateWithToolCalls(prompt:tools:options:) | `public func generateWithToolCalls(prompt: String, tools: [ToolSchema], options: InferenceOptions) async throws -> InferenceResponse` |
| 222 | func | public | MultiProvider.hasProvider(for:) | `public func hasProvider(for prefix: String) -> Bool` |
| 231 | func | public | MultiProvider.provider(for:) | `public func provider(for prefix: String) -> (any InferenceProvider)?` |
| 317 | var | public | MultiProvider.description | `public nonisolated var description: String { get }` |

### Providers/TextOnlyConversationInferenceProviderAdapter.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 13 | protocol | public | TextOnlyBackend | `public protocol TextOnlyBackend : Sendable` |
| 68 | struct | public | TextOnlyConversationInferenceProviderAdapter | `public struct TextOnlyConversationInferenceProviderAdapter` |
| 72 | func | public | TextOnlyConversationInferenceProviderAdapter.textOnly(_:) | `public static func textOnly(_ backend: some TextOnlyBackend) -> TextOnlyConversationInferenceProviderAdapter` |

### Providers/ToolCallStreamingInferenceProvider.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 9 | enum | public | InferenceStreamUpdate | `public enum InferenceStreamUpdate` |
| 11 | case | public | InferenceStreamUpdate.outputChunk(_:) | `public case outputChunk(String)` |
| 14 | case | public | InferenceStreamUpdate.toolCallPartial(_:) | `public case toolCallPartial(PartialToolCallUpdate)` |
| 17 | case | public | InferenceStreamUpdate.toolCallsCompleted(_:) | `public case toolCallsCompleted([InferenceResponse.ParsedToolCall])` |
| 20 | case | public | InferenceStreamUpdate.usage(_:) | `public case usage(TokenUsage)` |
| 23 | case | public | InferenceStreamUpdate.finishedTurn(_:) | `public case finishedTurn(InferenceResponse)` |
| 34 | protocol | public | ToolCallStreamingInferenceProvider | `public protocol ToolCallStreamingInferenceProvider : InferenceProvider` _(Deprecated compatibility identity; Agent reads `InferenceProviderCapabilities.streamingToolCalls`.)_ |
| 36 | func | public | ToolCallStreamingInferenceProvider.streamWithToolCalls(prompt:tools:options:) | `public func streamWithToolCalls(prompt: String, tools: [ToolSchema], options: InferenceOptions) -> AsyncThrowingStream<InferenceStreamUpdate, any Error>` |

## 12. Integration (Membrane + Wax)

### Integration/Membrane/MembraneAgentAdapter.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 8 | struct | public | MembraneFeatureConfiguration | `public struct MembraneFeatureConfiguration` |
| 9 | var | public | MembraneFeatureConfiguration.default | `public static let `default`: MembraneFeatureConfiguration` |
| 11 | var | public | MembraneFeatureConfiguration.jitMinToolCount | `public var jitMinToolCount: Int` |
| 12 | var | public | MembraneFeatureConfiguration.defaultJITLoadCount | `public var defaultJITLoadCount: Int` |
| 13 | var | public | MembraneFeatureConfiguration.pointerThresholdBytes | `public var pointerThresholdBytes: Int` |
| 14 | var | public | MembraneFeatureConfiguration.pointerSummaryMaxChars | `public var pointerSummaryMaxChars: Int` |
| 20 | var | public | MembraneFeatureConfiguration.runtimeFeatureFlags | `public var runtimeFeatureFlags: [String : Bool]` |
| 22 | var | public | MembraneFeatureConfiguration.runtimeModelAllowlist | `public var runtimeModelAllowlist: [String]` |
| 24 | func | public | MembraneFeatureConfiguration.init(jitMinToolCount:defaultJITLoadCount:pointerThresholdBytes:pointerSummaryMaxChars:runtimeFeatureFlags:runtimeModelAllowlist:) | `public init(jitMinToolCount: Int = 12, defaultJITLoadCount: Int = 6, pointerThresholdBytes: Int = 400, pointerSummaryMaxChars: Int = 240, runtimeFeatureFlags: [String : Bool] = [:], runtimeModelAllowlist: [String] = [])` |
| 41 | struct | public | MembraneEnvironment | `public struct MembraneEnvironment` |
| 42 | var | public | MembraneEnvironment.isEnabled | `public var isEnabled: Bool` |
| 43 | var | public | MembraneEnvironment.configuration | `public var configuration: MembraneFeatureConfiguration` |
| 44 | var | public | MembraneEnvironment.adapter | `public var adapter: (any MembraneAgentAdapter)?` |
| 46 | func | public | MembraneEnvironment.init(isEnabled:configuration:adapter:) | `public init(isEnabled: Bool = true, configuration: MembraneFeatureConfiguration = .default, adapter: (any MembraneAgentAdapter)? = nil)` |
| 56 | var | public | MembraneEnvironment.disabled | `public static let disabled: MembraneEnvironment` |
| 57 | var | public | MembraneEnvironment.enabled | `public static let enabled: MembraneEnvironment` |
| 60 | struct | public | MembranePlannedBoundary | `public struct MembranePlannedBoundary` |
| 61 | var | public | MembranePlannedBoundary.prompt | `public let prompt: String` |
| 62 | var | public | MembranePlannedBoundary.toolSchemas | `public let toolSchemas: [ToolSchema]` |
| 63 | var | public | MembranePlannedBoundary.mode | `public let mode: String` |
| 65 | func | public | MembranePlannedBoundary.init(prompt:toolSchemas:mode:) | `public init(prompt: String, toolSchemas: [ToolSchema], mode: String)` |
| 72 | struct | public | MembraneToolResultBoundary | `public struct MembraneToolResultBoundary` |
| 73 | var | public | MembraneToolResultBoundary.textForConversation | `public let textForConversation: String` |
| 74 | var | public | MembraneToolResultBoundary.pointerID | `public let pointerID: String?` |
| 76 | func | public | MembraneToolResultBoundary.init(textForConversation:pointerID:) | `public init(textForConversation: String, pointerID: String? = nil)` |
| 82 | enum | public | MembraneAgentAdapterError | `public enum MembraneAgentAdapterError` |
| 83 | case | public | MembraneAgentAdapterError.unsupportedInternalTool(name:) | `public case unsupportedInternalTool(name: String)` |
| 84 | case | public | MembraneAgentAdapterError.invalidInternalToolArguments(name:reason:) | `public case invalidInternalToolArguments(name: String, reason: String)` |
| 87 | protocol | public | MembraneAgentAdapter | `public protocol MembraneAgentAdapter : Sendable` |
| 88 | func | public | MembraneAgentAdapter.plan(prompt:toolSchemas:profile:) | `public func plan(prompt: String, toolSchemas: [ToolSchema], profile: ContextProfile) async throws -> MembranePlannedBoundary` |
| 94 | func | public | MembraneAgentAdapter.transformToolResult(toolName:output:) | `public func transformToolResult(toolName: String, output: String) async throws -> MembraneToolResultBoundary` |
| 99 | func | public | MembraneAgentAdapter.handleInternalToolCall(name:arguments:) | `public func handleInternalToolCall(name: String, arguments: [String : SendableValue]) async throws -> String?` |
| 104 | func | public | MembraneAgentAdapter.restore(checkpointData:) | `public func restore(checkpointData: Data?) async throws` |
| 105 | func | public | MembraneAgentAdapter.snapshotCheckpointData() | `public func snapshotCheckpointData() async throws -> Data?` |
| 108 | class | public | DefaultMembraneAgentAdapter | `public actor DefaultMembraneAgentAdapter` |
| 109 | func | public | DefaultMembraneAgentAdapter.init(configuration:) | `public init(configuration: MembraneFeatureConfiguration = .default)` |
| 132 | func | public | DefaultMembraneAgentAdapter.plan(prompt:toolSchemas:profile:) | `public func plan(prompt: String, toolSchemas: [ToolSchema], profile: ContextProfile) async throws -> MembranePlannedBoundary` |
| 190 | func | public | DefaultMembraneAgentAdapter.transformToolResult(toolName:output:) | `public func transformToolResult(toolName: String, output: String) async throws -> MembraneToolResultBoundary` |
| 218 | func | public | DefaultMembraneAgentAdapter.handleInternalToolCall(name:arguments:) | `public func handleInternalToolCall(name: String, arguments: [String : SendableValue]) async throws -> String?` |
| 289 | func | public | DefaultMembraneAgentAdapter.restore(checkpointData:) | `public func restore(checkpointData: Data?) async throws` |
| 305 | func | public | DefaultMembraneAgentAdapter.snapshotCheckpointData() | `public func snapshotCheckpointData() async throws -> Data?` |

### Integration/Wax/WaxEmbeddingProviderAdapters.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 4 | struct | public | WaxEmbeddingProviderAdapter | `public struct WaxEmbeddingProviderAdapter` |
| 5 | var | public | WaxEmbeddingProviderAdapter.base | `public let base: any EmbeddingProvider` |
| 6 | var | public | WaxEmbeddingProviderAdapter.normalize | `public let normalize: Bool` |
| 7 | var | public | WaxEmbeddingProviderAdapter.identity | `public let identity: EmbeddingIdentity?` |
| 9 | func | public | WaxEmbeddingProviderAdapter.init(_:normalize:providerName:) | `public init(_ base: any EmbeddingProvider, normalize: Bool = false, providerName: String? = "swarm")` |
| 24 | var | public | WaxEmbeddingProviderAdapter.dimensions | `public var dimensions: Int { get }` |
| 26 | func | public | WaxEmbeddingProviderAdapter.embed(_:) | `public func embed(_ text: String) async throws -> [Float]` |

### Integration/Wax/WaxIntegration.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 4 | struct | public | WaxIntegration | `public struct WaxIntegration` |
| 5 | func | public | WaxIntegration.init() | `public init()` |
| 8 | var | public | WaxIntegration.isEnabled | `public var isEnabled: Bool { get }` |
| 13 | var | public | WaxIntegration.debugDescription | `public static var debugDescription: String { get }` |

### Integration/Wax/WaxMemory.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 6 | class | public | WaxMemory | `public actor WaxMemory` |
| 10 | struct | public | WaxMemory.Configuration | `public struct Configuration` |
| 11 | var | public | WaxMemory.Configuration.default | `public static let `default`: WaxMemory.Configuration` |
| 13 | var | public | WaxMemory.Configuration.orchestratorConfig | `public var orchestratorConfig: OrchestratorConfig` |
| 14 | var | public | WaxMemory.Configuration.queryEmbeddingPolicy | `public var queryEmbeddingPolicy: MemoryOrchestrator.QueryEmbeddingPolicy` |
| 15 | var | public | WaxMemory.Configuration.tokenEstimator | `public var tokenEstimator: any TokenEstimator` |
| 16 | var | public | WaxMemory.Configuration.promptTitle | `public var promptTitle: String` |
| 17 | var | public | WaxMemory.Configuration.promptGuidance | `public var promptGuidance: String?` |
| 19 | func | public | WaxMemory.Configuration.init(orchestratorConfig:queryEmbeddingPolicy:tokenEstimator:promptTitle:promptGuidance:) | `public init(orchestratorConfig: OrchestratorConfig = .default, queryEmbeddingPolicy: MemoryOrchestrator.QueryEmbeddingPolicy = .ifAvailable, tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared, promptTitle: String = "Wax Memory Context (primary)", promptGuidance: String? = "Use Wax memory context as the primary source of truth. Prefer it before calling tools.")` |
| 34 | var | public | WaxMemory.count | `public var count: Int { get }` |
| 35 | var | public | WaxMemory.isEmpty | `public var isEmpty: Bool { get }` |
| 37 | var | public | WaxMemory.memoryPromptTitle | `public nonisolated let memoryPromptTitle: String` |
| 38 | var | public | WaxMemory.memoryPromptGuidance | `public nonisolated let memoryPromptGuidance: String?` |
| 39 | var | public | WaxMemory.memoryPriority | `public nonisolated let memoryPriority: MemoryPriorityHint` |
| 46 | func | public | WaxMemory.init(url:embedder:configuration:) | `public init(url: URL, embedder: (any EmbeddingProvider)? = nil, configuration: WaxMemory.Configuration = .default) async throws` |
| 72 | func | public | WaxMemory.add(_:) | `public func add(_ message: MemoryMessage) async` |
| 86 | func | public | WaxMemory.context(for:tokenLimit:) | `public func context(for query: String, tokenLimit: Int) async -> String` |
| 96 | func | public | WaxMemory.allMessages() | `public func allMessages() async -> [MemoryMessage]` |
| 100 | func | public | WaxMemory.clear() | `public func clear() async` |
| 121 | func | public | WaxMemory.beginMemorySession() | `public func beginMemorySession() async` |
| 126 | func | public | WaxMemory.endMemorySession() | `public func endMemorySession() async` |

## 13. Macros

### Macros/MacroDeclarations.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 99 | macro | public | Tool(_:) | `public @attached(member, names: named(name), named(description), named(parameters), named(init), named(execute), named(_userExecute), named(Input), named(Output)) @attached(extension, conformances: Tool, Sendable) macro Tool(_ description: String)` |
| 146 | macro | public | Parameter(_:default:oneOf:) | `public @attached(peer) macro Parameter(_ description: String, default defaultValue: Any? = nil, oneOf options: [String]? = nil)` |
| 188 | macro | public | AgentActor(instructions:generateBuilder:) | `public @attached(member, names: named(tools), named(instructions), named(configuration), named(memory), named(inferenceProvider), named(tracer), named(_memory), named(_defaultMemory), named(resolvedMemory), named(makeDefaultMemory), named(_inferenceProvider), named(_tracer), named(isCancelled), named(lastTokenUsage), named(init), named(run), named(stream), named(cancel), named(Builder)) @attached(extension, conformances: AgentRuntime) macro AgentActor(instructions: String, generateBuilder: Bool = true)` |
| 256 | macro | public | AgentActor(_:) | `public @attached(member, names: named(tools), named(instructions), named(configuration), named(memory), named(inferenceProvider), named(tracer), named(_memory), named(_defaultMemory), named(resolvedMemory), named(makeDefaultMemory), named(_inferenceProvider), named(_tracer), named(isCancelled), named(lastTokenUsage), named(init), named(run), named(stream), named(cancel), named(Builder)) @attached(extension, conformances: AgentRuntime) macro AgentActor(_ instructions: String)` |
| 287 | macro | public | Traceable() | `public @attached(peer, names: named(executeWithTracing)) macro Traceable()` |
| 315 | macro | public | Prompt(_:) | `public @freestanding(expression) macro Prompt(_ content: String) -> PromptString` |
| 326 | struct | public | PromptString | `public struct PromptString` |
| 329 | var | public | PromptString.content | `public let content: String` |
| 332 | var | public | PromptString.interpolations | `public let interpolations: [String]` |
| 335 | var | public | PromptString.description | `public var description: String { get }` |
| 338 | func | public | PromptString.init(content:interpolations:) | `public init(content: String, interpolations: [String] = [])` |
| 344 | func | public | PromptString.init(stringLiteral:) | `public init(stringLiteral value: String)` |
| 350 | func | public | PromptString.init(_:) | `public init(_ string: String)` |
| 395 | macro | public | Tool(_:_:) | `public @freestanding(expression) macro Tool(_ name: String, _ description: String)` |
| 465 | macro | public | Builder() | `public @attached(member, names: arbitrary) macro Builder()` |
| 471 | struct | public | PromptString.StringInterpolation | `public struct StringInterpolation` |
| 474 | func | public | PromptString.StringInterpolation.init(literalCapacity:interpolationCount:) | `public init(literalCapacity: Int, interpolationCount: Int)` |
| 479 | func | public | PromptString.StringInterpolation.appendLiteral(_:) | `public mutating func appendLiteral(_ literal: String)` |
| 483 | func | public | PromptString.StringInterpolation.appendInterpolation(_:) | `public mutating func appendInterpolation(_ value: some Any)` |
| 488 | func | public | PromptString.StringInterpolation.appendInterpolation(_:) | `public mutating func appendInterpolation(_ value: String)` |
| 493 | func | public | PromptString.StringInterpolation.appendInterpolation(_:) | `public mutating func appendInterpolation(_ value: Int)` |
| 498 | func | public | PromptString.StringInterpolation.appendInterpolation(_:) | `public mutating func appendInterpolation(_ value: [String])` |
| 509 | func | public | PromptString.init(stringInterpolation:) | `public init(stringInterpolation: PromptString.StringInterpolation)` |

## 14. Extensions

### Extensions/Extensions.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 27 | var | public | Duration.timeInterval | `public var timeInterval: TimeInterval { get }` |

## 15. Companion Products

The main catalog above is generated from `Sources/Swarm/`. The package also
exports companion products with small public entry surfaces.

### SwarmOpenTelemetry

Requires the **OpenTelemetry** SwiftPM trait (`traits: ["OpenTelemetry"]`).
Without it this product is a hollow module exposing ``OpenTelemetryTrait``.


#### Sources/SwarmOpenTelemetry/OpenTelemetryInferenceProvider.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 13 | struct | public | OpenTelemetryInferenceProvider | `public struct OpenTelemetryInferenceProvider<Base: InferenceProvider>` |
| 17 | func | public | OpenTelemetryInferenceProvider.init(_:tracer:captureContent:) | `public init(_ base: Base, tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "swarm.llm", instrumentationVersion: nil), captureContent: Bool = false)` |
| 30 | var | public | OpenTelemetryInferenceProvider.capabilities | `public var capabilities: InferenceProviderCapabilities { get }` |
| 34 | var | public | OpenTelemetryInferenceProvider.providerName | `public var providerName: String? { get }` |
| 38 | var | public | OpenTelemetryInferenceProvider.modelName | `public var modelName: String? { get }` |
| 42 | var | public | OpenTelemetryInferenceProvider.endpointURL | `public var endpointURL: URL? { get }` |
| 46 | func | public | OpenTelemetryInferenceProvider.generate(prompt:options:) | `public func generate(prompt: String, options: InferenceOptions) async throws -> String` |
| 54 | func | public | OpenTelemetryInferenceProvider.stream(prompt:options:) | `public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error>` |
| 65 | func | public | OpenTelemetryInferenceProvider.generateWithToolCalls(prompt:tools:options:) | `public func generateWithToolCalls(prompt: String, tools: [ToolSchema], options: InferenceOptions) async throws -> InferenceResponse` |
| 310 | func | public | InferenceProvider.instrumentedWithOpenTelemetry(tracer:captureContent:) | `public func instrumentedWithOpenTelemetry(tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "swarm.llm", instrumentationVersion: nil), captureContent: Bool = false) -> some InferenceProvider` |

#### Sources/SwarmOpenTelemetry/OpenTelemetryAgentRuntime.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 210 | func | public | AgentRuntime.instrumentedWithOpenTelemetry(tracer:llmTracer:spanName:captureContent:) | `public func instrumentedWithOpenTelemetry(tracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "swarm.agent", instrumentationVersion: nil), llmTracer: any OpenTelemetryApi.Tracer = OpenTelemetry.instance.tracerProvider.get(instrumentationName: "swarm.llm", instrumentationVersion: nil), spanName: String? = nil, captureContent: Bool = false) -> some AgentRuntime` |

#### Sources/SwarmOpenTelemetry/OTLPHTTPExporterConfiguration.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 30 | struct | public | OTLPHTTPExporterConfiguration | `public struct OTLPHTTPExporterConfiguration` |
| 32 | var | public | OTLPHTTPExporterConfiguration.defaultEndpoint | `public static let defaultEndpoint: URL` |
| 35 | var | public | OTLPHTTPExporterConfiguration.default | `public static let \`default\`: OTLPHTTPExporterConfiguration` |
| 72 | func | public | OTLPHTTPExporterConfiguration.init(endpoint:headers:resourceAttributes:maxBatchSize:scheduleDelay:maxRetries:retryBackoff:) | `public init(endpoint: URL = defaultEndpoint, headers: [String : String] = [:], resourceAttributes: [String : String] = ["service.name": "swarm"], maxBatchSize: Int = 64, scheduleDelay: Duration = .seconds(5), maxRetries: Int = 1, retryBackoff: Duration = .milliseconds(200))` |

#### Sources/SwarmOpenTelemetry/OTLPHTTPTraceExporter.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 30 | class | public | OTLPHTTPTraceExporter | `public final class OTLPHTTPTraceExporter` |
| 40 | func | public | OTLPHTTPTraceExporter.init(configuration:session:) | `public init(configuration: OTLPHTTPExporterConfiguration = .default, session: URLSession = .shared)` |
| 219 | enum | public | OpenTelemetryTracing | `public enum OpenTelemetryTracing` |
| 230 | func | public | OpenTelemetryTracing.configureOTLPHTTPExport(configuration:session:) | `public static func configureOTLPHTTPExport(configuration: OTLPHTTPExporterConfiguration = .default, session: URLSession = .shared) -> OTLPHTTPTraceExporter` |

#### Sources/SwarmOpenTelemetry/OpenTelemetryTracePropagation.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 22 | enum | public | OpenTelemetryTracePropagation | `public enum OpenTelemetryTracePropagation` |
| 24 | var | public | OpenTelemetryTracePropagation.currentHeaders | `public static var currentHeaders: [String : String] { get }` |
| 29 | var | public | OpenTelemetryTracePropagation.current | `public static var current: TraceContextHeaders? { get }` |
| 39 | func | public | OpenTelemetryTracePropagation.applyCurrent(to:) | `public static func applyCurrent(to request: inout URLRequest)` |

#### Sources/SwarmOpenTelemetry/SwarmTypeAliases.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 6 | typealias | public | SwarmRuntimeTracer | `public typealias SwarmRuntimeTracer = Tracer` |

### SwarmMembrane

#### Sources/SwarmMembrane/SwarmMembrane.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 1 | export | public | SwarmMembrane | `@_exported import Swarm` |

`SwarmMembrane` is a **deprecated** hollow re-export (`@_exported import Swarm`).
Import `Swarm` instead. Its user-facing symbols are the public Membrane
integration APIs cataloged in section 12 under
`Sources/Swarm/Integration/Membrane/`. The product will be removed in 0.7.0.

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 8 | enum | public | SwarmMembraneProduct | `@available(*, deprecated, message: "Import Swarm instead. SwarmMembrane is a hollow re-export and will be removed in 0.7.0.") public enum SwarmMembraneProduct: Sendable` |

### SwarmMCP

Requires the **MCP** SwiftPM trait (`traits: ["MCP"]`). Without it this product
is a hollow module exposing ``MCPTrait``.

#### Sources/SwarmMCP/SwarmMCPServerService.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 6 | actor | public | SwarmMCPServerService | `public actor SwarmMCPServerService` |
| 7 | struct | public | SwarmMCPServerService.Metrics | `public struct Metrics` |
| 17 | func | public | SwarmMCPServerService.Metrics.init(...) | `public init(listToolsRequests: Int = 0, listedToolCount: Int = 0, callToolRequests: Int = 0, callToolSuccesses: Int = 0, callToolFailures: Int = 0, approvalRequiredCount: Int = 0, approvalRejectedCount: Int = 0, cumulativeCallToolLatencyMs: Double = 0)` |
| 57 | func | public | SwarmMCPServerService.init(name:version:instructions:toolCatalog:toolExecutor:configuration:maxRequestsPerSecond:maxConcurrentRequests:) | `public init(name: String = "swarm-mcp-server", version: String = Swarm.version, instructions: String? = nil, toolCatalog: some SwarmMCPToolCatalog, toolExecutor: some SwarmMCPToolExecutor, configuration: Server.Configuration = .strict, maxRequestsPerSecond: Double = 10, maxConcurrentRequests: Int = 50)` |
| 86 | func | public | SwarmMCPServerService.start(transport:initializeHook:) | `public func start(transport: any Transport, initializeHook: (@Sendable (Client.Info, Client.Capabilities) async throws -> Void)? = nil) async throws` |
| 115 | func | public | SwarmMCPServerService.startStdio(initializeHook:) | `public func startStdio(initializeHook: (@Sendable (Client.Info, Client.Capabilities) async throws -> Void)? = nil) async throws` |
| 123 | func | public | SwarmMCPServerService.stop() | `public func stop() async` |
| 131 | func | public | SwarmMCPServerService.waitUntilCompleted() | `public func waitUntilCompleted() async` |
| 136 | func | public | SwarmMCPServerService.snapshotMetrics() | `public func snapshotMetrics() -> Metrics` |

#### Sources/SwarmMCP/SwarmMCPToolAdapter.swift

| Line | Kind | Access | Name | Signature |
|------|------|--------|------|-----------|
| 5 | protocol | public | SwarmMCPToolCatalog | `public protocol SwarmMCPToolCatalog: Sendable` |
| 11 | protocol | public | SwarmMCPToolExecutor | `public protocol SwarmMCPToolExecutor: Sendable` |
| 17 | enum | public | SwarmMCPToolExecutionError | `public enum SwarmMCPToolExecutionError` |
| 33 | actor | public | SwarmMCPToolRegistryAdapter | `public actor SwarmMCPToolRegistryAdapter` |
| 36 | func | public | SwarmMCPToolRegistryAdapter.init(registry:) | `public init(registry: ToolRegistry)` |
| 40 | func | public | SwarmMCPToolRegistryAdapter.listTools() | `public func listTools() async throws -> [ToolSchema]` |
| 44 | func | public | SwarmMCPToolRegistryAdapter.executeTool(named:arguments:) | `public func executeTool(named toolName: String, arguments: [String: SendableValue]) async throws -> SendableValue` |
