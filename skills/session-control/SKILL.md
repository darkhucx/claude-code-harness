---
name: session-control
description: "/work のセッション resume/fork(branch) を --resume/--fork フラグに基づいて制御。session.json と session.events.jsonl を更新する内部ワークフロー専用スキル。Do NOT load for: user session management, login state, app state handling."
description-en: "Controls session resume/fork(branch) for /work based on --resume/--fork flags. Updates session.json and session.events.jsonl. Internal workflow use only. Do NOT load for: user session management, login state, app state handling."
description-ja: "/work のセッション resume/fork(branch) を --resume/--fork フラグに基づいて制御。session.json と session.events.jsonl を更新する内部ワークフロー専用スキル。Do NOT load for: user session management, login state, app state handling."
description-zh: "依据 --resume/--fork 标志控制 /work 的会话 resume/fork(branch)。更新 session.json 与 session.events.jsonl。仅供内部工作流使用。不用于：用户会话管理、登录状态、应用状态处理。"
allowed-tools: ["Read", "Bash", "Write", "Edit"]
user-invocable: false
---

# Session Control Skill

/work の `--resume` / `--fork` フラグに応じてセッション状態を切り替える。

## 機能詳細

| 機能 | 詳細 |
|------|------|
| **セッション再開/分岐** | See [references/session-control.md](${CLAUDE_SKILL_DIR}/references/session-control.md) |

## 実行手順

1. workflow から渡された変数を確認
2. `scripts/session-control.sh` を適切な引数で実行
3. `session.json` と `session.events.jsonl` の更新を確認
