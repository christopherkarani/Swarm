# Agent Workspace

`AgentWorkspace` is the on-device file-backed workflow for Swarm. It gives you one place for:

- workspace-wide instructions with `AGENTS.md`
- per-agent specs under `.swarm/agents/`
- reusable standard `SKILL.md` skills under `.swarm/skills/`
- durable writable notes under `.swarm/memory/`

The goal is simple: a developer should be able to drop in `AGENTS.md` and standard `SKILL.md` files and have them work without custom wiring.

## Quick Start

```swift
import Swarm

let workspace = try AgentWorkspace.appDefault()

let supportAgent = try Agent.spec(
    "support",
    in: workspace,
    inferenceProvider: .foundationModels()
)

let result = try await supportAgent.run("I need help with a refund.")
print(result.output)
```

For a code-first agent that still uses workspace memory:

```swift
let workspace = try AgentWorkspace.appDefault()

let agent = try Agent.onDevice(
    "You are a concise on-device assistant.",
    workspace: workspace,
    inferenceProvider: .foundationModels()
)
```

## Layout

Swarm expects one canonical workspace layout:

```text
AgentWorkspace/
  AGENTS.md
  .swarm/
    agents/
      support.md
      reviewer.md
    skills/
      refund-policy/
        SKILL.md
        references/
        scripts/
        assets/
    memory/
      facts/
      decisions/
      tasks/
      lessons/
      handoffs/
```

Default locations:

- bundled files: `Bundle.main/AgentWorkspace/`
- writable notes: `Application Support/<bundle-id>/AgentWorkspace/`
- index/cache files: `Caches/<bundle-id>/AgentWorkspace/`

If you need custom paths, use the explicit initializer:

```swift
let workspace = try AgentWorkspace(
    bundleRoot: bundledWorkspaceURL,
    writableRoot: writableWorkspaceURL,
    indexCacheRoot: cacheURL
)
```

## File Scopes

### `AGENTS.md`

- one file per workspace
- applies to every agent in that workspace
- plain markdown
- if front matter exists, Swarm ignores it and uses the markdown body

Use `AGENTS.md` for:

- product boundaries
- safety rules
- tone and response style
- shared platform constraints

### Agent Specs

Agent specs live in `.swarm/agents/<agent-id>.md`.

Required front matter:

```yaml
---
schema_version: 1
id: support
title: Support
skills:
  - refund-policy
revision: 1
updated_at: 2026-03-20T00:00:00Z
---
```

The markdown body is the agent-specific instruction block.

Example:

```md
---
schema_version: 1
id: support
title: Support
skills:
  - refund-policy
revision: 1
updated_at: 2026-03-20T00:00:00Z
---
You are the support agent. Ask for order details before deciding next steps.
```

### `SKILL.md`

Swarm follows the standard skill folder shape:

```text
.swarm/skills/refund-policy/SKILL.md
```

Required fields:

```yaml
---
name: refund-policy
description: Handle refund and return questions
---
```

Optional standard fields that Swarm reads:

- `compatibility`
- `allowed-tools`
- `metadata`

Swarm-specific tuning belongs under namespaced metadata keys:

```yaml
---
name: refund-policy
description: Handle refund and return questions
compatibility:
  - Swarm
metadata:
  swarm.on-device-optimized: true
  swarm.priority: high
---
```

`SKILL.md` bodies are not treated as top-level instructions. Swarm retrieves them as secondary context only when the agent spec allows that skill and the current query matches it.

### Durable Memory Notes

Durable notes live under `.swarm/memory/` and are written through `WorkspaceWriter`.

Kinds:

- `facts`
- `decisions`
- `tasks`
- `lessons`
- `handoffs`

Example:

```swift
let writer = workspace.makeWriter()
try await writer.recordFact(
    title: "Customer refund policy",
    content: "Orders can be refunded within 30 days of purchase.",
    tags: ["support", "refunds"]
)
```

## Prompt Order

Swarm keeps prompt trust order fixed:

1. system/app instructions
2. `AGENTS.md`
3. agent spec body
4. retrieved `SKILL.md` snippets
5. retrieved workspace memory snippets

This means workspace memory is helpful, but it does not outrank shipped app instructions or the agent spec.

## Session vs Memory

`Session` and workspace memory are different systems:

- `Session` stores chat history
- `WorkspaceMemory` stores durable markdown knowledge

Swarm does not auto-copy chat transcripts into workspace markdown.

## Validation

Use `validate()` during development and CI:

```swift
let report = try await workspace.validate()
guard report.isValid else {
    for issue in report.issues {
        print("\(issue.path): \(issue.message)")
    }
    fatalError("Workspace validation failed")
}
```

Validation catches:

- malformed front matter
- missing required fields
- missing `SKILL.md`
- skill directory and skill name mismatches
- invalid agent specs

Runtime behavior is strict for listed specs/skills and tolerant for memory notes:

- invalid listed `SKILL.md` files fail `Agent.spec`
- bad specs fail when you try to build that agent
- malformed memory notes are skipped and logged
- malformed memory notes are left in place and reported by `validate()`
- missing `AGENTS.md` is allowed

## Error Handling

Swarm is strict about `SKILL.md` and agent specs, but permissive about `AGENTS.md`.

Examples:

- invalid `SKILL.md` front matter: skill is skipped and validation reports it
- missing `description` in `SKILL.md`: validation failure
- missing `AGENTS.md`: workspace still loads
- malformed markdown in `AGENTS.md`: treated as plain text when readable

## Privacy and Storage

The workspace feature is on-device first:

- bundled specs and skills are read from the app bundle
- durable notes are written to app-managed storage
- the runtime never gives agents arbitrary filesystem access
- `WorkspaceMemory` is for durable context, not transcript replay

Recommended reset controls in app UI:

- `Clear Session`
- `Clear Workspace Memory`
- `Export Memory`
- `Import Memory`

## Troubleshooting

If `Agent.spec(...)` fails, check these first:

- the spec file is in `.swarm/agents/<id>.md`
- the front matter contains `schema_version`, `id`, `title`, `skills`, `revision`, and `updated_at`
- every listed skill exists at `.swarm/skills/<skill-name>/SKILL.md`
- the skill folder name matches the `name` inside `SKILL.md`

If a skill loads but never appears in prompts:

- make sure the spec lists that skill
- make sure the query actually matches the skill body or description
- run `workspace.validate()` and fix any reported issues first

## On-Device Defaults

`AgentConfiguration.onDeviceDefault` is tuned for platform defaults:

- iPhone, iPad, tvOS: strict 4k context mode and shorter session replay
- macOS: platform default context profile and moderate session replay

When memory supports `MemoryQuery`, Swarm passes:

- total memory token budget
- max retrieved item count
- max per-item token budget

That keeps skill and memory retrieval bounded instead of dumping full markdown files into the prompt.
