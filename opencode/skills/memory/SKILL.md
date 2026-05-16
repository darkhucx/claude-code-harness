---
name: memory
description: "管理 SSOT 与记忆，并提供跨工具的记忆检索。decisions.md 与 patterns.md 的守护者。在用户提到 memory、SSOT、decisions.md、patterns.md、合并、迁移、SSOT 升格、同步记忆、保存学习、记忆检索、harness-mem、过往决定或记录此事时使用。不用于：实现工作、评审、临时笔记或会话内日志记录。"
---

# Memory Skills

メモリとSSOT管理を担当するスキル群です。

## 機能詳細

| 機能 | 詳細 |
|------|------|
| **SSOT初期化** | See [references/ssot-initialization.md](${CLAUDE_SKILL_DIR}/references/ssot-initialization.md) |
| **Plans.mdマージ** | See [references/plans-merging.md](${CLAUDE_SKILL_DIR}/references/plans-merging.md) |
| **移行処理** | See [references/workflow-migration.md](${CLAUDE_SKILL_DIR}/references/workflow-migration.md) |
| **プロジェクト仕様同期** | See [references/sync-project-specs.md](${CLAUDE_SKILL_DIR}/references/sync-project-specs.md) |
| **メモリ→SSOT昇格** | See [references/sync-ssot-from-memory.md](${CLAUDE_SKILL_DIR}/references/sync-ssot-from-memory.md) |

## Unified Harness Memory（共通DB）

Claude Code / Codex / OpenCode 共通の記録・検索は `harness_mem_*` MCP を優先する。

- 検索: `harness_mem_search`, `harness_mem_timeline`, `harness_mem_get_observations`
- 注入: `harness_mem_resume_pack`
- 記録: `harness_mem_record_checkpoint`, `harness_mem_finalize_session`, `harness_mem_record_event`

## Claude Code 自動メモリとの関係（D22）

Harness の SSOT メモリ（Layer 2）は Claude Code の自動メモリ（Layer 1）と共存します。
自動メモリは汎用的な学習を暗黙的に記録し、SSOT はプロジェクト固有の意思決定を明示的に管理します。
Layer 1 の知見がプロジェクト全体に重要な場合、`/memory ssot` で Layer 2 に昇格してください。

詳細: [D22: 3層メモリアーキテクチャ](../../.claude/memory/decisions.md#d22-3層メモリアーキテクチャ)

## 実行手順

1. ユーザーのリクエストを分類
2. 上記の「機能詳細」から適切な参照ファイルを読む
3. その内容に従って実行

## SSOT昇格

メモリシステム（Claude-mem / Serena）から重要な学びをSSOTに永続化します。

- "**Save what we learned**" → [references/sync-ssot-from-memory.md](${CLAUDE_SKILL_DIR}/references/sync-ssot-from-memory.md)
- "**Promote decisions to SSOT**" → [references/sync-ssot-from-memory.md](${CLAUDE_SKILL_DIR}/references/sync-ssot-from-memory.md)
