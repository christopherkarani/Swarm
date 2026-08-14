# OpenTelemetry Tracing

Swarm ships OpenTelemetry support as an optional product named `SwarmOpenTelemetry`.
Use it when you want agent turns and LLM calls to export as OTLP spans and to
propagate W3C `traceparent` on outbound HTTP.

Swarm's OpenTelemetry integration is scoped to agent turns and the LLM calls made
inside those turns:

- `agent.instrumentedWithOpenTelemetry()` creates one parent span for each
  user-facing agent operation.
- During that operation, Swarm automatically wraps the resolved
  `InferenceProvider` and emits child GenAI spans for LLM calls.
- `OTLPHTTPTraceExporter` posts those spans to an OTLP/HTTP collector as JSON.
  There is no gRPC dependency.
- W3C `traceparent` (and `tracestate` when present) is injected from the current
  span into built-in Web tool HTTP requests. Custom providers call
  `TraceContextHeaders.applyCurrent(to:)` or
  `OpenTelemetryTracePropagation.applyCurrent(to:)`.

## Add the Package Product

If your app already configures OpenTelemetry, add `SwarmOpenTelemetry` to the
target that creates agents. Swarm `0.6.0` is the current published tag:

```swift
.package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.6.0")

.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Swarm", package: "Swarm"),
        .product(name: "SwarmOpenTelemetry", package: "Swarm"),
    ]
)
```

`SwarmOpenTelemetry` already depends on OpenTelemetry API + SDK
(`opentelemetry-swift-core`). You do **not** need the first-party
`OpenTelemetryProtocolExporterHTTP` package (that one pulls gRPC). Swarm's
in-house exporter speaks OTLP/HTTP JSON over `URLSession`.

## Configure export

Register a tracer provider once during app startup. This example exports spans
to a local OpenTelemetry Collector at the default OTLP/HTTP traces endpoint
(`http://localhost:4318/v1/traces`):

```swift
import SwarmOpenTelemetry

func configureTracing() {
    OpenTelemetryTracing.configureOTLPHTTPExport(
        configuration: .default
            .headers(["Authorization": "Bearer collector-token"])
    )
}
```

Or wire the exporter yourself if you already own the tracer provider:

```swift
import OpenTelemetryApi
import OpenTelemetrySdk
import SwarmOpenTelemetry

func configureTracing() {
    let exporter = OTLPHTTPTraceExporter(
        configuration: .default
            .endpoint(URL(string: "http://localhost:4318/v1/traces")!)
            .headers(["Authorization": "Bearer collector-token"])
            .maxBatchSize(64)
            .scheduleDelay(.seconds(5))
    )

    OpenTelemetry.registerTracerProvider(
        tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter))
            .build()
    )
}
```

### What exports

Each finished agent and LLM span is POSTed as OTLP/JSON `resourceSpans`. Resource
attributes include `service.name` (default `swarm`) plus any values you set on
`OTLPHTTPExporterConfiguration.resourceAttributes`. Span attributes include the
fields Swarm already records:

- Agent: `swarm.operation.name`, `swarm.agent.name`, `swarm.request.input_length`,
  `swarm.response.output_length`, `swarm.iterations.count`, tool-call counts,
  and `gen_ai.usage.*` when the provider reports tokens.
- LLM: `gen_ai.operation.name`, `gen_ai.request.*`, `gen_ai.provider.name`,
  `gen_ai.request.model`, `server.address` / `url.full` when metadata is present,
  and `error.type` on failure.

Batching is size- and timer-based. Transient failures (HTTP 5xx and network
errors) retry once by default; HTTP 4xx is not retried.

## Local collector

A minimal Collector config that accepts OTLP/HTTP JSON and prints spans:

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
processors:
  batch: {}
exporters:
  debug:
    verbosity: detailed
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [debug]
```

```bash
docker run --rm -p 4318:4318 \
  -v "$(pwd)/otel-collector.yaml:/etc/otelcol/config.yaml" \
  otel/opentelemetry-collector:latest
```

## Trace an agent run

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
- Inference child spans for provider calls, sharing the agent trace.
- An OTLP/HTTP JSON export of those spans to your collector.
- `traceparent` (and `tracestate` when present) on built-in Web tool HTTP
  requests made inside the active span.

## Propagate trace context

Swarm injects W3C headers from the **current** span. The format is exactly
`{version}-{trace-id}-{parent-id}-{flags}` (lowercase hex), for example
`00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`.

Built-in Web fetches and Tavily search apply `TraceContextHeaders.current`
automatically. Custom providers — including a future remote OpenAI-compatible
provider — should do the same:

```swift
import Swarm

var request = URLRequest(url: endpoint)
TraceContextHeaders.applyCurrent(to: &request)
```

If you already import `SwarmOpenTelemetry`, this is equivalent and also reads
the active OTel span directly:

```swift
import SwarmOpenTelemetry

var request = URLRequest(url: endpoint)
OpenTelemetryTracePropagation.applyCurrent(to: &request)
```

Swarm does **not** install process-wide `URLSessionInstrumentation`. If you also
want HTTP *spans* (not just header injection) for arbitrary `URLSession` traffic,
add OpenTelemetry Swift's URLSession instrumentation in your app bootstrap and
restrict it to the hosts you intend to trace. That module is optional and is
not required for Swarm's own export or `traceparent` propagation.

## Capture content

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

## Metrics without a manual tracer

`MetricsCollector` can attach from configuration so execution counters flow
without passing a tracer:

```swift
let config = AgentConfiguration.default
    .autoAttachMetricsCollector(true)

let agent = try Agent(
    "Answer briefly.",
    configuration: config,
    inferenceProvider: .foundationModels()
)

_ = try await agent.run("Hello")
let snapshot = await agent.metricsCollector?.snapshot()
```

The flag defaults to `false`.

## Platform notes

Agent and LLM span wrapping, OTLP/HTTP JSON export, and W3C header helpers work
anywhere the OpenTelemetry API/SDK and Swarm targets build, including Linux.
URLSession auto-instrumentation for extra HTTP spans remains an optional
application concern and is not shipped by Swarm.
