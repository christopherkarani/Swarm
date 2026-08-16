# Agent Instructions

## Public Repository Hygiene

This is the front-facing Swarm GitHub repository. Keep tracked files limited to
source code, tests, examples, public documentation, release tooling, and CI.

Do not add or re-track internal planning, audit, marketing, or assistant
workspace artifacts. In particular, keep these paths out of Git:

- `tasks/`
- `.claude/`
- `.agent_context.md`
- `.mcp.json`
- `docs/plans/`
- `docs/prompts/`
- `docs/superpowers/`
- `docs/work-packages/`
- `docs/validation/`
- `marketing/`
- `website/`
- `IMPLEMENTATION_PLAN.md`
- `HIVE_EXTENSIBILITY_INTEGRATION_PLAN.md`
- `PRODUCTION_READINESS_AUDIT.md`
- `docs/reference/*audit-report.md`
- `docs/reference/documentation-*-report.md`
- `docs/reference/documentation-improvement-plan.md`
- `docs/reference/api-quality-assessment.md`
- `docs/reference/twitter-article-*.md`
- `docs/swarm-hacker-news-blog.md`

If a task requires one of those artifacts, keep it local only. Before staging,
run `git status --short` and make sure none of the paths above are staged. If a
future cleanup finds one tracked again, remove it from Git instead of editing it
as public documentation.

## Development Rules

- Preserve unrelated dirty worktree changes.
- Keep edits surgical and matched to the requested behavior.
- Use tests for behavioral changes.
- For public API changes, update source DocC and the remaining public reference
  docs: `README.md`, `docs/guide/*`, `docs/reference/overview.md`,
  `docs/reference/front-facing-api.md`, and `docs/reference/api-catalog.md`.
