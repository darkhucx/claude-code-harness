---
name: session-state
description: "Manages session state transitions per SESSION_ORCHESTRATION.md. Controls state updates at /work phase boundaries, escalated transitions on error, and initialized restoration on session resume. Internal workflow use only. Do NOT load for: user session management, login state, app state handling."
description-en: "Manages session state transitions per SESSION_ORCHESTRATION.md. Controls state updates at /work phase boundaries, escalated transitions on error, and initialized restoration on session resume. Internal workflow use only. Do NOT load for: user session management, login state, app state handling."
description-ja: "SESSION_ORCHESTRATION.md に基づくセッション状態遷移管理。/work フェーズ境界での状態更新、エラー時の escalated 遷移、セッション再開時の initialized 復帰を制御。Internal workflow use only. Do NOT load for: user session management, login state, app state handling."
description-zh: "依据 SESSION_ORCHESTRATION.md 管理会话状态迁移。控制 /work 阶段边界的状态更新、错误时的 escalated 迁移以及会话恢复时的 initialized 还原。仅供内部工作流使用。不用于：用户会话管理、登录状态、应用状态处理。"
allowed-tools: ["Read", "Bash"]
user-invocable: false
disable-model-invocation: true
---

# Session State Skill

セッション状態の遷移を管理する内部スキル。
`docs/SESSION_ORCHESTRATION.md` に定義された状態機械に従って遷移を検証・実行する。

## 機能詳細

| 機能 | 詳細 |
|------|------|
| **状態遷移** | See [references/state-transition.md](${CLAUDE_SKILL_DIR}/references/state-transition.md) |

## 使用タイミング

- `/work` フェーズ境界での状態更新
- エラー発生時の `escalated` 遷移
- セッション終了時の `stopped` 遷移
- セッション再開時の `initialized` 復帰

## 注意事項

- このスキルは内部使用専用です
- ユーザーが直接呼び出すことは想定していません
- 状態遷移ルールは `docs/SESSION_ORCHESTRATION.md` で定義
