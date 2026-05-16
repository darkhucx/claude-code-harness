# GitNexus 統合ガイド

> 対象: claude-code-harness v4.4.0+ / Claude Code v2.1.111+
> 最終更新: 2026-04-28

## 概要

[GitNexus](https://github.com/abhigyanpatwari/GitNexus) はリポジトリを **ナレッジグラフ**（symbol / call chain / process / cluster / route 等）に変換し、MCP サーバとして Claude Code に公開する code intelligence engine。

Harness と組み合わせると、`/work`・`/harness-review` の各フェーズで **「grep より先に graph」** が成立する:

| フェーズ | Harness 単体 | GitNexus 併用後 |
|---------|-------------|-----------------|
| 影響範囲推定 | grep + 手動追跡 | `mcp__gitnexus__impact` で blast radius |
| 変更検知 | `git diff` のみ | `detect_changes` で affected process まで |
| Self-review 証拠 | self_review 5 件を Worker が言語化 | `context` の callers/callees を根拠として添付 |
| 残骸チェック (Phase 40) | `check-residue.sh` | `cypher` で旧概念の参照を直接 query |

GitNexus は **読み取り専用の理解レイヤー**として補完する位置づけ。Harness の guardrail / agent 契約は変更しない。

---

## ⚠️ Harness 固有の注意

GitNexus の `analyze` 既定動作は **CLAUDE.md / AGENTS.md / `.claude/skills/` / Claude Code hooks を自動書き換え**する。Harness は以下を deny / 既存実装で保護しているため、**素のまま走らせると衝突する**:

| 保護対象 | 保護方法 | GitNexus が触ろうとする |
|---------|---------|------------------------|
| `.claude/settings*` | `settings.json` deny | hooks 追記 |
| `CLAUDE.md` 末尾 | `self-audit.md` の integrity マーカー | gitnexus セクション追記 |
| `.claude/skills/` 配下 | `skill-editing.md` SSOT | `.claude/skills/generated/` 生成 |

回避策:

- 必ず `--skip-agents-md` を付ける
- `gitnexus setup` の auto-config は使わず、`claude mcp add` で手動接続
- `.claude/skills/generated/` は git ignore する

---

## セットアップ手順

### Step 1: インストールと初回 analyze

```bash
# グローバルインストール
npm install -g gitnexus

# Harness ルートで安全な index 化
cd $(git rev-parse --show-toplevel)
gitnexus analyze --skip-agents-md

# 状態確認
gitnexus status
gitnexus list
```

`.gitnexus/` がリポジトリ直下に生成される。**`.gitignore` に `.gitnexus/` を追加すること**。

embedding が必要な場合（hybrid 検索の精度↑ / 解析時間↑）:

```bash
gitnexus analyze --skip-agents-md --embeddings
```

> **再 analyze 時の注意**: 一度 `--embeddings` で作ったら、以降の analyze にも必ず `--embeddings` を付ける。付け忘れると embeddings が破棄される（GitNexus の README 記載）。

### Step 2: MCP として接続

```bash
# ユーザースコープ（全プロジェクトから利用可能）
claude mcp add gitnexus -- npx -y gitnexus@latest mcp
```

接続確認: 次セッションで `/mcp` を実行し `gitnexus` が表示されること。

Harness の `settings.json` deny は `mcp__codex__*` / `mcp__gemini__*` のみで `mcp__gitnexus__*` は素通り。追加 deny は不要。

### Step 3: `.gitignore` 更新

```gitignore
# GitNexus
.gitnexus/
.claude/skills/generated/
```

---

## 提供される MCP ツール（11 + 5）

Harness 開発で使用頻度が高い順:

| ツール | 用途 | Harness での主な利用箇所 |
|--------|------|------------------------|
| `query` | BM25 + vector hybrid の自然言語検索 | `/work` 実装前の探索 |
| `context` | symbol の callers / callees / process | Worker の self_review 証拠 |
| `impact` | blast radius (upstream / downstream) | `/work` の scope 検出補強 |
| `detect_changes` | `git diff` → 影響 process マップ | `/harness-review` の事前分析 |
| `rename` | graph + text の多ファイル協調 rename (`dry_run` あり) | リファクタリングタスク |
| `cypher` | 生 Cypher クエリ | Phase 40 残骸チェックの拡張 |
| `list_repos` | 登録済みレポジトリ一覧 | マルチレポ運用時 |

詳細は GitNexus README の "What Your AI Agent Gets" セクション参照。

---

## 対話例: `monitor.go` の health check 変更

ユーザー入力:

> `monitor.go` の `harness-mem` health check を変更したい。影響範囲を教えて。

Claude Code 側の内部フロー:

```
1. mcp__gitnexus__list_repos
   → claude-code-harness が登録済みか確認

2. mcp__gitnexus__context({
     symbol: "runMemHealthCheck",
     repo: "claude-code-harness"
   })
   → callers / callees / 関連 process を取得

3. mcp__gitnexus__impact({
     symbol: "runMemHealthCheck",
     direction: "downstream",
     repo: "claude-code-harness"
   })
   → blast radius + confidence + 影響テスト一覧

4. Read で該当ファイルを開く
   → active-watching-test-policy.md の 3 状態カバレッジ規約に照合

5. Edit で改修案を提示
   → self_review 5 件に impact 結果を引用
```

**ポイント**: 手順 2-3 で `impact` が返す confidence と affected tests を、Worker の `worker-report.v1` の `self_review[]` 内 `dod-items-verified-with-evidence` の evidence として参照できる。

---

## Harness 機能との対応

| Harness 機能 | GitNexus 補強 | 連携方法 |
|------------|--------------|---------|
| `worker.md` self_review 5 件 | `impact` の confidence | `dod-items-verified-with-evidence` rule の evidence 欄 |
| Phase 40 deleted-concepts | `cypher` で旧概念参照 grep | `check-residue.sh` の補完 query |
| `/work` scope 検出 | `detect_changes` | `git diff` 入力で affected process まで取得 |
| `/harness-review` 規約判定 | `context` の callers | review 時の影響確認 |
| `active-watching-test-policy.md` 3 状態 | `query "health check"` | 既存 health check 実装の参照 |

---

## トラブルシュート

### `analyze` が CLAUDE.md を上書きしようとして失敗する

`--skip-agents-md` を付け忘れ。再実行する。

### MCP に gitnexus が出ない

```bash
gitnexus list  # registry に登録されているか確認
claude mcp list  # Claude Code 側の登録確認
```

それでも出ない場合は Claude Code を再起動。

### LadybugDB lock error

`.gitnexus/lbug` を同時に開けるのは 1 プロセスのみ。MCP server と `analyze` を同時に走らせると衝突する。片方を停止して再試行。

### embedding が消えた

`--embeddings` 付きで再 analyze。`.gitnexus/meta.json` の `stats.embeddings` が 0 になっていないか確認。

---

## アンインストール

```bash
gitnexus clean              # このリポジトリのインデックス削除
claude mcp remove gitnexus  # MCP 接続解除
rm -rf .gitnexus/           # 残骸の削除
```

`.gitignore` から `.gitnexus/` / `.claude/skills/generated/` の行を削除すれば完全撤退。

---

## 関連

- 上流: https://github.com/abhigyanpatwari/GitNexus
- License: PolyForm Noncommercial（OSS だが商用利用は別契約）
- 必要環境: Node.js ≥ 20, Git
- Harness 側: [`.claude/rules/active-watching-test-policy.md`](../.claude/rules/active-watching-test-policy.md), [`agents/worker.md`](../agents/worker.md)
