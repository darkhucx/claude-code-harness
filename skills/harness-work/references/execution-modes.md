# Execution Modes

`harness-work` chooses the lightest execution mode that still preserves review
and validation.

## Shared Preflight

1. Read `Plans.md` and identify the selected task set.
2. Stop if the task table lacks `Task`, `DoD`, `Depends`, or `Status`.
3. Resolve helper scripts through `HARNESS_PLUGIN_ROOT`, not the caller
   project's `scripts/` directory.
4. Mark only the selected task as `cc:WIP`.
5. Generate and approve a sprint contract before implementation when the task
   needs reviewable DoD checks.

## Solo

Use for one task. The parent session implements directly, validates, runs the
review loop, commits unless `--no-commit` is set, and marks `Plans.md`
`cc:完了 [hash]`.

## Parallel

Use for two or three independent tasks, or when `--parallel N` is explicit.
Workers may use isolated worktrees when file ownership can conflict. The Lead
still owns final integration and status updates.

## Codex

Use only when `--codex` is explicit. Delegate implementation to the Codex
companion entrypoint:

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write "task"
```

Validate the result locally. Codex output is not accepted until the normal
review loop approves it.

## Breezing

Use for four or more tasks, or when `--breezing` is explicit. Lead coordinates
Workers, Advisor, and Reviewer while preserving the implementation/review
boundary.

Codex-native Breezing reads this flow through `spawn_agent`, `send_input`,
`wait_agent`, and `close_agent` rather than Claude Code `Agent` /
`SendMessage` pseudo-code.
