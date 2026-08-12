# OpenTelemetry Tracing

Swarm ships OpenTelemetry support as an optional product named `SwarmOpenTelemetry`.
Use it when you want LLM requests and their underlying HTTP calls to show up in
the same distributed trace as the rest of your app.

Swarm's OpenTelemetry integration is scoped to agent turns and the LLM calls made
inside those turns:

- `agent.instrumentedWithOpenTelemetry()` creates one parent span for each
  user-facing agent operation.
- During that operation, Swarm automatically wraps the resolved
  `InferenceProvider` and emits child GenAI spans for LLM calls.

If you also want HTTP spans or `traceparent` header propagation for the
underlying LLM network requests, install OpenTelemetry Swift's
`URLSessionInstrumentation` in your application telemetry bootstrap. Swarm does
not install it for you because URLSession instrumentation is process-wide.

## Add the Package Products

If your app already configures OpenTelemetry, add only `SwarmOpenTelemetry` to the
target that creates agents:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Swarm", package: "Swarm"),
        .product(name: "SwarmOpenTelemetry", package: "Swarm"),
    ]
)
```

If the same target also configures an OTLP exporter, add the OpenTelemetry
packages directly so SwiftPM lets the app import the SDK, exporter, and optional
URLSession instrumentation modules:

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", from: "2.3.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Swarm", package: "Swarm"),
            .product(name: "SwarmOpenTelemetry", package: "Swarm"),
            .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
            .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift"),
            .product(name: "URLSessionInstrumentation", package: "opentelemetry-swift"),
        ]
    )
]
```

## Configure OpenTelemetry

Register your tracer provider once during app startup. This example exports spans
to a local OpenTelemetry Collector using OTLP/HTTP.

```swift
import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import URLSessionInstrumentation
import SwarmOpenTelemetry

private var urlSessionInstrumentation: URLSessionInstrumentation?

func configureTracing() {
    let exporter = OtlpHttpTraceExporter(
        endpoint: URL(string: "http://localhost:4318/v1/traces")!
    )

    let processor = SimpleSpanProcessor(spanExporter: exporter)

    OpenTelemetry.registerTracerProvider(
        tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: processor)
            .build()
    )

    urlSessionInstrumentation = URLSessionInstrumentation(
        configuration: URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in
                guard let host = request.url?.host else { return false }
                return host == "api.openai.com" || host == "api.anthropic.com"
            },
            shouldInjectTracingHeaders: { request in
                guard let host = request.url?.host else { return false }
                return host == "api.openai.com" || host == "api.anthropic.com"
            }
        )
    )
}
```

Keep the `URLSessionInstrumentation` instance alive for as long as you want
URLSession requests to be instrumented. The filtering closures are application
policy: decide where HTTP spans and propagated trace headers are allowed.

## Trace an Agent Run

Wrap the agent once. Swarm will instrument whichever inference provider that
agent resolves for the run.

```swift
import Swarm
import SwarmOpenTelemetry

configureTracing()

let agent = try Agent(
    "Answer briefly and use tools when useful.",
    configuration: .default.name("support-agent"),
    inferenceProvider: .foundationModels()
) {
    CalculatorTool()
}.instrumentedWithOpenTelemetry()

let result = try await agent.run("What is 18% of 245?")
print(result.output)
```

This creates:

- An agent parent span named like `swarm.agent.run support-agent`.
- Inference child spans for provider calls.
- URLSession HTTP spans for provider network requests, if your app installed URLSession instrumentation and the provider uses URLSession.
- `traceparent` and `baggage` headers on instrumented URLSession requests, if your app enabled header injection.

If one agent run makes multiple inference calls, those spans share the same
trace as the agent span. With URLSession instrumentation enabled, provider HTTP
requests made inside those spans inherit that same current trace context.

## Control Header Injection

URLSession instrumentation is global to the process, so configure it in the app
instead of in Swarm. Restrict instrumentation and header injection to the hosts
that should participate in distributed tracing:

```swift
urlSessionInstrumentation = URLSessionInstrumentation(
    configuration: URLSessionInstrumentationConfiguration(
        shouldInstrument: { request in
            guard let host = request.url?.host else { return false }
            return host == "api.openai.com" || host == "api.anthropic.com"
        },
        shouldInjectTracingHeaders: { request in
            guard let host = request.url?.host else { return false }
            return host == "api.openai.com"
        }
    )
)
```

Return `false` from `shouldInjectTracingHeaders` when you want local HTTP spans
but do not want to propagate tracing headers to an upstream provider.

## Capture Content

LLM spans record request shape, provider metadata, token usage when the provider
reports it (Foundation Models does not), output length,
and errors. They do not record prompts or model output by default.

If your deployment policy allows content capture, opt in on the agent wrapper:

```swift
let agent = try Agent(
    "Answer briefly.",
    inferenceProvider: .foundationModels()
) {}.instrumentedWithOpenTelemetry(captureContent: true)
```

`captureContent` currently marks the span with `swarm.capture_content.enabled`.
Keep prompt and response capture behind an explicit application-level policy
before adding sensitive content to span attributes or events.

## Platform Notes

Agent and LLM span wrapping works anywhere the OpenTelemetry API and Swarm
targets build.
URLSession auto-instrumentation is available when the `URLSessionInstrumentation`
module is importable by your application. On unsupported platforms, skip the
URLSession instrumentation setup and keep only the Swarm agent wrapper.
