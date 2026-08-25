// AgentMacro.swift
// SwarmMacros
//
// Implementation of the @AgentActor macro for generating LegacyAgent protocol conformance.

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - AgentMacro

/// The `@AgentActor` macro generates LegacyAgent protocol conformance for an actor.
///
/// Usage:
/// ```swift
/// @AgentActor("You are a helpful assistant")
/// actor MyAgent {
///     let tools: [any AnyJSONTool] = [CalculatorTool(), DateTimeTool()]
///
///     func process(_ input: String) async throws -> String {
///         // Custom processing logic
///         return "Response"
///     }
/// }
/// ```
///
/// Generates:
/// - All LegacyAgent protocol properties with defaults
/// - Standard initializer
/// - `run()` implementation
/// - `stream()` wrapper
/// - `cancel()` implementation
/// - Builder class (optional, enabled by default)
public struct AgentMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    // swiftlint:disable:next function_body_length
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract the instructions from macro argument
        let instructions = extractInstructions(from: node) ?? ""

        // Verify this is an actor
        guard declaration.is(ActorDeclSyntax.self) else {
            throw AgentMacroError.onlyApplicableToActor
        }

        // Check for existing properties to avoid duplicates
        let existingMembers = getExistingMemberNames(from: declaration)

        var members: [DeclSyntax] = []

        // 1. Generate tools property if not present
        if !existingMembers.contains("tools") {
            members.append("""
                nonisolated public let tools: [any AnyJSONTool]
                """)
        }

        // 2. Generate instructions property
        if !existingMembers.contains("instructions") {
            members.append("""
                nonisolated public let instructions: String
                """)
        }

        // 3. Generate configuration property
        if !existingMembers.contains("configuration") {
            members.append("""
                nonisolated public let configuration: AgentConfiguration
                """)
        }

        // 4. Generate memory property
        if !existingMembers.contains("memory") {
            members.append("""
                nonisolated public var memory: (any Memory)? { _memory }
                private nonisolated let _memory: (any Memory)?
                private nonisolated let _defaultMemory: (any Memory)?

                private nonisolated func resolvedMemory() -> (any Memory)? {
                    _memory ?? AgentEnvironmentValues.current.memory ?? _defaultMemory
                }

                private static func makeDefaultMemory() -> (any Memory)? {
                    try? Agent.makeDefaultMemory()
                }
                """)
        }

        // 5. Generate inferenceProvider property
        if !existingMembers.contains("inferenceProvider") {
            members.append("""
                nonisolated public var inferenceProvider: (any InferenceProvider)? { _inferenceProvider ?? AgentEnvironmentValues.current.inferenceProvider }
                private nonisolated let _inferenceProvider: (any InferenceProvider)?
                """)
        }

        // 6. Generate tracer property
        if !existingMembers.contains("tracer") {
            members.append("""
                nonisolated public var tracer: (any Tracer)? { _tracer ?? AgentEnvironmentValues.current.tracer }
                private nonisolated let _tracer: (any Tracer)?
                """)
        }

        // 7. Generate isCancelled state
        if !existingMembers.contains("isCancelled") {
            members.append("""
                private var isCancelled: Bool = false
                """)
        }

        // 7b. Last provider-reported usage, set by `process` when available.
        if !existingMembers.contains("lastTokenUsage") {
            members.append("""
                private var lastTokenUsage: TokenUsage?
                """)
        }

        // 8. Generate initializer
        if !hasInit(in: declaration) {
            members.append("""
                public init(
                    tools: [any AnyJSONTool] = [],
                    instructions: String = \(literal: instructions),
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
                """)
        }

        // 9. Generate run() method
        if !existingMembers.contains("run") {
            let hasProcess = hasProcessMethod(in: declaration)
            if hasProcess {
                members.append("""
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
                    """)
            } else {
                members.append("""
                    public func run(
                        _ input: String,
                        session: (any Session)? = nil,
                        observer: (any AgentObserver)? = nil
                    ) async throws -> AgentResult {
                        throw AgentError.internalError(reason: "No process method implemented")
                    }
                    """)
            }
        }

        // 10. Generate stream() method
        if !existingMembers.contains("stream") {
            members.append("""
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
                """)
        }

        // 11. Generate cancel() method
        if !existingMembers.contains("cancel") {
            members.append("""
                public func cancel() async {
                    isCancelled = true
                }
                """)
        }

        // 11. Generate Builder class (enabled by default)
        // Disable with @AgentActor(instructions: "...", generateBuilder: false)
        if shouldGenerateBuilder(from: node) {
            let typeName: String
            if let actorDecl = declaration.as(ActorDeclSyntax.self) {
                typeName = actorDecl.name.text
            } else {
                typeName = "LegacyAgent"
            }
            members.append(generateBuilderClass(typeName: typeName, defaultInstructions: instructions))
        }

        return members
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only add extension for actors
        guard declaration.is(ActorDeclSyntax.self) else {
            return []
        }
        let agentExtension = try ExtensionDeclSyntax("extension \(type): AgentRuntime {}")
        return [agentExtension]
    }

    // MARK: - Helper Methods

    /// Extracts the instructions string from the macro attribute.
    /// Supports both labeled and unlabeled argument formats for backward compatibility.
    private static func extractInstructions(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        
        // Try to find labeled "instructions" argument first
        for argument in arguments {
            if argument.label?.text == "instructions",
               let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        
        // Fallback to unlabeled first argument for backward compatibility
        if let firstArg = arguments.first,
           firstArg.label == nil,
           let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            return segment.content.text
        }
        
        return nil
    }

    /// Gets names of existing members in the declaration.
    private static func getExistingMemberNames(from declaration: some DeclGroupSyntax) -> Set<String> {
        var names = Set<String>()

        for member in declaration.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        names.insert(pattern.identifier.text)
                    }
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                names.insert(funcDecl.name.text)
            }
        }

        return names
    }

    /// Checks if the declaration has an init.
    private static func hasInit(in declaration: some DeclGroupSyntax) -> Bool {
        for member in declaration.memberBlock.members where member.decl.is(InitializerDeclSyntax.self) {
            return true
        }
        return false
    }

    /// Checks if the declaration has a process method.
    private static func hasProcessMethod(in declaration: some DeclGroupSyntax) -> Bool {
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self),
               funcDecl.name.text == "process" {
                return true
            }
        }
        return false
    }

    /// Extracts the generateBuilder parameter from the macro arguments.
    static func shouldGenerateBuilder(from node: AttributeSyntax) -> Bool {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return true // Default to generating builder
        }

        for argument in arguments {
            if argument.label?.text == "generateBuilder",
               let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                return boolLiteral.literal.tokenKind == .keyword(.true)
            }
        }

        return true // Default to generating builder
    }

    /// Generates the Builder struct for the agent.
    /// Uses value semantics for Swift 6 concurrency safety.
    static func generateBuilderClass(typeName: String, defaultInstructions: String) -> DeclSyntax {
        """
        /// A fluent builder for creating \(raw: typeName) instances.
        /// Uses value semantics (struct) for Swift 6 concurrency safety.
        public struct Builder: Sendable {
            private var _tools: [any AnyJSONTool] = []
            private var _instructions: String = \(literal: defaultInstructions)
            private var _configuration: AgentConfiguration = .default
            private var _memory: (any Memory)?
            private var _inferenceProvider: (any InferenceProvider)?
            private var _tracer: (any Tracer)?

            /// Creates a new builder with default values.
            public init() {}

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
                copy._tools = tools.map { $0.asAnyJSONTool() }
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
            public func build() -> \(raw: typeName) {
                \(raw: typeName)(
                    tools: _tools,
                    instructions: _instructions,
                    configuration: _configuration,
                    memory: _memory,
                    inferenceProvider: _inferenceProvider,
                    tracer: _tracer
                )
            }
        }
        """
    }
}

// MARK: - AgentMacroError

/// Errors that can occur during @AgentActor macro expansion.
enum AgentMacroError: Error, CustomStringConvertible {
    case onlyApplicableToActor

    var description: String {
        switch self {
        case .onlyApplicableToActor:
            return "@AgentActor can only be applied to actors"
        }
    }
}
