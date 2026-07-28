# Swarm Release Checklist

## Goal

Publish a `Swarm` GitHub tag that downstream users can resolve and build without any sibling local checkouts.

## Agent-Owned Steps

1. Update release notes and changelog content.
2. Verify `Package.swift` uses the intended published dependency graph for remote consumers.
3. Run local parity verification:
   - `swift build`
   - `swift test --no-parallel`
   - `swift test --no-parallel --filter HiveSwarmTests`
   - `swift run SwarmCapabilityShowcase matrix`
   - `cd Examples/CodeReviewer && swift test`
4. Run docs verification if the Node toolchain is installed:
   - `npm ci`
   - `npm run docs:build`
   - `SWARM_CORE_ONLY=1 swift test --package-path Examples/CodeReviewer`
5. Run remote-only verification:
   - `scripts/ci/verify-remote-release.sh`
6. Confirm no compiler warnings or errors appear in the release build logs.
7. Smoke-test consumption from a clean external package after tagging.

## User-Owned Steps

1. Push the release branch to GitHub.
2. Create and push the SemVer tag.
3. Publish the GitHub release entry and release notes.

## Pre-Tag Gate

- Working tree is intentional and reviewed.
- `swift build` passes.
- `swift test --no-parallel` passes.
- `swift run SwarmCapabilityShowcase matrix` passes.
- `swift test` passes from `Examples/CodeReviewer`.
- If docs or public examples changed, `npm run docs:build` passes after `npm ci`.
- `SWARM_CORE_ONLY=1 swift test --package-path Examples/CodeReviewer` passes for core-only example resolution.
- `scripts/ci/verify-remote-release.sh` passes.
- README/examples still match the public package interface.
- If `Swarm` depends on newer published internal tags, those upstream tags already exist.

## Docs Verification

The documentation site is VitePress-backed. The CI docs job runs:

```bash
npm ci
npm run docs:build
```

The built site is written to `docs/.vitepress/dist`. For local editing:

```bash
npm run docs:dev
npm run docs:preview
```

## Optional Demos

Demo executables are not part of the default package graph. Opt into them with
`SWARM_INCLUDE_DEMO=1`:

```bash
SWARM_INCLUDE_DEMO=1 swift build
SWARM_INCLUDE_DEMO=1 swift run SwarmDemo
SWARM_INCLUDE_DEMO=1 swift run SwarmMCPServerDemo
```

## Live Smoke Requirements

`swift run SwarmCapabilityShowcase smoke` may exit successfully when live smoke
scenarios are skipped. For a release smoke pass, provide an Ollama model and
confirm the summary row says `passed live-provider-smoke`:

```bash
swift run SwarmCapabilityShowcase smoke  # requires Foundation Models on host
```

## Environment Variables

| Variable | Used By | Required For | Notes |
|---|---|---|---|
| `SWARM_INCLUDE_DEMO=1` | `Package.swift` | Demo executable build/run | Enables `SwarmDemo` and `SwarmMCPServerDemo`. |
| Foundation Models availability | Capability showcase | Live provider smoke | Skips when system model is unavailable. |
| `SWARM_RUN_LIVE_FOUNDATION_MODELS_TESTS=1` | Live Foundation Models tests | Apple on-device live tests | Live-only; not required for default CI. |
| `SWARM_RUN_SWIFTDATA_TESTS=1` | SwiftData memory/session tests | SwiftData-backed persistence checks | Apple-platform focused; default tests may skip based on environment. |
| `TAVILY_API_KEY` | Built-in web search tool | Live Tavily search | Not required for deterministic tests. |
| `AISTACK_USE_LOCAL_DEPS=0` | Release verification script | Remote dependency graph proof | Ensures sibling checkouts are not required. |
| `CONDUIT_SKIP_MLX_DEPS=1` | Release verification script | Remote release verification | Keeps optional MLX dependency resolution out of the release gate. |

## Tagging Sequence

1. Finalize the dependency graph in `Package.swift`.
2. Run `scripts/ci/verify-remote-release.sh`.
3. Tag `Swarm`.
4. Publish the GitHub release.
5. Only after that, update `Colony` to the exact new `Swarm` tag.
