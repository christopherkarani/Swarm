// AgentMacroTests.swift
// SwarmMacrosTests
//
// Tests for the @AgentActor macro expansion.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(SwarmMacros)
    import SwarmMacros

    private func agentMacros() -> [String: Macro.Type] {
        [
        "AgentActor": AgentMacro.self
        ]
    }
#endif

// MARK: - AgentMacroTests

final class AgentMacroTests: XCTestCase {
    // MARK: - Basic Agent Tests

    // swiftlint:disable:next function_body_length
    func testBasicAgentExpansion() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentActor("You are a helpful assistant")
                actor AssistantAgent {
                    func process(_ input: String) async throws -> String {
                        return "Hello!"
                    }
                }
                """,
                expandedSource: """
                actor AssistantAgent {
                    func process(_ input: String) async throws -> String {
                        return "Hello!"
                    }

                    nonisolated public let tools: [any AnyJSONTool]

                    nonisolated public let instructions: String

                    nonisolated public let configuration: AgentConfiguration

                    nonisolated public var memory: (any Memory)? {
                        _memory
                    }
                    private nonisolated let _memory: (any Memory)?
                    private nonisolated let _defaultMemory: (any Memory)?

                    private nonisolated func resolvedMemory() -> (any Memory)? {
                        _memory ?? AgentEnvironmentValues.current.memory ?? _defaultMemory
                    }

                    private static func makeDefaultMemory() -> (any Memory)? {
                        try? Agent.makeDefaultMemory()
                    }

                    nonisolated public var inferenceProvider: (any InferenceProvider)? {
                        _inferenceProvider ?? AgentEnvironmentValues.current.inferenceProvider
                    }
                    private nonisolated let _inferenceProvider: (any InferenceProvider)?

                    nonisolated public var tracer: (any Tracer)? {
                        _tracer ?? AgentEnvironmentValues.current.tracer
                    }
                    private nonisolated let _tracer: (any Tracer)?

                    private var isCancelled: Bool = false

                    private var lastTokenUsage: TokenUsage?

                    public init(
                        tools: [any AnyJSONTool] = [],
                        instructions: String = "You are a helpful assistant",
                        configuration: AgentConfiguration = .default,
                        memory: (any Memory)? = nil,
                        inferenceProvider: (any InferenceProvider)? = nil,
                        tracer: (any Tracer)? = nil
                    ) {
                        self.tools = tools
                        self.instructions = instructions
                        self.configuration = configuration
                        self._memory = memory
                        self._defaultMemory = memory == nil ? Self.makeDefaultMemory() : nil
                        self._inferenceProvider = inferenceProvider
                        self._tracer = tracer
                    }

                    public func run(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) async throws -> AgentResult {
                        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw AgentError.invalidInput(reason: "Input cannot be empty")
                        }

                        let activeTracer = tracer ?? AgentEnvironmentValues.current.tracer
                        let activeMemory = resolvedMemory()

                        let tracing = TracingHelper(
                            tracer: activeTracer,
                            agentName: configuration.name.isEmpty ? String(describing: Self.self) : configuration.name
                        )
                        await tracing.traceStart(input: input)

                        await observer?.onAgentStart(context: nil, agent: self, input: input)

                        if let activeMemory {
                            await activeMemory.beginMemorySession()
                        }

                        do {
                            isCancelled = false
                            lastTokenUsage = nil

                            // Load conversation history from session (limit to recent messages)
                            var sessionHistory: [MemoryMessage] = []
                            if let session {
                                sessionHistory = try await session.getItems(limit: configuration.sessionHistoryLimit)
                            }

                            let userMessage = MemoryMessage.user(input)

                            // Store in memory (for AI context) if available
                            if let mem = activeMemory {
                                // Seed session history only once when the memory is eligible.
                                if session != nil {
                                    await mem.seedSessionHistoryIfNeeded(sessionHistory)
                                }
                                await mem.add(userMessage)
                            }

                            let startTime = ContinuousClock.now

                            let output = try await process(input)

                            if isCancelled {
                                throw AgentError.cancelled
                            }

                            let duration = ContinuousClock.now - startTime

                            // Store turn in session (user + assistant messages)
                            if let session {
                                try await session.addItems([userMessage, .assistant(output)])
                            }

                            // Store output in memory
                            if let mem = activeMemory {
                                await mem.add(.assistant(output))
                            }

                            let result = AgentResult(
                                output: output,
                                toolCalls: [],
                                toolResults: [],
                                iterationCount: 1,
                                duration: duration,
                                tokenUsage: lastTokenUsage,
                                metadata: [:]
                            )

                            await tracing.traceComplete(result: result)
                            await observer?.onAgentEnd(context: nil, agent: self, result: result)

                            if let activeMemory {
                                await activeMemory.endMemorySession()
                            }

                            return result
                        } catch {
                            await observer?.onError(context: nil, agent: self, error: error)
                            await tracing.traceError(error)
                            if let activeMemory {
                                await activeMemory.endMemorySession()
                            }
                            throw error
                        }
                    }

                    nonisolated public func stream(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) -> AsyncThrowingStream<AgentEvent, Error> {
                        StreamHelper.makeTrackedStream(for: self) { agent, continuation in
                            do {
                                continuation.yield(.lifecycle(.started(input: input)))
                                let result = try await agent.run(input, session: session, observer: observer)
                                continuation.yield(.lifecycle(.completed(result: result)))
                                continuation.finish()
                            } catch let error as AgentError {
                                continuation.yield(.lifecycle(.failed(error: error)))
                                continuation.finish(throwing: error)
                            } catch let error as GuardrailError {
                                continuation.yield(.lifecycle(.guardrailFailed(error: error)))
                                continuation.finish(throwing: error)
                            } catch {
                                let agentError = AgentError.internalError(reason: error.localizedDescription)
                                continuation.yield(.lifecycle(.failed(error: agentError)))
                                continuation.finish(throwing: agentError)
                            }
                        }
                    }

                    public func cancel() async {
                        isCancelled = true
                    }

                    /// A fluent builder for creating AssistantAgent instances.
                    /// Uses value semantics (struct) for Swift 6 concurrency safety.
                    public struct Builder: Sendable {
                        private var _tools: [any AnyJSONTool] = []
                        private var _instructions: String = "You are a helpful assistant"
                        private var _configuration: AgentConfiguration = .default
                        private var _memory: (any Memory)?
                        private var _inferenceProvider: (any InferenceProvider)?
                        private var _tracer: (any Tracer)?

                        /// Creates a new builder with default values.
                        public init() {
                        }

                        /// Sets the tools for the agent.
                        public func tools(_ tools: [any AnyJSONTool]) -> Builder {
                            var copy = self
                            copy._tools = tools
                            return copy
                        }

                        /// Adds a tool to the agent's tool set.
                        public func addTool(_ tool: some AnyJSONTool) -> Builder {
                            var copy = self
                            copy._tools.append(tool)
                            return copy
                        }

                        /// Sets typed tools for the agent (bridged to AnyJSONTool).
                        public func tools<T: Tool>(_ tools: [T]) -> Builder {
                            var copy = self
                            copy._tools = tools.map {
                                $0.asAnyJSONTool()
                            }
                            return copy
                        }

                        /// Adds a typed tool to the agent's tool set (bridged to AnyJSONTool).
                        public func addTool<T: Tool>(_ tool: T) -> Builder {
                            var copy = self
                            copy._tools.append(tool.asAnyJSONTool())
                            return copy
                        }

                        /// Sets the instructions for the agent.
                        public func instructions(_ instructions: String) -> Builder {
                            var copy = self
                            copy._instructions = instructions
                            return copy
                        }

                        /// Sets the configuration for the agent.
                        public func configuration(_ configuration: AgentConfiguration) -> Builder {
                            var copy = self
                            copy._configuration = configuration
                            return copy
                        }

                        /// Sets the memory system for the agent.
                        public func memory(_ memory: any Memory) -> Builder {
                            var copy = self
                            copy._memory = memory
                            return copy
                        }

                        /// Sets the inference provider for the agent.
                        public func inferenceProvider(_ provider: any InferenceProvider) -> Builder {
                            var copy = self
                            copy._inferenceProvider = provider
                            return copy
                        }

                        /// Sets the tracer for the agent.
                        public func tracer(_ tracer: any Tracer) -> Builder {
                            var copy = self
                            copy._tracer = tracer
                            return copy
                        }

                        /// Builds the agent with the configured values.
                        public func build() -> AssistantAgent {
                            AssistantAgent(
                                tools: _tools,
                                instructions: _instructions,
                                configuration: _configuration,
                                memory: _memory,
                                inferenceProvider: _inferenceProvider,
                                tracer: _tracer
                            )
                        }
                    }
                }

                extension AssistantAgent: AgentRuntime {
                }
                """,
                macros: agentMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // swiftlint:disable:next function_body_length
    func testAgentWithExistingTools() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentActor("Math assistant")
                actor MathAgent {
                    nonisolated public let tools: [any AnyJSONTool]

                    func process(_ input: String) async throws -> String {
                        return "Calculated!"
                    }
                }
                """,
                expandedSource: """
                actor MathAgent {
                    nonisolated public let tools: [any AnyJSONTool]

                    func process(_ input: String) async throws -> String {
                        return "Calculated!"
                    }

                    nonisolated public let instructions: String

                    nonisolated public let configuration: AgentConfiguration

                    nonisolated public var memory: (any Memory)? {
                        _memory
                    }
                    private nonisolated let _memory: (any Memory)?
                    private nonisolated let _defaultMemory: (any Memory)?

                    private nonisolated func resolvedMemory() -> (any Memory)? {
                        _memory ?? AgentEnvironmentValues.current.memory ?? _defaultMemory
                    }

                    private static func makeDefaultMemory() -> (any Memory)? {
                        try? Agent.makeDefaultMemory()
                    }

                    nonisolated public var inferenceProvider: (any InferenceProvider)? {
                        _inferenceProvider ?? AgentEnvironmentValues.current.inferenceProvider
                    }
                    private nonisolated let _inferenceProvider: (any InferenceProvider)?

                    nonisolated public var tracer: (any Tracer)? {
                        _tracer ?? AgentEnvironmentValues.current.tracer
                    }
                    private nonisolated let _tracer: (any Tracer)?

                    private var isCancelled: Bool = false

                    private var lastTokenUsage: TokenUsage?

                    public init(
                        tools: [any AnyJSONTool] = [],
                        instructions: String = "Math assistant",
                        configuration: AgentConfiguration = .default,
                        memory: (any Memory)? = nil,
                        inferenceProvider: (any InferenceProvider)? = nil,
                        tracer: (any Tracer)? = nil
                    ) {
                        self.tools = tools
                        self.instructions = instructions
                        self.configuration = configuration
                        self._memory = memory
                        self._defaultMemory = memory == nil ? Self.makeDefaultMemory() : nil
                        self._inferenceProvider = inferenceProvider
                        self._tracer = tracer
                    }

                    public func run(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) async throws -> AgentResult {
                        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw AgentError.invalidInput(reason: "Input cannot be empty")
                        }

                        let activeTracer = tracer ?? AgentEnvironmentValues.current.tracer
                        let activeMemory = resolvedMemory()

                        let tracing = TracingHelper(
                            tracer: activeTracer,
                            agentName: configuration.name.isEmpty ? String(describing: Self.self) : configuration.name
                        )
                        await tracing.traceStart(input: input)

                        await observer?.onAgentStart(context: nil, agent: self, input: input)

                        if let activeMemory {
                            await activeMemory.beginMemorySession()
                        }

                        do {
                            isCancelled = false
                            lastTokenUsage = nil

                            // Load conversation history from session (limit to recent messages)
                            var sessionHistory: [MemoryMessage] = []
                            if let session {
                                sessionHistory = try await session.getItems(limit: configuration.sessionHistoryLimit)
                            }

                            let userMessage = MemoryMessage.user(input)

                            // Store in memory (for AI context) if available
                            if let mem = activeMemory {
                                // Seed session history only once when the memory is eligible.
                                if session != nil {
                                    await mem.seedSessionHistoryIfNeeded(sessionHistory)
                                }
                                await mem.add(userMessage)
                            }

                            let startTime = ContinuousClock.now

                            let output = try await process(input)

                            if isCancelled {
                                throw AgentError.cancelled
                            }

                            let duration = ContinuousClock.now - startTime

                            // Store turn in session (user + assistant messages)
                            if let session {
                                try await session.addItems([userMessage, .assistant(output)])
                            }

                            // Store output in memory
                            if let mem = activeMemory {
                                await mem.add(.assistant(output))
                            }

                            let result = AgentResult(
                                output: output,
                                toolCalls: [],
                                toolResults: [],
                                iterationCount: 1,
                                duration: duration,
                                tokenUsage: lastTokenUsage,
                                metadata: [:]
                            )

                            await tracing.traceComplete(result: result)
                            await observer?.onAgentEnd(context: nil, agent: self, result: result)

                            if let activeMemory {
                                await activeMemory.endMemorySession()
                            }

                            return result
                        } catch {
                            await observer?.onError(context: nil, agent: self, error: error)
                            await tracing.traceError(error)
                            if let activeMemory {
                                await activeMemory.endMemorySession()
                            }
                            throw error
                        }
                    }

                    nonisolated public func stream(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) -> AsyncThrowingStream<AgentEvent, Error> {
                        StreamHelper.makeTrackedStream(for: self) { agent, continuation in
                            do {
                                continuation.yield(.lifecycle(.started(input: input)))
                                let result = try await agent.run(input, session: session, observer: observer)
                                continuation.yield(.lifecycle(.completed(result: result)))
                                continuation.finish()
                            } catch let error as AgentError {
                                continuation.yield(.lifecycle(.failed(error: error)))
                                continuation.finish(throwing: error)
                            } catch let error as GuardrailError {
                                continuation.yield(.lifecycle(.guardrailFailed(error: error)))
                                continuation.finish(throwing: error)
                            } catch {
                                let agentError = AgentError.internalError(reason: error.localizedDescription)
                                continuation.yield(.lifecycle(.failed(error: agentError)))
                                continuation.finish(throwing: agentError)
                            }
                        }
                    }

                    public func cancel() async {
                        isCancelled = true
                    }

                    /// A fluent builder for creating MathAgent instances.
                    /// Uses value semantics (struct) for Swift 6 concurrency safety.
                    public struct Builder: Sendable {
                        private var _tools: [any AnyJSONTool] = []
                        private var _instructions: String = "Math assistant"
                        private var _configuration: AgentConfiguration = .default
                        private var _memory: (any Memory)?
                        private var _inferenceProvider: (any InferenceProvider)?
                        private var _tracer: (any Tracer)?

                        /// Creates a new builder with default values.
                        public init() {
                        }

                        /// Sets the tools for the agent.
                        public func tools(_ tools: [any AnyJSONTool]) -> Builder {
                            var copy = self
                            copy._tools = tools
                            return copy
                        }

                        /// Adds a tool to the agent's tool set.
                        public func addTool(_ tool: some AnyJSONTool) -> Builder {
                            var copy = self
                            copy._tools.append(tool)
                            return copy
                        }

                        /// Sets typed tools for the agent (bridged to AnyJSONTool).
                        public func tools<T: Tool>(_ tools: [T]) -> Builder {
                            var copy = self
                            copy._tools = tools.map {
                                $0.asAnyJSONTool()
                            }
                            return copy
                        }

                        /// Adds a typed tool to the agent's tool set (bridged to AnyJSONTool).
                        public func addTool<T: Tool>(_ tool: T) -> Builder {
                            var copy = self
                            copy._tools.append(tool.asAnyJSONTool())
                            return copy
                        }

                        /// Sets the instructions for the agent.
                        public func instructions(_ instructions: String) -> Builder {
                            var copy = self
                            copy._instructions = instructions
                            return copy
                        }

                        /// Sets the configuration for the agent.
                        public func configuration(_ configuration: AgentConfiguration) -> Builder {
                            var copy = self
                            copy._configuration = configuration
                            return copy
                        }

                        /// Sets the memory system for the agent.
                        public func memory(_ memory: any Memory) -> Builder {
                            var copy = self
                            copy._memory = memory
                            return copy
                        }

                        /// Sets the inference provider for the agent.
                        public func inferenceProvider(_ provider: any InferenceProvider) -> Builder {
                            var copy = self
                            copy._inferenceProvider = provider
                            return copy
                        }

                        /// Sets the tracer for the agent.
                        public func tracer(_ tracer: any Tracer) -> Builder {
                            var copy = self
                            copy._tracer = tracer
                            return copy
                        }

                        /// Builds the agent with the configured values.
                        public func build() -> MathAgent {
                            MathAgent(
                                tools: _tools,
                                instructions: _instructions,
                                configuration: _configuration,
                                memory: _memory,
                                inferenceProvider: _inferenceProvider,
                                tracer: _tracer
                            )
                        }
                    }
                }

                extension MathAgent: AgentRuntime {
                }
                """,
                macros: agentMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

// MARK: - AgentMacroTests Error Cases

extension AgentMacroTests {
    // MARK: - Error Cases

    func testAgentOnlyAppliesToActor() throws {
        #if canImport(SwarmMacros)
            assertMacroExpansion(
                """
                @AgentActor("Invalid")
                struct InvalidAgent {
                    func process(_ input: String) async throws -> String {
                        return ""
                    }
                }
                """,
                expandedSource: """
                struct InvalidAgent {
                    func process(_ input: String) async throws -> String {
                        return ""
                    }
                }
                """,
                diagnostics: [
                    DiagnosticSpec(message: "@AgentActor can only be applied to actors", line: 1, column: 1)
                ],
                macros: agentMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // swiftlint:disable:next function_body_length
    func testAgentWithoutProcessMethod() throws {
        #if canImport(SwarmMacros)
            // Agent without process method should still compile but run() throws
            assertMacroExpansion(
                """
                @AgentActor("No process method")
                actor IncompleteAgent {
                }
                """,
                expandedSource: """
                actor IncompleteAgent {

                    nonisolated public let tools: [any AnyJSONTool]

                    nonisolated public let instructions: String

                    nonisolated public let configuration: AgentConfiguration

                    nonisolated public var memory: (any Memory)? {
                        _memory
                    }
                    private nonisolated let _memory: (any Memory)?
                    private nonisolated let _defaultMemory: (any Memory)?

                    private nonisolated func resolvedMemory() -> (any Memory)? {
                        _memory ?? AgentEnvironmentValues.current.memory ?? _defaultMemory
                    }

                    private static func makeDefaultMemory() -> (any Memory)? {
                        try? Agent.makeDefaultMemory()
                    }

                    nonisolated public var inferenceProvider: (any InferenceProvider)? {
                        _inferenceProvider ?? AgentEnvironmentValues.current.inferenceProvider
                    }
                    private nonisolated let _inferenceProvider: (any InferenceProvider)?

                    nonisolated public var tracer: (any Tracer)? {
                        _tracer ?? AgentEnvironmentValues.current.tracer
                    }
                    private nonisolated let _tracer: (any Tracer)?

                    private var isCancelled: Bool = false

                    private var lastTokenUsage: TokenUsage?

                    public init(
                        tools: [any AnyJSONTool] = [],
                        instructions: String = "No process method",
                        configuration: AgentConfiguration = .default,
                        memory: (any Memory)? = nil,
                        inferenceProvider: (any InferenceProvider)? = nil,
                        tracer: (any Tracer)? = nil
                    ) {
                        self.tools = tools
                        self.instructions = instructions
                        self.configuration = configuration
                        self._memory = memory
                        self._defaultMemory = memory == nil ? Self.makeDefaultMemory() : nil
                        self._inferenceProvider = inferenceProvider
                        self._tracer = tracer
                    }

                    public func run(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) async throws -> AgentResult {
                        throw AgentError.internalError(reason: "No process method implemented")
                    }

                    nonisolated public func stream(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) -> AsyncThrowingStream<AgentEvent, Error> {
                        StreamHelper.makeTrackedStream(for: self) { agent, continuation in
                            do {
                                continuation.yield(.lifecycle(.started(input: input)))
                                let result = try await agent.run(input, session: session, observer: observer)
                                continuation.yield(.lifecycle(.completed(result: result)))
                                continuation.finish()
                            } catch let error as AgentError {
                                continuation.yield(.lifecycle(.failed(error: error)))
                                continuation.finish(throwing: error)
                            } catch let error as GuardrailError {
                                continuation.yield(.lifecycle(.guardrailFailed(error: error)))
                                continuation.finish(throwing: error)
                            } catch {
                                let agentError = AgentError.internalError(reason: error.localizedDescription)
                                continuation.yield(.lifecycle(.failed(error: agentError)))
                                continuation.finish(throwing: agentError)
                            }
                        }
                    }

                    public func cancel() async {
                        isCancelled = true
                    }

                    /// A fluent builder for creating IncompleteAgent instances.
                    /// Uses value semantics (struct) for Swift 6 concurrency safety.
                    public struct Builder: Sendable {
                        private var _tools: [any AnyJSONTool] = []
                        private var _instructions: String = "No process method"
                        private var _configuration: AgentConfiguration = .default
                        private var _memory: (any Memory)?
                        private var _inferenceProvider: (any InferenceProvider)?
                        private var _tracer: (any Tracer)?

                        /// Creates a new builder with default values.
                        public init() {
                        }

                        /// Sets the tools for the agent.
                        public func tools(_ tools: [any AnyJSONTool]) -> Builder {
                            var copy = self
                            copy._tools = tools
                            return copy
                        }

                        /// Adds a tool to the agent's tool set.
                        public func addTool(_ tool: some AnyJSONTool) -> Builder {
                            var copy = self
                            copy._tools.append(tool)
                            return copy
                        }

                        /// Sets typed tools for the agent (bridged to AnyJSONTool).
                        public func tools<T: Tool>(_ tools: [T]) -> Builder {
                            var copy = self
                            copy._tools = tools.map {
                                $0.asAnyJSONTool()
                            }
                            return copy
                        }

                        /// Adds a typed tool to the agent's tool set (bridged to AnyJSONTool).
                        public func addTool<T: Tool>(_ tool: T) -> Builder {
                            var copy = self
                            copy._tools.append(tool.asAnyJSONTool())
                            return copy
                        }

                        /// Sets the instructions for the agent.
                        public func instructions(_ instructions: String) -> Builder {
                            var copy = self
                            copy._instructions = instructions
                            return copy
                        }

                        /// Sets the configuration for the agent.
                        public func configuration(_ configuration: AgentConfiguration) -> Builder {
                            var copy = self
                            copy._configuration = configuration
                            return copy
                        }

                        /// Sets the memory system for the agent.
                        public func memory(_ memory: any Memory) -> Builder {
                            var copy = self
                            copy._memory = memory
                            return copy
                        }

                        /// Sets the inference provider for the agent.
                        public func inferenceProvider(_ provider: any InferenceProvider) -> Builder {
                            var copy = self
                            copy._inferenceProvider = provider
                            return copy
                        }

                        /// Sets the tracer for the agent.
                        public func tracer(_ tracer: any Tracer) -> Builder {
                            var copy = self
                            copy._tracer = tracer
                            return copy
                        }

                        /// Builds the agent with the configured values.
                        public func build() -> IncompleteAgent {
                            IncompleteAgent(
                                tools: _tools,
                                instructions: _instructions,
                                configuration: _configuration,
                                memory: _memory,
                                inferenceProvider: _inferenceProvider,
                                tracer: _tracer
                            )
                        }
                    }
                }

                extension IncompleteAgent: AgentRuntime {
                }
                """,
                macros: agentMacros()
            )
        #else
            throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
