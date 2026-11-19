// SwarmIntentBridge.swift
// SwarmAppIntents
//
// Platform-independent runtime used by code that @IntentTool / @AgentIntent
// generate. Everything here builds on Linux so it can be unit-tested without
// the AppIntents framework.

import Foundation
@_exported import Swarm

// MARK: - SwarmIntentBridge

/// Runs Swarm tools and agents on behalf of App Intents.
///
/// `@IntentTool` and `@AgentIntent` generate `perform()` methods that call into
/// this type. You can also call it from a hand-written `AppIntent` when you
/// need full control over the intent's shape:
///
/// ```swift
/// struct LookUpOrderIntent: AppIntent {
///     static let title: LocalizedStringResource = "Look Up Order"
///
///     @Parameter(title: "Order Number")
///     var orderNumber: String
///
///     func perform() async throws -> some IntentResult & ReturnsValue<String> {
///         let text = try await SwarmIntentBridge.run(
///             OrderLookupTool(),
///             arguments: ["orderNumber": .string(orderNumber)]
///         )
///         return .result(value: text)
///     }
/// }
/// ```
///
/// Tools are executed through a ``ToolRegistry``, so argument normalization,
/// defaults, ``AnyJSONTool/isEnabled``, and tool input/output guardrails apply
/// exactly as they do when an agent calls the tool.
public enum SwarmIntentBridge {
    /// Executes `tool` with `arguments` and renders the result as text.
    ///
    /// - Parameters:
    ///   - tool: The typed Swarm tool to run.
    ///   - arguments: Tool arguments keyed by parameter name. Missing optional
    ///     parameters fall back to the tool's declared defaults.
    /// - Returns: The tool output rendered by ``render(_:)``.
    /// - Throws: ``SwarmIntentError/toolFailed(toolName:reason:)`` when the tool,
    ///   its arguments, or its guardrails reject the call; `CancellationError`
    ///   when the intent is cancelled.
    public static func run<T: Tool>(
        _ tool: T,
        arguments: [String: SendableValue]
    ) async throws -> String {
        let toolName = tool.name
        do {
            let registry = try ToolRegistry(tools: [tool])
            let value = try await registry.execute(toolNamed: toolName, arguments: arguments)
            return render(value)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SwarmIntentError.toolFailed(toolName: toolName, reason: SwarmIntentError.reason(for: error))
        }
    }

    /// Sends `prompt` to `agent` and returns the agent's final output.
    ///
    /// - Parameters:
    ///   - agent: Any Swarm agent runtime (for example an ``Agent``).
    ///   - prompt: The user's natural-language request.
    /// - Returns: ``AgentResult/output``.
    /// - Throws: ``SwarmIntentError/agentFailed(reason:)`` when the run fails;
    ///   `CancellationError` when the intent is cancelled.
    public static func run(agent: some AgentRuntime, prompt: String) async throws -> String {
        do {
            return try await agent.run(prompt).output
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SwarmIntentError.agentFailed(reason: SwarmIntentError.reason(for: error))
        }
    }

    /// Renders a tool result as human-readable text for Siri and Shortcuts.
    ///
    /// Strings are returned verbatim, scalars use their natural spelling,
    /// `null` becomes `"Done."`, and arrays/dictionaries become pretty-printed
    /// JSON with sorted keys.
    public static func render(_ value: SendableValue) -> String {
        switch value {
        case .null:
            return "Done."
        case let .string(text):
            return text
        case let .bool(flag):
            return String(flag)
        case let .int(number):
            return String(number)
        case let .double(number):
            return String(number)
        case .array, .dictionary:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
                return text
            }
            return value.description
        }
    }
}

// MARK: - SwarmIntentError

/// An error surfaced to Siri / Shortcuts when a bridged tool or agent fails.
///
/// On Apple platforms this type also conforms to
/// `CustomLocalizedStringResourceConvertible`, so Siri speaks the message
/// instead of a generic failure.
public enum SwarmIntentError: Error, Sendable, Equatable, LocalizedError {
    /// The named tool failed, rejected its arguments, or was blocked by a guardrail.
    case toolFailed(toolName: String, reason: String)
    /// The agent run failed.
    case agentFailed(reason: String)
    /// No agent is registered in ``SwarmAgentDirectory`` under this identifier.
    case agentNotFound(id: String)

    public var errorDescription: String? {
        switch self {
        case let .toolFailed(toolName, reason):
            "The \(toolName) action failed: \(reason)"
        case let .agentFailed(reason):
            "The assistant couldn't complete the request: \(reason)"
        case let .agentNotFound(id):
            "No assistant named \"\(id)\" is available."
        }
    }

    static func reason(for error: any Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

// MARK: - Argument conversion

/// A value that an App Intents parameter can hand to a Swarm tool.
///
/// `@IntentTool` converts each intent parameter with
/// ``SwarmIntentArgument/encode(_:)``. `nil` means "omit the argument" so the
/// tool's declared default applies.
public protocol SwarmIntentArgumentConvertible {
    /// The `SendableValue` for this value, or `nil` to omit the argument.
    var swarmIntentValue: SendableValue? { get }
}

/// Converts App Intents parameter values into Swarm tool arguments.
public enum SwarmIntentArgument {
    /// Returns the tool argument for `value`, or `nil` to omit it.
    public static func encode<Value: SwarmIntentArgumentConvertible>(_ value: Value) -> SendableValue? {
        value.swarmIntentValue
    }
}

extension String: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? { .string(self) }
}

extension Int: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? { .int(self) }
}

extension Double: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? { .double(self) }
}

extension Float: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? { .double(Double(self)) }
}

extension Bool: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? { .bool(self) }
}

extension Array: SwarmIntentArgumentConvertible where Element: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? {
        .array(map { $0.swarmIntentValue ?? .null })
    }
}

extension Optional: SwarmIntentArgumentConvertible where Wrapped: SwarmIntentArgumentConvertible {
    public var swarmIntentValue: SendableValue? {
        flatMap(\.swarmIntentValue)
    }
}
