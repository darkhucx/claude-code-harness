# Project Spec SSOT Workflow

Plans.md is the task ledger. A project spec SSOT is the product contract.

This distinction matters because a task can be well written while the project
meaning is still vague. If the product behavior, domain terms, data ownership,
API contract, security boundary, or non-goal is not written anywhere stable,
implementation can drift even when every Plans.md task is completed.

## Default Location

Prefer an existing project-level specification if one already exists:

- `docs/spec/00-project-spec.md`
- `docs/ARCHITECTURE.md`
- `docs/HANDOFF.md`
- `docs/oem/PROJECT_COMPASS.md`
- a clearly named product or domain spec under `docs/specs/`

If no stronger local convention exists, create:

```text
docs/spec/00-project-spec.md
```

## When To Create Or Update It

Create or update a spec SSOT before implementation when any of these are true:

- The task introduces or changes user-visible product behavior.
- The task changes API, data model, permissions, billing, tenant boundaries, or
  integration contracts.
- Multiple implementation choices are plausible and would create different
  product behavior.
- A reviewer, worker, or user has already seen implementation drift from unclear
  requirements.
- The task spans several modules and needs shared terms or invariants.
- Plans.md contains what to do, but not what "correct" means for the project.

## When To Skip

Do not create a new spec for purely mechanical work:

- typo fixes
- formatting
- dependency bumps without behavior change
- local CI/test repair with no product decision
- README/CHANGELOG-only updates
- narrow refactors that preserve existing behavior and have clear tests

If skipping could surprise a later implementer, write the skip reason in the
task context or sprint contract.

## Minimum Content

Keep the first spec short. It only needs enough structure to prevent drift.

```markdown
# Project Spec

## Purpose
What this project is for, in one paragraph.

## Users And Workflows
Who uses it, and the main workflows they expect.

## Core Rules
The product rules that implementation must not violate.

## Data And Contracts
Important data shapes, API contracts, integrations, and ownership boundaries.

## Non-Goals
Things the project intentionally does not do.

## Open Decisions
Unknowns that must be resolved before implementation can rely on them.

## Links
- Plans.md task or phase:
- Related briefs:
- Related decisions:
```

## Relationship To Plans.md

Plans.md should link to the spec when a task depends on project-level behavior.

Example:

```markdown
| 4.2 | Add tenant invite flow (spec: docs/spec/00-project-spec.md#tenant-rules) | invite API rejects cross-tenant roles in tests | 4.1 | cc:TODO |
```

The spec does not replace DoD. DoD still says how the task is judged complete.
The spec says what the implementation must stay consistent with.

## Review Rule

Reviewers should treat a direct contradiction of the spec SSOT as a major issue.
If the spec is missing and the task needed one, that is a planning gap, not a
reason to invent behavior during implementation.
