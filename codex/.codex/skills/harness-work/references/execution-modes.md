# Codex Execution Modes

Codex `harness-work` uses native Codex tools where Claude Code would use
Agent/Task tool wording.

## Shared Preflight

1. Read `Plans.md`.
2. Stop on old table formats that lack `Task`, `DoD`, `Depends`, or `Status`.
3. Resolve helper scripts from the Harness plugin root.
4. Keep implementation and review separate.

## Solo

Use the current Codex session for one task. Validate locally and run the normal
review loop before completion.

## Parallel / Breezing

Use Codex native subagents:

- `spawn_agent`
- `send_input`
- `wait_agent`
- `close_agent`

Default Breezing worker count is `max`, meaning the number of ready tasks whose
dependencies are already satisfied. It is not unlimited spawning.

## Companion Delegation

Use the companion script only through the resolved plugin root:

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write "task"
```
