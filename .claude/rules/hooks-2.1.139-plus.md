# Hooks (Claude Code 2.1.133+) Rules

CC `2.1.133`-`2.1.142` で hook 周りに増えた `$CLAUDE_EFFORT` env / `effort.level` JSON 入力、
exec form (`args: string[]`)、`continueOnBlock`、`terminalSequence`、
SessionStart/Setup/SubagentStart の command-only 制約を Harness で扱うための SSOT。

このルールは Phase 69 (`docs/upstream-update-snapshot-2026-05-15.md`) で導入された。
既存 rule (`opus-4-7-prompt-audit.md`, `skill-editing.md`, `commit-safety.md`) と直交し、
hook 設計時に必ず参照する。

## 1. `$CLAUDE_EFFORT` env / `effort.level` JSON 入力

### 動作 (2.1.133+)

- すべての hook の stdin JSON に `effort: { level: "low" | "medium" | "high" }` が含まれる。
- すべての hook subprocess に `$CLAUDE_EFFORT` 環境変数が exported される。
- Bash tool で起動される subprocess も `$CLAUDE_EFFORT` を継承する。

### Harness 利用条件

- hook handler が effort によって挙動を変えてよいケース:
  - **観測のみ**: log に effort を含める (例: `notification-handler.sh` の jsonl 記録)。
  - **opt-in な強度切替**: 同じ rule を effort で degrade しない。
    例: `high` でだけ追加 lint を走らせる、は **禁止**。`medium` でも同じ rule を維持する。
- 禁止:
  - effort で deny → ask に降格する hook (`pre-tool` ルール R01-R13 等の guard rail は effort 不問)。
  - effort 文字列が空のときに silent fallback して別 effort 相当の判定をする (空なら effort 情報なしと扱う)。

### Bash 内利用

- hook の `command` 内で `"${CLAUDE_EFFORT:-unset}"` を参照してよい。
- 値の妥当性 (`low`/`medium`/`high`) を呼び出し側で検証してから挙動分岐する。

## 2. Hook exec form (`args: string[]`) (2.1.139+)

### 動作

CC 2.1.139 で hook 定義に `args: string[]` 形式の exec form が追加された。
shell を介さず直接 spawn するため、path placeholder (例: `${CLAUDE_PROJECT_DIR}/scripts/foo.sh`)
を quoting せずに渡せる。

```json
{
  "type": "command",
  "args": ["${CLAUDE_PROJECT_DIR}/scripts/hook-handlers/notification-handler.sh", "${event}"]
}
```

### Harness 利用条件 (採用基準)

| ケース | 推奨 form | 理由 |
|--------|-----------|------|
| `${CLAUDE_PROJECT_DIR}` / `${CLAUDE_PLUGIN_DATA}` 単純展開のみ | exec form (`args`) | quoting 漏れによる shell injection を排除 |
| `bash -c` 経由で複数コマンド連結が必要 | 既存 `command` (shell form) | `&&` / OR-shell / pipe / heredoc が必要なため |
| `if`/`for` 等 shell 制御構文が必要 | 既存 `command` (shell form) | 同上 |
| 引数に空白 / 環境変数展開 (`$VAR`) を含むユーザー入力 | exec form (`args`) | shell injection 防止 |

### 移行手順 (任意 / 段階的)

1. 新規 hook を追加する際は exec form を優先。
2. 既存 hook の `command` を exec form に書換える時は、`bash -c '...' _` のような shell 経由 wrapper を解体できるか確認。`valid_root` チェック等で shell 制御が必要な場合は据え置く。
3. 移行した hook の動作差 (環境変数展開, PATH 解決, signal handling) を `tests/test-hooks-*.sh` で検証してからマージ。

## 3. `PostToolUse.continueOnBlock` (2.1.139+)

### 動作

PostToolUse hook で `continueOnBlock: true` を設定すると、hook が `permissionDecision: "deny"`
を返したときに rejection reason が Claude に feedback され、turn を継続して再試行できる。
default は `false` (= 従来通り turn 停止)。

### Harness 利用条件

- **`continueOnBlock: true` の許可ケース**: 「diagnostic feedback」用途のみ。
  例: lint hook が「行末空白がある」と feedback → Claude が修正リトライ。
- **`continueOnBlock: false` 必須ケース**:
  - **R01-R13 guard rail**: protected path への書込、`git push --force`、`rm -rf` 等。
    deny は不可逆操作の防止であり、Claude にリトライさせない。
  - **secret detection**: credentials を含む変更 deny。リトライで漏洩リスクが残る。
  - **policy violation**: `.eslintrc*` 等 protected config への書換。

### 実装

`.claude-plugin/hooks.json` で `PostToolUse` hook を新規追加する際は、
`continueOnBlock` を明示する (default に依存しない)。

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    { "type": "command", "command": "...", "continueOnBlock": false }
  ]
}
```

## 4. `terminalSequence` output field (2.1.141+)

### 動作

hook の stdout JSON に `terminalSequence` を含めると、Claude Code が controlling terminal を
持たない状態 (background session, `--bg`) でも desktop notification / window title / bell を
発火できる。

payload は **ESC (0x1B) + `]` + 番号 + `;` + 内容 + BEL (0x07)** の OSC (Operating System Command)
sequence。JSON では unicode escape (`\u001b` / `\u0007`) を使う:

```json
{
  "decision": "approve",
  "terminalSequence": "\u001b]9;Build complete\u0007"
}
```

主な OSC sequence (`<ESC>` = 0x1B = `\u001b`, `<BEL>` = 0x07 = `\u0007`):

- `OSC 9`: `<ESC>]9;<text><BEL>` — macOS Terminal / iTerm 通知 (popup)
- `OSC 0`: `<ESC>]0;<title><BEL>` — window title
- `OSC 2`: `<ESC>]2;<title><BEL>` — window title (代替表記)
- `OSC 777;notify`: `<ESC>]777;notify;<title>;<body><BEL>` — KDE/GNOME desktop notification
- `BEL` alone: `<BEL>` (0x07) — terminal bell のみ

### Harness 利用条件

- **必ず opt-in**: hook handler は env (`HARNESS_TERMINAL_NOTIFY`) が未設定なら `terminalSequence` を出力しない。
  - `unset` / `0`: 出力しない (default)
  - `1` / `bell`: BEL のみ
  - `title`: window title 更新のみ
  - `osc9`: OSC 9 popup notification
  - `notify`: OSC 777 (Linux desktop notification)
- **payload 制約**: `terminalSequence` の payload は ASCII 文字 + 印字可能 unicode に限る。
  bell 文字 (`\u0007`) と OSC terminator 以外の制御文字を含めない (terminal corruption 防止)。
- **secrets を含めない**: hook payload (PR タイトル等) を `terminalSequence` に転記する前に
  redact rules (`.claude/rules/cross-repo-handoff.md` の Layer 2/3) を適用する。

### 標準実装ヘルパ

**ランタイム (Go バイナリ)**:
- `go/internal/hookhandler/terminal_notify.go` — `BuildTerminalSequence` / `AugmentWithTerminalSequence`
- `go/internal/hookhandler/notification_handler.go` (Notification hook) — `HARNESS_TERMINAL_NOTIFY` を読み、既知 4 種 (`permission_prompt` / `elicitation_dialog` / `idle_prompt` / `auth_success`) で emit
- `go/internal/hookhandler/task_completed.go` (TaskCompleted hook) — 全応答 path に `terminalSequence` を付与

**シェル参照実装**:
- `scripts/hook-handlers/webhook-notify.sh`
- `scripts/hook-handlers/notification-handler.sh`
- `scripts/lib/terminal-notify.sh`

ランタイムは `.claude-plugin/hooks.json` から `bin/harness hook ...` 経由で Go バイナリが起動するため、
実際の `terminalSequence` 出力は Go 実装が担当する。シェル版は Plans.md SSOT や運用 doc で
参照される際の reference として保守する。

## 5. SessionStart / Setup / SubagentStart は command-type 限定 (2.1.142+)

### 動作

CC 2.1.142 で `SessionStart` / `Setup` / `SubagentStart` 系 hook に `type: "prompt"` または
`type: "agent"` を指定すると、起動時に「use a command-type hook instead」のエラーが出る。

理由: これらの hook は session bootstrap 段階で動くため、LLM 系 hook (prompt/agent) の latency と
permission propagation を許容できない。

### Harness 利用条件

- **`.claude-plugin/hooks.json` の `Setup`/`SessionStart`/`SubagentStart` matcher 配下の hook は必ず `type: "command"`**。
- 例外なし。LLM 判断が必要な場合は `PreToolUse` で受ける。
- 既存 `hooks.json` を編集する際は `grep -nE '"SessionStart"|"Setup"|"SubagentStart"' .claude-plugin/hooks.json` で確認後、
  `type:` 値が `"command"` であることを確認する。

### CI gate

`tests/validate-plugin.sh` で本制約を grep gate として強制する (Section 4 settings parity の延長)。

## 6. Checklist (hook 追加 / 編集時)

- [ ] hook の input JSON で `effort.level` を参照する場合、effort 不在時の fallback を明示
- [ ] hook subprocess で `$CLAUDE_EFFORT` を参照する場合、空文字列を許容
- [ ] hook が path placeholder のみを使うなら exec form (`args`) を優先
- [ ] `PostToolUse` hook に `continueOnBlock` を明示 (default に依存しない)
- [ ] guard rail (R01-R13 / secret / protected config) では `continueOnBlock: false`
- [ ] `terminalSequence` を使う hook は `HARNESS_TERMINAL_NOTIFY` env で opt-in
- [ ] `terminalSequence` payload に secret / 非印字制御文字を含めない
- [ ] `SessionStart` / `Setup` / `SubagentStart` 配下の hook は `type: "command"` のみ
- [ ] hook の挙動を変える場合、`tests/validate-plugin.sh` の関連 section が PASS

## 7. 関連

- `docs/upstream-update-snapshot-2026-05-15.md` — Phase 69 snapshot (本 rule の導入根拠)
- `.claude/rules/opus-4-7-prompt-audit.md` — agent 契約と permission 境界
- `.claude/rules/skill-editing.md` — skill 編集 SSOT
- `.claude/rules/commit-safety.md` — `/undo` policy (rewind compaction との関係)
- `scripts/hook-handlers/webhook-notify.sh` — `terminalSequence` reference 実装
- `scripts/hook-handlers/notification-handler.sh` — `terminalSequence` reference 実装
