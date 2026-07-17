# MultiAgentPipeline

End-to-end Swarm demo for multi-agent workflows and durable execution.

## What it shows

- Sequential `Workflow().step(...).step(...).run(...)`
- Parallel fan-out with `.parallel(..., merge: .structured)`
- Durable checkpoint + resume (`.durable.checkpoint` / `.durable.execute`)
- Optional live Foundation Models for both agents
- Deterministic `--demo` mode with scripted providers (CI-safe)

## Run

```bash
swift run MultiAgentPipeline --demo
swift run MultiAgentPipeline              # live FM when available
```

Requires macOS 26+ and a path dependency on the Swarm package (`../../`).
