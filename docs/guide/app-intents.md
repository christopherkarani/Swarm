# App Intents: Siri, Shortcuts, and Apple Intelligence

`SwarmAppIntents` turns Swarm tools and agents into App Intents with one
annotation. You define a tool once: your agents call it through Swarm, and
Siri, Shortcuts, Spotlight, and Apple Intelligence call it through App Intents.

```swift
.product(name: "SwarmAppIntents", package: "Swarm")
```

```swift
import SwarmAppIntents   // re-exports Swarm and AppIntents
```

The App Intents surface (macros, `SwarmAgentEntity`, `AskSwarmAgentIntent`)
is available on iOS, macOS, and tvOS. The runtime bridge
(`SwarmIntentBridge`, `SwarmAgentDirectory`) also builds on Linux, so you can
unit-test it there.

## Expose a tool: `@IntentTool`

Add `@IntentTool` next to `@Tool`:

```swift
@Tool("Gets the current weather for a city")
@IntentTool("Get Weather")
struct WeatherTool {
    @Parameter("City name")
    var city: String = ""

    @Parameter("Temperature units", oneOf: ["celsius", "fahrenheit"])
    var units: String = "celsius"

    func execute() async throws -> String {
        "22° and sunny in \(city)"
    }
}
```

That generates `WeatherTool.Intent`, an `AppIntent` that:

- uses the macro argument as its title, or derives one from the type name
  (`WeatherTool` → "Weather"), and uses the `@Tool` description,
- mirrors each `@Parameter` as an App Intents parameter with a readable title
  (`includeForecast` → "Include Forecast"), the parameter description, and
  its default,
- turns each `@Parameter(oneOf:)` into a picker via `DynamicOptionsProvider`,
- runs the tool through `SwarmIntentBridge` and returns the output both as a
  `String` that Shortcuts can pass on and as the dialog Siri speaks.

Make it reachable by voice with an `AppShortcutsProvider`:

```swift
struct WeatherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WeatherTool.Intent(),
            phrases: ["Check the weather in \(.applicationName)"],
            shortTitle: "Weather",
            systemImageName: "cloud.sun"
        )
    }
}
```

The same tool still works in an agent, unchanged:

```swift
let agent = try Agent("You help plan trips.") { WeatherTool() }
```

### Parameter mapping

| Tool parameter | Intent parameter |
|---|---|
| `String`, `Int`, `Double`, `Bool` | same type |
| `Float` | `Double` (converted back when the tool runs) |
| `[T]` of the above | `[T]` |
| `T?` | `T?` (optional; omitted arguments use the tool default) |
| `@Parameter(oneOf:)` | `String` with a `DynamicOptionsProvider` |
| `@Parameter(default: x)` or `= x` | `default: x` |

`@Tool` needs an initial value on every stored property, so an empty
placeholder (`= ""` or `= []`) is treated as "no default". Siri asks for
that value instead of running the tool with an empty string. Use
`@Parameter("…", default: "")` if you really want an empty default.

Nested arrays, arrays of optionals, and anything `@Tool` itself rejects are
compile errors.

### What runs when Siri calls the tool

`SwarmIntentBridge.run(_:arguments:)` executes the tool through a
`ToolRegistry`. That means argument normalization, defaults, `isEnabled`, and
tool input and output guardrails all apply, exactly as when an agent calls the
tool. Failures become `SwarmIntentError`, which conforms to
`CustomLocalizedStringResourceConvertible` so Siri can read out the reason.

Output rendering: strings are returned as they are, numbers and booleans use
their usual spelling, `null` becomes "Done.", and structured output becomes
pretty-printed JSON with sorted keys. To present it differently, write your
own `AppIntent` and call `SwarmIntentBridge` from `perform()`.

### Requirements

- The struct needs `@Tool`, can't be generic, and must be constructible with
  `init()`. `@Tool` generates `init()` unless you write your own initializer.
- The generated type is named `Intent`, so don't declare another nested type
  with that name.

## Expose an agent: `@AgentIntent`

```swift
@AgentIntent("Plan a Trip", description: "Plans weekend trips using live weather")
struct PlanTripIntent {
    static func makeAgent() throws -> some AgentRuntime {
        try Agent("You plan weekend trips.") { WeatherTool() }
    }
}
```

The struct gains `AppIntent` conformance, a `title`, an optional
`description`, a required `prompt` parameter, and a `perform()` that builds
the agent and returns its final output. `makeAgent()` must be `static`, take
no arguments, and return an `AgentRuntime`. It can be `async` and/or
`throws`, and it runs once per request. Use `promptTitle:` to rename the
request parameter (it defaults to "Request").

The agent resolves its inference provider the usual way. On device that
normally means Apple Foundation Models. If your app calls
`Swarm.configure(provider:)`, make sure that also happens when the system
launches the app in the background to run an intent.

## Expose many agents: `SwarmAgentEntity`

If you'd rather have one intent for every assistant, register the agents in
`SwarmAgentDirectory`. Each one becomes a `SwarmAgentEntity`, an `AppEntity`
that Siri and Shortcuts can list, search, and pick from.
`AskSwarmAgentIntent` takes an assistant and a request:

```swift
@main
struct MyApp: App {
    init() {
        SwarmAgentDirectory.shared.register(
            id: "travel",
            name: "Travel Planner",
            summary: "Plans trips with live weather"
        ) {
            try Agent("You plan weekend trips.") { WeatherTool() }
        }
    }

    var body: some Scene { WindowGroup { ContentView() } }
}

// Let the system index the intents and entities defined in SwarmAppIntents.
struct MyAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [SwarmAppIntentsPackage.self]
    }
}
```

Keep `id` stable across releases, because Shortcuts stores it. Factories run
for each request, so state is never shared between runs.

## Name clashes with `@Parameter`

Inside a type that conforms to `AppIntent`, `@Parameter` refers to App
Intents' property wrapper. Everywhere else it refers to Swarm's macro. The
generated code always spells out `@AppIntents.IntentParameter`, so the two
never get mixed up. If you write your own `AppIntent` in a file that imports
Swarm and the compiler reports an ambiguity, write `@IntentParameter`.

## Testing

`SwarmIntentBridge` and `SwarmAgentDirectory` don't depend on App Intents.
Call `SwarmIntentBridge.run(MyTool(), arguments: [...])` in a unit test to
check exactly what Siri would get back.
