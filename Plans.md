# Claude Code Harness — Plans.md

最終アーカイブ: 2026-05-07（Phase 47〜62 → `.claude/memory/archive/Plans-2026-05-07-phase47-62.md`）
前回アーカイブ: 2026-04-19（Phase 44 + 45 + 46 → `.claude/memory/archive/Plans-2026-04-19-phase44-46.md`）

---

## 📦 アーカイブ

完了済み Phase は以下のファイルへ切り出し済み（git history にも残存）:

- [Phase 47〜62](.claude/memory/archive/Plans-2026-05-07-phase47-62.md) — CLAUDE.md 調査 / Session Monitor / XR-003 / active-watching 規約 / upstream 追従 (CC 2.1.99-2.1.126) / English default / Codex Breezing / skill orchestration / harness-mem companion / sandbagging weak-supervision / zh i18n (v4.7.0)
- [Phase 44 + 45 + 46](.claude/memory/archive/Plans-2026-04-19-phase44-46.md) — Opus 4.7 / CC 2.1.99-110 追従 "Arcana" (v4.2.0) + Plugin Manifest 公式準拠 + Worker 3 層防御 (#84-#87, v4.3.0)
- [Phase 37 + 41 + 42 + 43](.claude/memory/archive/Plans-2026-04-17-phase37-41-42-43.md) — Hokage 完全体 / Long-Running Harness / Go hot-path migration / Advisor Strategy
- [Phase 39 + 40 + 41.0](.claude/memory/archive/Plans-2026-04-15-phase39-40-41.0.md) — レビュー体験改善 / Migration Residue Scanner / Long-Running Harness Spike

---

## 🔖 Status マーカー凡例

PM ↔ Impl 運用で使用する標準マーカー:

| マーカー | 意味 | 誰が付ける |
|---------|------|-----------|
| `pm:依頼中` | PM がタスクを起票し、Impl へ依頼中 | PM |
| `cc:WIP` | Impl（Claude Code）が着手中 | Impl |
| `cc:完了` | Impl が作業完了し、PM の確認待ち | Impl |
| `pm:確認済` | PM が最終確認を完了 | PM |

**状態遷移**: `pm:依頼中 → cc:WIP → cc:完了 → pm:確認済`

**後方互換**: `cursor:依頼中` / `cursor:確認済` は `pm:依頼中` / `pm:確認済` の同義として扱う（Cursor PM 運用時の表記）。

---

## Phase 63: Codex auth — 仿 Gemini auth 交互认证流程 [P2]

Purpose: `codex-companion.sh` に `auth` サブコマンドを追加し、`gemini auth` と対称的な体験を提供する。ユーザーは API Key を手動で設定ファイルに書かず、`auth` コマンドで対話的に設定・確認・削除できる。

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 63.1 | `scripts/codex-companion.sh` に `auth` / `auth status` / `auth logout` サブコマンドを追加する。`auth` は対話式で OpenAI API Key を入力させ `~/.codex/config.toml` に書き込む（パーミッション 600、既存値があれば上書き確認）。`auth status` は設定済みキーの末尾4文字と設定日時を表示。`auth logout` はキーを削除してファイルから除去する | (a) `bash scripts/codex-companion.sh auth` で API Key を入力すると `~/.codex/config.toml` に書き込まれる、(b) ファイルパーミッションが 600 になる、(c) `auth status` で `configured (****XXXX, 2026-05-07)` 形式で表示される、(d) `auth logout` でキーが削除される、(e) Codex CLI が `~/.codex/config.toml` を自動読み込みし `setup --json` が成功する | - | cc:完了 [02bff5a] |
| 63.2 | `tests/test-codex-auth.sh` を新規作成する。auth / status / logout の 3 フローをモック環境で検証する。実際の API Key は使わず、ダミー値 `sk-test-xxxx` で動作を確認する | (a) `auth` → ファイル書き込み・権限 600 の検証、(b) `auth status` → 末尾4文字マスク表示の検証、(c) `auth logout` → ファイルからキー削除の検証、(d) `bash tests/test-codex-auth.sh` が PASS、(e) `./tests/validate-plugin.sh` が PASS を維持 | 63.1 | cc:完了 [7f2f66d] |

---

## Phase 64: Ollama ローカルモデル対応 — OpenAI 互換 API でタスク処理 [P2]

Purpose: Ollama の OpenAI 互換エンドポイント (`http://localhost:11434/v1`) を使い、小タスクをローカル AI に委託できるようにする。`codex-companion.sh` / `gemini-companion.sh` と対称的な `ollama-companion.sh` を実装し、`harness-work --ollama` フラグでタスクを振り分ける。将来的には複雑度スコアによる自動ルーティングも追加する。

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 64.1 | `scripts/ollama-companion.sh` を新規作成する。`task "..."` / `task --model <name> "..."` / `status` / `models` の4サブコマンドを実装する。`task` は Ollama の `/v1/chat/completions` エンドポイントを `curl` で呼び出し、応答を stdout に出力する。`status` は `curl -s http://localhost:11434/api/tags` の疎通で Ollama 起動確認。`models` は同 API のモデル一覧を整形表示。Ollama 未起動時は `⚠️ Ollama is not running. Start with: ollama serve` を stderr に出力して exit 1 | (a) `bash scripts/ollama-companion.sh status` が起動中/未起動を正しく判定する、(b) `bash scripts/ollama-companion.sh task "hello"` でローカルモデルの応答が返る、(c) `--model qwen2.5-coder:7b` でモデル指定が機能する、(d) Ollama 未起動時のエラーメッセージが明確、(e) `bash scripts/ollama-companion.sh models` でモデル一覧が表示される | - | cc:完了 [9b942a9] |
| 64.2 | `harness-work` スキル (`skills/harness-work/SKILL.md`) に `--ollama` フラグの説明を追加し、`scripts/codex-companion.sh` の `--codex` フラグと対称的に記述する。実行時は `ollama-companion.sh task --write` 相当の呼び出しにマッピングする | (a) `SKILL.md` の オプション表に `--ollama` 行が追加される、(b) Quick Reference 表に `--ollama` モードが記載される、(c) `codex-companion.sh` / `gemini-companion.sh` と同等の呼び出し仕様が文書化される | 64.1 | cc:完了 [6daf4fe] |
| 64.3 | タスク複雑度による自動ルーティングを実装する。`scripts/ollama-companion.sh` に `score-task "タスク内容"` サブコマンドを追加し、変更ファイル数推定・キーワード（security / migration / architecture）・行数の3要素でスコアを算出する。スコアが閾値（既定 3）以下なら `ollama`、超えれば `codex/claude` を推奨する。閾値は `.claude-code-harness.config.yaml` の `routing.ollama_score_threshold` で上書き可能 | (a) `bash scripts/ollama-companion.sh score-task "add description-zh field"` がスコアと推奨エンジンを JSON で返す、(b) `security` キーワードを含むタスクが閾値超と判定される、(c) config.yaml の `routing.ollama_score_threshold` 設定でしきい値変更が機能する、(d) スコア算出が 1 秒以内に完了する（外部 API 不使用） | 64.1 | cc:完了 [9b942a9] |
| 64.4 | `tests/test-ollama-companion.sh` を新規作成する。Ollama API をモックして `task` / `status` / `models` / `score-task` の動作を検証する。実際の Ollama デーモンに依存しない（CI 環境でも PASS） | (a) task / status(up) / status(down) / models / score-task の 5 ケースが PASS、(b) CI 環境（Ollama 未起動）でも全テスト PASS、(c) `bash tests/test-ollama-companion.sh` が単体で実行可能、(d) `./tests/validate-plugin.sh` が PASS を維持 | 64.1, 64.2, 64.3 | cc:完了 [3a7e953] |

---
