# SwiftAgents — Agent Instructions

## Project Overview
SwiftAgents is a Swift 6.2+ framework for building AI agents (ReAct, Plan-and-Execute, tool use, memory, orchestration) targeting Apple platforms and Linux. The main package lives in `Sources/SwiftAgents` with macro support in `Sources/SwiftAgentsMacros`.

## Repo Layout
- `Sources/SwiftAgents/` — Core framework
- `Sources/SwiftAgentsMacros/` — Swift macros (@Agent, @Tool, etc.)
- `Tests/SwiftAgentsTests/` — Unit/integration tests + mocks
- `Tests/SwiftAgentsMacrosTests/` — Macro tests
- `docs/` — API docs and guides
- `scripts/` — Dev utilities (coverage)
- `SwiftSwarm-main/` — Separate sample project; avoid editing unless requested

## Build & Test
- Build: `swift build`
- Test all: `swift test`
- Test specific: `swift test --filter AgentTests`
- Coverage: `./scripts/generate-coverage-report.sh`

## Formatting & Linting
- SwiftFormat: `swift package plugin --allow-writing-to-package-directory swiftformat`
- SwiftLint: `swiftlint lint` (install via Homebrew if needed)

## Development Standards
- Swift 6.2 concurrency: prefer `async/await`, actors for shared state, `@MainActor` for UI-bound code.
- Public types must be `Sendable`.
- Prefer `struct` over `class` unless identity/mutability is required.
- Protocol-first design; fluent builders with `@discardableResult` where appropriate.
- Do not use `print()` in production code; use `Log.*` (see `Sources/SwiftAgents/Core/Logger+SwiftAgents.swift`).

## Testing Expectations (TDD Required)
- Write tests first (Red–Green–Refactor).
- Use mocks from `Tests/SwiftAgentsTests/Mocks/` for inference providers and external dependencies.
- Foundation Models may be unavailable in simulators; avoid direct dependencies in tests.

## Documentation
Update or add docs in `docs/` when changing public APIs or behavior.
