// IntentMacros.swift
// SwarmAppIntents
//
// Public declarations for the @IntentTool and @AgentIntent macros.

#if SWARM_MACROS && canImport(AppIntents)
import AppIntents

// MARK: - @IntentTool

/// Exposes a `@Tool` struct to Siri, Shortcuts, Spotlight, and Apple
/// Intelligence by generating a nested `Intent` type that conforms to
/// `AppIntent`.
///
/// Define the tool once; agents call it through Swarm, and the system calls it
/// through App Intents.
///
/// ```swift
/// import SwarmAppIntents
///
/// @Tool("Gets the current weather for a city")
/// @IntentTool("Get Weather")
/// struct WeatherTool {
///     @Parameter("City name")
///     var city: String
///
///     @Parameter("Temperature units", oneOf: ["celsius", "fahrenheit"])
///     var units: String = "celsius"
///
///     func execute() async throws -> String {
///         "22° and sunny in \(city)"
///     }
/// }
///
/// // In your agent:
/// let agent = try Agent("You help with travel.") { WeatherTool() }
///
/// // For Siri / Shortcuts:
/// struct Shortcuts: AppShortcutsProvider {
///     static var appShortcuts: [AppShortcut] {
///         AppShortcut(
///             intent: WeatherTool.Intent(),
///             phrases: ["Check the weather in \(.applicationName)"],
///             shortTitle: "Weather",
///             systemImageName: "cloud.sun"
///         )
///     }
/// }
/// ```
///
/// ## What is generated
///
/// `WeatherTool.Intent` has:
/// - `title` from the macro argument (or derived from the type name:
///   `WeatherTool` → "Weather") and `description` from `@Tool`,
/// - one `@Parameter` per tool `@Parameter`, with a human-readable title
///   (`includeForecast` → "Include Forecast"), the tool's parameter
///   description, and its default value,
/// - a `DynamicOptionsProvider` for each `@Parameter(oneOf:)`,
/// - `perform()`, which runs the tool through ``SwarmIntentBridge`` (applying
///   argument normalization and tool guardrails) and returns the rendered
///   output as both a `String` value for Shortcuts and a Siri dialog.
///
/// ## Requirements
///
/// - The struct must also be annotated with `@Tool`, must not be generic, and
///   must be constructible with `init()` (which `@Tool` generates unless you
///   write your own initializer).
/// - Parameter types must be `String`, `Int`, `Double`, `Float` (exposed as
///   `Double`), `Bool`, arrays of those, or optionals of those.
///
/// - Parameters:
///   - title: The action name shown in Shortcuts and spoken by Siri. Defaults
///     to a name derived from the type.
///   - description: Overrides the `@Tool` description in Shortcuts.
@attached(member, names: named(Intent))
public macro IntentTool(
    _ title: String? = nil,
    description: String? = nil
) = #externalMacro(module: "SwarmMacros", type: "IntentToolMacro")

// MARK: - @AgentIntent

/// Turns a struct into an `AppIntent` that sends the user's request to a
/// Swarm agent.
///
/// ```swift
/// import SwarmAppIntents
///
/// @AgentIntent("Plan a Trip", description: "Plans weekend trips using live weather")
/// struct PlanTripIntent {
///     static func makeAgent() throws -> some AgentRuntime {
///         try Agent("You plan weekend trips.") { WeatherTool() }
///     }
/// }
/// ```
///
/// The struct gains `AppIntent` conformance, a `title`, an optional
/// `description`, a required `prompt` parameter, and a `perform()` that builds
/// the agent with `makeAgent()` and returns its output as a Shortcuts value and
/// a Siri dialog.
///
/// `makeAgent()` must be `static`, take no arguments, and return an
/// `AgentRuntime`. It may be `async` and/or `throws`. It runs once per request.
///
/// To expose several agents through a single intent instead, register them in
/// ``SwarmAgentDirectory`` and use ``AskSwarmAgentIntent``.
///
/// - Parameters:
///   - title: The action name shown in Shortcuts and spoken by Siri.
///   - description: Optional longer description shown in Shortcuts.
///   - promptTitle: The label of the request parameter. Defaults to "Request".
@attached(
    member,
    names: named(title), named(description), named(prompt), named(init), named(perform)
)
@attached(extension, conformances: AppIntent)
public macro AgentIntent(
    _ title: String,
    description: String? = nil,
    promptTitle: String = "Request"
) = #externalMacro(module: "SwarmMacros", type: "AgentIntentMacro")
#endif
