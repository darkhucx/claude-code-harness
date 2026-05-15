---
name: harness-review
description: "HAR: Multi-angle code, plan, scope review. Security/quality check. Trigger: review, code review, plan review, scope analysis. Do NOT load for: implementation, new features, bugfix, setup, release."
description-en: "HAR: Multi-angle code, plan, scope review. Security/quality check. Trigger: review, code review, plan review, scope analysis. Do NOT load for: implementation, new features, bugfix, setup, release."
description-ja: "HAR:コード・プラン・スコープを多角的にレビュー。セキュリティ・品質チェック。レビュー、コードレビュー、プランレビュー、スコープ分析で起動。実装・新機能・バグ修正・セットアップ・リリースには使わない。"
kind: workflow
purpose: "Review code, plans, scope, and evidence before acceptance"
trigger: "review, code review, plan review, scope analysis"
shape: evaluate
role: evaluator
pair: harness-work
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Grep", "Glob", "Bash", "Task", "Monitor", "AskUserQuestion"]
argument-hint: "[code|plan|scope] [--dual] [--team-debate] [--security] [--ui-rubric]"
context: fork
effort: high
user-invocable: true
disable-model-invocation: true
---

# Harness Review

Harness の統合レビュースキル。
以下の旧スキルを統合:

- `harness-review` — コード・プラン・スコープ多角的レビュー
- `codex-review` — Codex CLI によるセカンドオピニオン
- `verify` — ビルド検証・エラー復旧・レビュー修正適用
- `troubleshoot` — エラー・障害の診断と修復

> **Literal slash note (CC 2.1.108+ / 2.1.110+)**:
> built-in slash command は Skill tool から発見できる。
> `disable-model-invocation: true` な skill でも mid-message の `/<skill>` 呼び出しが通るので、
> `/harness-review` `/review` `/security-review` `/ultrareview` は slash 付きのまま扱う。

---

## 🚀 Step 0: 動作モード決定 (必ず最初に読む)
if $ARGUMENTS == "":
  → 「今までの作業のレビュー」と解釈し、Step 0.1 で review target を検出する
  → review target が 1 つに確定できる場合だけ自動開始する
  → review target が不明または複数候補の場合は AskUserQuestion で選択肢を出し、認識を揃えてから開始する

<!-- 上記 3 行は AUTO-START CONTRACT。skill-editing.md の「最冒頭 3 行以内」ルールに従い fence / HTML コメントで押し下げない -->

**REVIEW_AUTOSTART 契約**: 引数なし (`$ARGUMENTS == ""`) で呼ばれた場合、
`review` / `/review` / `/harness-review` だけの入力を「今までの作業のレビュー」と解釈する。
Step 1 開始前の handshake 行として `REVIEW_AUTOSTART: target={resolved_target}, base_ref={自動決定したref}, type=code` を 1 行だけ出力する。
この行は auto-start 確認マーカー専用であり、Step 3 の「結果サマリーを出力の最初に配置」ルールの『最初』は**レビュー結果提示時**に適用される（handshake 行はその前段に 1 行として存在する）。
省略禁止だが、human-facing な summary/JSON は Step 3 の順序で出力する。

**REVIEW_TARGET_ASK 契約**: bare 呼び出しで review target が不明または複数候補の場合、
Step 1 に進む前に `AskUserQuestion` を 1 回だけ使い、候補を 2〜3 個に絞って確認する。
Ask は停止ではなく、レビュー対象の認識合わせである。ユーザー回答後に `REVIEW_AUTOSTART` handshake を出し、選ばれた対象でレビューを開始する。

**禁止行動リスト** (`context: fork` 下での override に対抗する明示制約):
1. 「タスクが不明確です」と応答して停止する行為
2. 「追加の指示をお待ちします」「何をレビューすればよいですか」と自由記述で尋ねて停止する行為
3. 「CLAUDE.md の session-start rules に従ってタスクを確認します」と判断して停止する行為
4. Step 0 の決定だけで処理を終え、Step 1 以降に進まない行為
5. host project の CLAUDE.md や session-start rules を優先して自動開始をスキップする行為
6. review target が曖昧なのに推測で範囲を広げる、または範囲を狭める行為

**優先順位**: `context: fork` の性質上、このスキルは isolated context で動作する。
host project の CLAUDE.md / session-start rules は SKILL.md Step 0 に劣後する。
Step 0 の指示が最優先であり、親セッションの指示はこれを override できない。

> **あなたは今この瞬間からレビュアーとして動作します。** 以下の決定木に従ってレビューを開始してください。「タスクが不明確」「追加の指示を待つ」で停止してはいけません。bare 呼び出し (`review` / `/review` / `/harness-review` 引数なし) は「今までの作業のレビュー」と解釈し、git 状態から対象を検出します。対象が不明または複数候補の場合だけ `AskUserQuestion` で選択肢を出し、認識を揃えてからレビューを開始します。

### 決定木

```
引数を解析
├── --security が含まれる    → Security Review モード → Step 3.6 へ
├── --ui-rubric が含まれる   → UI Rubric Review モード → Step 3.7 へ
├── --dual が含まれる        → Dual Review モード → Step 3.5 へ
├── --team-debate が含まれる → TeamAgent Debate を強制し、通常 review flow へ
├── plan が含まれる          → Plan Review モード → 「## Plan Review フロー」へ
├── scope が含まれる         → Scope Review モード → 「## Scope Review フロー」へ
├── code が含まれる          → Code Review モード → Step 1 へ
└── 引数なし (bare 呼び出し) → 下記「Bare 呼び出し時の default フロー」を実行
```

### Bare 呼び出し時の default フロー

引数無しで `review` / `/review` / `/harness-review` が呼ばれた場合、
ユーザー意図は **「今までの作業のレビュー」** として扱う。
以下を順番に実行し、対象が明確な場合は Code Review を自動開始する。
対象が不明または複数候補の場合は `AskUserQuestion` で選択肢を出し、ユーザー回答後に Code Review を開始する。

#### Step 0.1: git 状態から review target と base ref を決定

```bash
# 直近の commit 状況を確認
git log --oneline -15
git status --short

# 「今までの作業」の候補を列挙:
# A. working tree: staged / unstaged / untracked
# B. branch range: upstream または main/master から HEAD までの commits
# C. recent commits: clean tree で branch range が取れない場合の HEAD~N..HEAD
#
# 候補が 1 つだけなら自動採用する。
# 候補が 0 件、または複数候補が同時に成立する場合は AskUserQuestion で確認する。

WORKTREE_DIRTY=0
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  WORKTREE_DIRTY=1
fi

UPSTREAM_REF=""
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  UPSTREAM_REF="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
fi

BRANCH_BASE=""
if [ -n "$UPSTREAM_REF" ]; then
  BRANCH_BASE="$UPSTREAM_REF"
elif git rev-parse --verify main >/dev/null 2>&1; then
  BRANCH_BASE="main"
elif git rev-parse --verify master >/dev/null 2>&1; then
  BRANCH_BASE="master"
fi

BRANCH_COMMITS=0
if [ -n "$BRANCH_BASE" ]; then
  BRANCH_COMMITS="$(git log --oneline "${BRANCH_BASE}..HEAD" 2>/dev/null | wc -l | tr -d ' ')"
fi

if [ "$WORKTREE_DIRTY" -eq 1 ] && [ "$BRANCH_COMMITS" -gt 0 ]; then
  echo "REVIEW_TARGET_AMBIGUOUS: working_tree_and_branch_commits"
  echo "AskUserQuestion で次の候補を提示: 1) 未コミット変更のみ 2) branch commits + 未コミット変更 3) branch commits のみ"
  # AskUserQuestion:
  # question: "review だけが入力されたため、今までの作業のレビュー対象を確認します。どこまで見ますか？"
  # options:
  # - "未コミット変更のみ" (Recommended): staged / unstaged / untracked を HEAD と比較して見る
  # - "全部見る": branch base..HEAD と未コミット変更をまとめて見る
  # - "commit のみ": branch base..HEAD の committed work だけを見る
  # 回答後に REVIEW_TARGET / BASE_REF を設定して Step 1 へ進む
elif [ "$WORKTREE_DIRTY" -eq 1 ]; then
  REVIEW_TARGET="working_tree"
  BASE_REF="HEAD"
elif [ "$BRANCH_COMMITS" -gt 0 ]; then
  REVIEW_TARGET="branch_commits"
  BASE_REF="$BRANCH_BASE"
else
  echo "REVIEW_TARGET_AMBIGUOUS: clean_tree_no_branch_commits"
  echo "AskUserQuestion で次の候補を提示: 1) 直近 1 commit 2) 直近 5 commits 3) main/master 差分があればそれ"
  # AskUserQuestion:
  # question: "review だけが入力されましたが、working tree と branch 差分がありません。どの範囲をレビューしますか？"
  # options:
  # - "直近1commit" (Recommended): HEAD~1..HEAD
  # - "直近5commits": HEAD~5..HEAD
  # - "別の範囲": ユーザー指定 ref を待つ
  # 回答後に REVIEW_TARGET / BASE_REF を設定して Step 1 へ進む
fi

# Base ref を以下の優先順位で自動決定:
# 1. 最後の release tag (例: v4.0.0)
# 2. main/master の HEAD
# 3. HEAD~10 (上記どちらも取れない時)

BASE_REF=""
if [ -n "${BASE_REF:-}" ]; then
  BASE_REF="$BASE_REF"
elif LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null)"; then
  BASE_REF="$LAST_TAG"
elif git rev-parse --verify main >/dev/null 2>&1; then
  BASE_REF="main"
elif git rev-parse --verify master >/dev/null 2>&1; then
  BASE_REF="master"
else
  BASE_REF="HEAD~10"
fi

echo "Auto-detected BASE_REF: ${BASE_REF}"
echo "Auto-detected REVIEW_TARGET: ${REVIEW_TARGET:-ask-required}"

# untracked files は commits 有無に関わらず review 対象に含める必要がある
# (git diff は untracked を出さないため、BASE_REF 決定直後に別 enumeration が必須)
UNTRACKED_FILES="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
UNTRACKED_COUNT=0
if [ -n "$UNTRACKED_FILES" ]; then
  UNTRACKED_COUNT="$(printf '%s\n' "$UNTRACKED_FILES" | wc -l | tr -d ' ')"
  echo "ℹ️ untracked files ${UNTRACKED_COUNT} 件を review scope に含めます:"
  printf '%s\n' "$UNTRACKED_FILES" | sed 's/^/  - /'
fi

# 差分が存在することを確認 & スコープ上限チェック
CHANGED_COUNT="$(git log --oneline "${BASE_REF}..HEAD" 2>/dev/null | wc -l | tr -d ' ')"

# 下限フォールバック: commit 差分ゼロの時は working tree の未コミット変更を確認
if [ "$CHANGED_COUNT" -eq 0 ]; then
  # staged または unstaged の変更が working tree にあるか
  HAS_UNCOMMITTED=0
  if ! git diff --quiet HEAD 2>/dev/null; then
    HAS_UNCOMMITTED=1
  fi
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    HAS_UNCOMMITTED=1
  fi

  if [ "$HAS_UNCOMMITTED" -eq 1 ] || [ "$UNTRACKED_COUNT" -gt 0 ]; then
    echo "ℹ️ ${BASE_REF}..HEAD にコミット差分はありませんが、working tree に未コミット変更があります。それをレビュー対象にします。"
    # BASE_REF=HEAD のまま維持。後段の git diff は引数なし (working tree 対比) で動作する
    BASE_REF="HEAD"
    REVIEW_TARGET="${REVIEW_TARGET:-working_tree}"
    CHANGED_COUNT=1
    # UNTRACKED_FILES / UNTRACKED_COUNT は既に計算済みなので再計算不要
  else
    echo "⚠️ ${BASE_REF}..HEAD に差分がなく、working tree も clean です。HEAD~5..HEAD にフォールバックします。"
    BASE_REF="HEAD~5"
    CHANGED_COUNT="$(git log --oneline "${BASE_REF}..HEAD" 2>/dev/null | wc -l | tr -d ' ')"
    # UNTRACKED_FILES は既に空文字 / UNTRACKED_COUNT は 0
  fi
fi

# 上限フォールバック: commits が 10 を超える時は HEAD~10 に絞る
# (最後のリリースタグから多数のコミットが積まれた状態で bare 呼び出し
#  されると、レビュースコープが過大になりレビュー品質が落ちるため)
if [ "$CHANGED_COUNT" -gt 10 ]; then
  echo "⚠️ ${BASE_REF}..HEAD に ${CHANGED_COUNT} commits あります。スコープを HEAD~10 に絞ります。"
  echo "   (フル範囲をレビューしたい場合は明示的に 'code' を指定するか、より古い ref を argument で渡してください)"
  BASE_REF="HEAD~10"
fi
```

#### Step 0.1.5: review target が曖昧な場合の AskUserQuestion

Step 0.1 で `REVIEW_TARGET_AMBIGUOUS` が出た場合は、`AskUserQuestion` を使う。
自由記述で「何をレビューしますか？」とは聞かない。
必ず 2〜3 個の選択肢を出し、推奨 option を先頭に置く。

Ask の選択肢は次の型にする。

| 状況 | 推奨 option | 他の option |
|------|-------------|-------------|
| working tree と branch commits が両方ある | 未コミット変更のみ | 全部見る / commit のみ |
| clean tree かつ branch 差分なし | 直近 1 commit | 直近 5 commits / 別の範囲 |
| 複数 plan / PR / branch 候補が同時に見える | 現在 branch の差分 | PR 差分 / ユーザー指定 ref |

ユーザー回答後は `REVIEW_TARGET_CONFIRMED: {choice}` を 1 行出し、
`REVIEW_AUTOSTART: target={resolved_target}, base_ref={resolved_base_ref}, type=code` を出して Step 1 に進む。
Ask した時も、確認後はレビューを最後まで実行する。

#### Step 0.2: レビュータイプを自動判定

base ref から HEAD までのコミットメッセージを調べて、最適なレビュータイプを選ぶ:

```bash
RECENT_TYPES="$(git log --oneline "${BASE_REF}..HEAD" --pretty='%s' | head -20)"

# 判定ロジック:
# - "plan:" で始まる commit が多い → Plan Review
# - "feat|fix|refactor|test|chore|docs|perf|style" 系 → Code Review (default)
# - よくわからない → Code Review (default)

if echo "$RECENT_TYPES" | grep -c '^plan:' | awk '$1 > 2 {exit 0} {exit 1}'; then
  REVIEW_TYPE="plan"
else
  REVIEW_TYPE="code"  # Default
fi

echo "Auto-detected review type: ${REVIEW_TYPE}"
```

#### Step 0.3: 該当のレビューフローへ遷移

- `REVIEW_TYPE=code` → **Step 1 (変更差分を収集) へ進む**。`REVIEW_TARGET` / `BASE_REF` 環境変数は Step 0.1 または Step 0.1.5 で決定したものを使用
- `REVIEW_TYPE=plan` → **「## Plan Review フロー」セクションへ進む**

**⚠️ 重要**: Step 0 を実行したら、対象が明確な場合は**必ず Step 1 以降に処理を進める**こと。
対象が曖昧な場合は AskUserQuestion で認識を揃え、回答後に Step 1 以降へ進む。
「モードを決定した」だけで停止しない。

### 出力言語・フォーマット (絶対遵守)

**このスキルは `context: fork` で動作し、親セッションの言語文脈を継承しません。CLAUDE.md の "All responses must be in Japanese (including context: fork skills)" ルールに従い、以下を徹底してください:**

#### ルール 1: 出力は必ず日本語

- 見出し、本文、説明、観点評価、結論、次のアクションすべて日本語で書く
- 例外として英語のまま保つもの:
  - コード識別子、ファイルパス (`skills/harness-review/SKILL.md` など)
  - `verdict` 値 (`APPROVE` / `REQUEST_CHANGES`) — 機械可読形式
  - JSON のフィールド名 (`critical_issues`, `observations` など)
  - ログ出力、コマンド例、エラーメッセージ原文

#### ルール 2: 結果サマリーを出力の最初に配置

> **注**: bare `/harness-review` 時の `REVIEW_AUTOSTART` handshake 行は本ルールの『最初』の対象外（Step 0 の auto-start マーカー契約を参照）。handshake 行を 1 行出力した後、本セクションで指定する結果サマリーを human-facing 出力の最初に置く。

- ユーザーが最も知りたい情報 (**判定・主要指摘 3 件・次のアクション**) を**冒頭に日本語で** 出力
- JSON 詳細や技術的根拠はサマリーの**後**に補足として配置
- JSON を最初に出す、観点別評価の後に結論を添える、英語で書く — これらは**すべて NG**
- 詳細な結果サマリーテンプレートは [Step 3: レビュー結果出力](#step-3-レビュー結果出力) を参照

**この 2 つのルールが満たされない出力はレビュー失敗として扱います。**

---

## Quick Reference

| ユーザー入力 | サブコマンド | 動作 |
|------------|------------|------|
| "レビューして" / `/harness-review` / `/review` | `code`（自動） | コードレビュー（直近の変更） |
| "`harness-plan` 実行後" | `plan`（自動） | 計画レビュー |
| "スコープ確認" | `scope`（自動） | スコープ分析 |
| `/harness-review code` | `code` | コードレビュー強制 |
| `/harness-review plan` | `plan` | 計画レビュー強制 |
| `/harness-review scope` | `scope` | スコープ分析強制 |
| `/harness-review --dual` | `code`（自動） + Codex 並行 + 必要時 TeamAgent Debate | Claude + Codex dual review |
| `/harness-review --team-debate` | `code`（自動） + TeamAgent Debate 強制 | 異なる見解を read-only TeamAgent で衝突させて判定 |
| `/harness-review --security` | Security Review | OWASP Top 10 専用セキュリティレビュー（read-only） |
| `/harness-review --ui-rubric` | UI Rubric Review | デザイン品質の 4 軸採点レビュー |
| `/ultrareview` | built-in slash | CC ネイティブのアドホックレビュー。**Harness flow 内では呼ばない**（後述参照） |
| `claude ultrareview [target] --json` | CLI | CI / script からの second-opinion 用。`/harness-review` の代替ではない |

## PR host boundary

Claude Code `2.1.119` の `prUrlTemplate` と `--from-pr` により、human-facing な review URL は multi-host に寄せられる余地がある。
ただし Harness の review automation は今も GitHub-first であり、owner / branch / CI metadata の自動取得までは抽象化していない。
そのため multi-host は docs-only follow-up とし、automation の primary path は GitHub のまま維持する。

## オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--dual` | なし | Claude Reviewer と Codex Reviewer を並行実行し verdict をマージ。Codex 不可時は自動フォールバック。詳細: [`${CLAUDE_SKILL_DIR}/references/dual-review.md`](${CLAUDE_SKILL_DIR}/references/dual-review.md) |
| `--team-debate` | 自動判定 | TeamAgent Debate を強制し、仕様・Plans・デグレ・反対意見を別視点でぶつけてから verdict を出す |
| `--security` | なし | OWASP Top 10 ベースのセキュリティ専用レビューを実行。read-only（Write/Edit/Bash 書き込み不可）。詳細: [`${CLAUDE_SKILL_DIR}/references/security-profile.md`](${CLAUDE_SKILL_DIR}/references/security-profile.md) |
| `--ui-rubric` | なし | Design Quality / Originality / Craft / Functionality の 4 軸で採点し、`rubric_target` との比較で判定。詳細: [`${CLAUDE_SKILL_DIR}/references/ui-rubric.md`](${CLAUDE_SKILL_DIR}/references/ui-rubric.md) |
| `--no-commit` | なし | APPROVE 時の自動コミットを無効化 |

## レビュータイプ自動判定

| 直前のアクティビティ | レビュータイプ | 観点 |
|--------------------|--------------|------|
| `harness-work` 後 | **Code Review** | Security, Performance, Quality, Accessibility, AI Residuals |
| `harness-plan` 後 | **Plan Review** | Clarity, Feasibility, Dependencies, Acceptance |
| タスク追加後 | **Scope Review** | Scope-creep, Priority, Feasibility, Impact |

## Review Governance Contract（必須）

`/harness-review` は「感想」ではなく合否判定の gate として動作する。
レビュー開始時に、以下の合格ラインを先に固定してから差分を読む。

### 明確な合格ライン

`APPROVE` は、次の条件をすべて満たす時だけ返す。

1. `critical` / `major` 指摘が 0 件
2. 仕様正本 (`spec_path`) または明示された `spec_skip_reason` と矛盾しない
3. `Plans.md` の該当 task / DoD / Depends と矛盾しない
4. 既存テスト、既存 UX、既存 CLI、既存設定、既存 docs のいずれにもデグレ証拠がない
5. 必要な自動検証が実行済み、または実行不能理由が具体的に記録されている
6. TeamAgent Debate を実行した場合、反対意見がすべて解消済み、または `minor` / `recommendation` として理由付きで格下げ済み

この合格ラインを満たせない場合は、曖昧に丸めず `REQUEST_CHANGES` を返す。

### TeamAgent Debate

変更内容が次のいずれかに当たる場合、TeamAgent を使って異なる見解を read-only でぶつける。
`--team-debate` が指定された場合は、条件に関係なく必ず実行する。

- product behavior / API / data model / permission / billing / external integration / tenant boundary を変える
- 仕様正本や Plans.md との対応が読み取りだけでは曖昧
- テスト、review gate、guardrail、release path、security-sensitive path を変える
- diff が 5 ファイル以上、または複数 role / skill / script / docs にまたがる
- Claude と Codex の verdict、または reviewer 内の観点別評価が割れた
- 1 件でも `critical` / `major` 候補がある

TeamAgent Debate は最低 2 視点、必要時 4 視点までに絞る。

| 視点 | 役割 |
|------|------|
| Spec Agent | 仕様正本と実装差分の矛盾を探す |
| Plans Agent | `Plans.md` の task / DoD / Depends と差分の対応を確認する |
| Regression Agent | 既存挙動・テスト・配布 mirror・CLI/skill UX のデグレを探す |
| Skeptic Agent | 「通したい」前提を疑い、過小評価されたリスクを探す |

Claude Code では `Task` tool を TeamAgent として使う。
Codex 環境で native TeamAgent が使えない場合でも、この gate を省略してはいけない。
Codex では `codex-companion.sh review`、利用可能な reviewer subagent、または明示的に分けた read-only review pass で同じ 2〜4 視点を再現し、`team_agent_mode` に `native` / `codex-companion` / `manual-pass` / `unavailable` のいずれかを記録する。
`unavailable` の場合は、その理由と代替確認を JSON に残す。

TeamAgent Debate の出力は、最終 JSON に `team_debate` として残す。

```json
{
  "team_debate": {
    "required": true,
    "mode": "native | codex-companion | manual-pass | unavailable",
    "agents": ["Spec Agent", "Plans Agent", "Regression Agent"],
    "disagreements": [
      {
        "topic": "Plans.md DoD alignment",
        "positions": ["Plans Agent: missing evidence", "Regression Agent: tests cover existing behavior"],
        "resolution": "REQUEST_CHANGES until evidence is added"
      }
    ]
  }
}
```

### Asktool / AskUserQuestion 境界

修正に意思決定が必要な場合は、推測で進めず `AskUserQuestion` を使う。
該当するのは次のケースだけ。

- 仕様正本の変更が必要
- `Plans.md` の task / DoD / Depends を変えないと合格できない
- product behavior / public API / permission / billing / data migration の選択肢が複数ある
- テストを削除・緩和・skip しないと通せない
- `REQUEST_CHANGES` の修正案がスコープ拡大や別 feature 追加になる

単純な実装ミス、テスト不足、mirror drift、docs 不整合は Ask せず `REQUEST_CHANGES` として修正ループに返す。

## Code Review フロー

### Step 1: 変更差分を収集

> **`BASE_REF=HEAD` fallback 時の注意**:
> Step 0.1 で `BASE_REF=HEAD` に設定されたパスに入ったときは、`git diff HEAD` が tracked 変更だけを返し untracked files を落とす。
> このステップの change enumeration と Step 1.5 の residual scan は、`git diff HEAD` の結果に加えて
> `${UNTRACKED_FILES}` (= `git ls-files --others --exclude-standard` の出力) のファイルも
> **個別に `cat` して review scope に含めること**。untracked ファイルの行数は `wc -l` で
> CHANGED_COUNT 上限チェックには含めず、レビュー本文だけに含める。
> `UNTRACKED_COUNT=0` の場合はこの手順をスキップしてよい。

```bash
# BASE_REF が harness-work から渡された場合はそれを使用、なければ HEAD~1 にフォールバック
CHANGED_FILES="$(git diff --name-only --diff-filter=ACMR "${BASE_REF:-HEAD~1}")"
git diff ${BASE_REF:-HEAD~1} --stat
git diff ${BASE_REF:-HEAD~1} -- ${CHANGED_FILES}

# BASE_REF=HEAD の場合: untracked files も個別に取得してレビュー範囲に含める
if [ "${BASE_REF}" = "HEAD" ] && [ -n "${UNTRACKED_FILES:-}" ]; then
  echo "--- untracked files (レビュー対象に追加) ---"
  printf '%s\n' "$UNTRACKED_FILES" | while IFS= read -r f; do
    echo "=== $f (untracked) ==="
    cat "$f" 2>/dev/null || echo "(読み取り不可)"
  done
fi
```

### Step 1.5: AI Residuals を静的走査

LLM の印象だけで判定せず、再実行できる形で残骸候補を拾う。`scripts/review-ai-residuals.sh` は stable な JSON を返すので、その結果をレビュー根拠として使う。

```bash
HARNESS_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$HARNESS_PLUGIN_ROOT" ] && [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
  HARNESS_PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
fi

# 差分ベース
AI_RESIDUALS_JSON="$(bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh" --base-ref "${BASE_REF:-HEAD~1}" --include-untracked)"

# 対象ファイルを明示したい場合
bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh" path/to/file.ts path/to/config.sh

# weak-supervision-report.v1 が出力されている場合
bash "${HARNESS_PLUGIN_ROOT}/scripts/review-weak-supervision-report.sh" path/to/weak-supervision-report.json
```

`--include-untracked` は `git ls-files --others --exclude-standard` の対象も同じ JSON に入れる。
`files_scanned` は tracked diff と untracked の合算、`untracked_files_scanned` は未追跡ファイルだけの証跡。
Claude 側・Codex 側とも、この JSON を読んで Step 2.2 の severity 判定に進む。

`weak-supervision-report.v1` がある場合は、`review-weak-supervision-report.sh` の JSON も確認する。
これは「テストは通ったが、本当に良い実装か」を見る採点表で、最終判定者は Reviewer のまま。
`APPROVE` なのに `evidence_refs` が空、`reward_score` が 0..1 の範囲外、privacy tag が未知、再現手順なしの bugfix claim がある場合は、レビューで明示する。

### Step 2: 8観点でレビュー

| 観点 | チェック内容 |
|------|------------|
| **Security** | SQLインジェクション, XSS, 機密情報露出, 入力バリデーション |
| **Performance** | N+1クエリ, 不要な再レンダリング, メモリリーク |
| **Quality** | 命名, 単一責任, テストカバレッジ, エラーハンドリング |
| **Accessibility** | ARIA属性, キーボードナビ, カラーコントラスト |
| **AI Residuals** | `mockData`, `dummy`, `fake`, `localhost`, `TODO`, `FIXME`, `it.skip`, `describe.skip`, `test.skip`, `expect(true).toBe(true)` のような中身のない成功、ハードコードされた秘密情報/環境依存 URL, 明らかな仮実装コメント |
| **Spec Alignment** | 仕様正本に基づいた変更か、仕様正本が不要な場合は skip 理由が妥当か |
| **Plans Alignment** | `Plans.md` の task / DoD / Depends と実装・検証証跡が一致しているか |
| **Regression Safety** | 既存機能・既存テスト・配布 mirror・CLI/skill UX にデグレがないか |

### Step 2.2: AI Residuals の severity 判定表

`AI Residuals` は、まず `scripts/review-ai-residuals.sh` の JSON を確認し、その後に diff 文脈で「本当に出荷リスクか」を最終判断する。

| 重要度 | 代表例 | 判定の考え方 |
|--------|--------|-------------|
| **major** | `localhost` / `127.0.0.1` / `0.0.0.0` の接続先、`it.skip` / `describe.skip` / `test.skip`、`expect(true).toBe(true)` などの hardcoded test pass、ハードコードされた秘密情報っぽい値、dev/staging 固定 URL | 本番事故、誤設定、検証抜けに直結しやすい。1 件でも `REQUEST_CHANGES` |
| **minor** | `mockData`, `dummy`, `fakeData`, `TODO`, `FIXME` | 残骸の可能性は高いが、即事故とは限らない。修正推奨だが verdict は変えない |
| **recommendation** | `temporary implementation`, `replace later`, `placeholder implementation` のような仮実装コメント | コメント単体では即バグ断定できないが、追跡・明確化を促したい |

### Step 2.3: 仕様正本 alignment check / Plans.md / デグレ alignment check

code review では、project spec SSOT があるかを確認する。
候補は `docs/spec/00-project-spec.md`、`docs/ARCHITECTURE.md`、`docs/HANDOFF.md`、`docs/oem/PROJECT_COMPASS.md`、`docs/specs/`。

確認すること:

- task が product behavior / API / data model / permission / billing / integration / tenant boundary を変える場合、`spec_path` または `spec_skip_reason` があるか
- `spec_path` がある場合、差分がその仕様正本と直接矛盾していないか
- 仕様正本が必要なのに無い場合、実装で勝手に product behavior を決めていないか
- `Plans.md` の該当 task / DoD / Depends と差分が一致しているか
- DoD に書かれた検証コマンド・配布 mirror・docs 反映が実際に行われているか
- 既存挙動の削除、既存テストの弱体化、配布 mirror の片肺更新、CLI/skill UX の後退がないか
- `Plans.md` 側が古く、正しい修正には plan 変更が必要な場合、`AskUserQuestion` で確認すべき意思決定か

| 重要度 | 代表例 | verdict への影響 |
|--------|--------|-----------------|
| **major** | 仕様正本に書かれた権限/契約/API と実装が明確に矛盾している、仕様正本が必要な task なのに `spec_path` も `spec_skip_reason` もない、`Plans.md` の DoD 未達、既存挙動のデグレ、配布 mirror の片肺更新 | 1 件でも → REQUEST_CHANGES |
| **minor** | spec link の書き方が弱いが、実装の正しさは contract / test / existing docs で確認できる、または Plans 参照の表記だけが弱い | verdict に影響しない |

### Step 2.4: TDD compliance check

code review で sprint-contract の `tdd_required=true` が確認できる場合は、TDD compliance を必ず確認する。
`tdd.enforce.enabled=true` の時は block 条件として扱い、無効時は evidence gap として記録する。

確認する evidence:

- 変更された source file に対応する test file があるか
- `.claude/state/tdd-red-log/<task-id>.jsonl` に直近の FAIL 記録があるか。age 設定が読めない時は 60 分を基準にする
- TDD を skip している場合、`skip_tdd_reason` または `[tdd:skip:<reason>]` が空でないか
- Worker の `self_review[]` に `tdd-red-evidence-attached` があり、evidence が Red log path または literal failing test output を指しているか

| 重要度 | 代表例 | verdict への影響 |
|--------|--------|-----------------|
| **critical** | `tdd_required=true` の code change なのに test file がない、直近 Red log がない、skip 理由がない、または `self_review` に Red 証跡がない | 1 件でも → REQUEST_CHANGES |
| **major** | Red log や test file の存在はあるが task-id / 対象 source との対応が曖昧で、Reviewer が同じタスクの証跡だと確認できない | 1 件でも → REQUEST_CHANGES |
| **minor** | 表示名や説明の改善だけで、Red / Green の証跡そのものはそろっている | verdict に影響しない |

> **重要**: minor の TDD advice だけで REQUEST_CHANGES にしてはいけない。
> TDD compliance で止めるのは critical / major に該当する時だけ。

### Step 2.5: 閾値基準による verdict 判定

各指摘を以下の重要度に分類し、**この基準のみ**で verdict を決定する。

| 重要度 | 定義 | verdict への影響 |
|--------|------|-----------------|
| **critical** | セキュリティ脆弱性、データ損失リスク、本番障害の可能性 | 1 件でも → REQUEST_CHANGES |
| **major** | 既存機能の破壊、仕様との明確な矛盾、テスト不通過 | 1 件でも → REQUEST_CHANGES |
| **minor** | 命名改善、コメント不足、スタイル不統一 | verdict に影響しない |
| **recommendation** | ベストプラクティス提案、将来の改善案 | verdict に影響しない |

> **重要**: minor / recommendation のみの場合は **必ず APPROVE** を返すこと。
> 「あったほうが良い改善」は REQUEST_CHANGES の理由にならない。
> `AI Residuals` でも同じ。`major` に入るのは「出荷事故や誤設定に直結しやすいもの」だけで、単なる残骸候補は `minor` または `recommendation` に留める。

### Step 2.6: TeamAgent Debate と合格ラインの確定

Step 2.3〜2.5 の結果から TeamAgent Debate が必要か判定する。
必要な場合は Review Governance Contract の TeamAgent Debate を実行し、合格ラインごとに `pass` / `fail` / `not_applicable` を記録する。

最終 verdict は次の順で決める。

1. `critical` / `major` が 1 件以上ある → `REQUEST_CHANGES`
2. 仕様正本 / Plans.md / デグレ gate のいずれかが `fail` → `REQUEST_CHANGES`
3. TeamAgent Debate の未解消 disagreement が `critical` / `major` 相当 → `REQUEST_CHANGES`
4. 意思決定が必要で Ask 未実施 → `REQUEST_CHANGES` ではなく `decision_needed` として AskUserQuestion を実行
5. 上記すべてを満たす → `APPROVE`

### Step 3: レビュー結果出力

#### 出力順序 (絶対遵守)

レビュー結果は**必ず以下の順序で出力**する:

> **注**: bare 呼び出し時の `REVIEW_AUTOSTART` handshake 行（Step 0 の auto-start マーカー）は Step 3 の出力順序の対象外。handshake 行（1 行）を出力した後、以下の順序でレビュー結果を出力する。

1. **🎯 結果サマリー** (日本語、レビュー結果の最初に出力)
2. JSON 出力 (機械可読 schema-v1 形式、サマリーの後)
3. 観点別評価の詳細 (任意、日本語)

#### 1. 結果サマリーテンプレート (必須、最初に出力)

**設計方針**: 非専門家にもわかるように、**情報粒度 MID / 認知負荷 MIN** を意識。結論を最上段、安心材料(良かったこと)を先、問題点は日本語タイトル→平易な説明→アクション→技術詳細の 4 段で隔離。

以下のテンプレートで出力する:

```markdown
## 🎯 レビュー結果

### {✅ 合格 (APPROVE) | ❌ 要修正 (REQUEST_CHANGES)} — {1 行の日本語結論}

例: ✅ 合格 (APPROVE) — 10 commits 全てがテストを通過し、リリース可能な品質です

**対象**: `{BASE_REF}..HEAD` の {N} commits、{M} ファイル変更 (+{INS}/-{DEL} 行)
**レビュー種別**: コードレビュー / プランレビュー / スコープレビュー / セキュリティレビュー / デュアルレビュー

---

### ✨ 良かったところ

{2〜3 件、非専門家にもわかる日本語で。何が良かったか 1 行ずつ}

- {ポイント 1: 具体的に評価できる変更点を平易に}
- {ポイント 2}
- {ポイント 3}

### ⚠️ 気になったところ ({X} 件)

{0 件なら「特になし — すべてクリーンです 🎉」と 1 行で明記して次のセクションへ}

{1 件以上ある場合、重要度順に最大 3 件。各項目は以下の 4 段構造を厳守}

#### 1. {日本語のタイトル: 技術用語を避け、何が問題か一読でわかる表現}

**問題**: {技術用語を使わず、何が起きているか・起きうる影響を 1〜2 文で説明}

**対応**: {具体的な次のステップを日本語で。動詞で始める。例: 「〜を修正する」「〜を別タスクとして起票する」}

**重要度**: {🔴 致命的 | 🟠 重要 | 🟡 軽微 | 🟢 推奨}

**技術的位置 (開発者向け)**: `{file_path}:{line}` — {1 行の技術要約}

#### 2. ...

### 🎬 次のアクション

{1〜3 項目、日本語、動詞で始める。リリース可否の判断もここに含める}

1. {アクション 1}
2. {アクション 2}
3. {アクション 3}

### 📊 自動検証の結果

{チェックリスト形式、日本語表記}

- ✅ Go テスト ({N} packages): 全パス
- ✅ プラグイン検証: {合格数} 件合格 / {失敗数} 件失敗
- ✅ 整合性チェック: 全パス
- ✅ AI 残骸スキャナ: {件数} 件

---

### 📦 詳細データ (開発者・ツール連携向け、非専門家は読み飛ばし可)

<!-- ここから先は任意。JSON・観点別評価・ファイル一覧などを配置 -->
```

**禁止事項 (非専門家向け UX を守るため)**:
- ❌ JSON 出力を最初に出すこと — 必ず結果サマリーより後、「📦 詳細データ」セクション内に配置
- ❌ 結果サマリー本文を英語で書くこと — 見出し・説明・アクションすべて日本語
- ❌ 判定や主要指摘を JSON の中に埋めてサマリーを省略すること
- ❌ 観点別評価の後に結論を添えること — 結論は必ず最初
- ❌ 「気になったところ」の **本文**(問題・対応の説明) で技術用語を説明なしに使うこと
  - 例の悪い書き方: 「`validTargets` が kebab-case を期待しているため `HookEventName` と一致しない」
  - 例の良い書き方: 「フック名の大文字小文字が揃わず、機能が動いていない可能性があります」
  - 技術用語は「技術的位置 (開発者向け)」欄に隔離すれば OK
- ❌ `critical` / `major` / `minor` / `recommendation` の英単語を本文で使うこと
  - 代わりに「🔴 致命的」「🟠 重要」「🟡 軽微」「🟢 推奨」の日本語+絵文字表記を使用
- ❌ 「良かったところ」セクションを省略すること — APPROVE 時は必ず 2〜3 件の具体的な評価点を列挙(安心材料として非専門家に必要)

**ベースリファレンス透明性**: bare 呼び出しで Step 0.1 の上限フォールバックが発動した場合 (`>10 commits → HEAD~10`)、「対象」行には元の候補 ref と絞込後を併記すること。例: `対象: HEAD~10..HEAD (v4.0.0 から 21 commits のうち直近 10 を対象)`

#### 2. JSON 出力 (schema-v1、「📦 詳細データ」セクション内)

```json
{
  "schema_version": "review-result.v1",
  "verdict": "APPROVE | REQUEST_CHANGES",
  "reviewer_profile": "static | runtime | browser | security | ui-rubric",
  "calibration": {
    "label": "false_positive | false_negative | missed_bug | overstrict_rule",
    "source": "manual | post-review | retrospective",
    "notes": "観察メモ",
    "prompt_hint": "few-shot に使う要点",
    "few_shot_ready": true
  },
  "critical_issues": [],
  "major_issues": [],
  "observations": [
    {
      "severity": "critical | major | minor | recommendation",
      "category": "Security | Performance | Quality | Accessibility | AI Residuals",
      "location": "ファイル名:行番号",
      "issue": "問題の説明",
      "suggestion": "修正案"
    }
  ],
  "recommendations": ["必須ではない改善提案"]
  ,
  "acceptance_bar": {
    "critical_major_zero": true,
    "spec_alignment": "pass | fail | not_applicable",
    "plans_alignment": "pass | fail | not_applicable",
    "regression_safety": "pass | fail | not_applicable",
    "verification_evidence": "pass | fail | not_applicable"
  },
  "team_debate": {
    "required": false,
    "mode": "native | codex-companion | manual-pass | unavailable",
    "agents": [],
    "disagreements": []
  },
  "decision_needed": {
    "required": false,
    "ask_tool": "AskUserQuestion",
    "question": null
  }
}
```

browser review の場合は `scripts/generate-browser-review-artifact.sh` が `browser_mode` と route / required artifacts を決め、その後に `scripts/write-review-result.sh` で `.claude/state/review-result.json` に正規化して保存する。
このファイルは commit guard と後続フローの共通入力になる。
`calibration` が付くレビュー結果は `scripts/record-review-calibration.sh` で
`.claude/state/review-calibration.jsonl` に追記し、`scripts/build-review-few-shot-bank.sh`
で few-shot bank を更新する。

### Step 3.5: --dual フラグ時の Codex 並行レビュー

`--dual` フラグが指定されている場合、Step 3 の Claude レビューと並行して Codex レビューを実行し、結果をマージする。
さらに Review Governance Contract の条件に当たる場合は TeamAgent Debate も実行する。

1. Codex の利用可否を確認する（`scripts/codex-companion.sh setup --json`）
2. 利用可能であれば `scripts/codex-companion.sh review --base "${BASE_REF:-HEAD~1}"` を起動
3. 両方の verdict を Verdict マージルールで統合する
4. 最終レビュー結果に `dual_review` フィールドを付加する

詳細な手順・出力スキーマ・フォールバック仕様は [`${CLAUDE_SKILL_DIR}/references/dual-review.md`](${CLAUDE_SKILL_DIR}/references/dual-review.md) を参照。

### Step 3.6: --security フラグ時のセキュリティ専用レビュー

`--security` フラグが指定された場合、通常の 5 観点レビューを **スキップ**し、セキュリティ専用フローを実行する。

**Read-only 制約**: このフロー中は Write / Edit / 書き込み系 Bash を一切実行しない。

1. セキュリティプロファイルを読み込む:
   ```
   Read: ${CLAUDE_SKILL_DIR}/references/security-profile.md
   ```
2. OWASP Top 10 全カテゴリを変更差分・関連ファイルに対して確認する
3. 認証・認可フロー、秘密情報取り扱い、依存パッケージ脆弱性をチェックする
4. `reviewer_profile: "security"` を設定して結果を出力する（Step 3 の JSON スキーマに準拠）
5. Security モードの verdict 判定基準（security-profile.md 末尾参照）を適用する

通常の Code Review と `--security` の使い分け:

| | 通常の Code Review | `--security` |
|---|---|---|
| 観点 | Security, Performance, Quality, Accessibility, AI Residuals | Security のみ（OWASP Top 10 全項目） |
| 深度 | セキュリティは概要チェック | 認証・認可・暗号化・依存関係まで網羅 |
| ツール制限 | なし | Read / Grep / Glob / 読み取り Bash のみ |
| 用途 | PR マージ前の総合確認 | セキュリティ集中監査・リリース前の追加確認 |

### Step 3.7: --ui-rubric フラグ時の 4 軸デザインレビュー

`--ui-rubric` フラグが指定された場合、通常の 5 観点レビューを **スキップ**し、UI/デザイン品質に特化した 4 軸レビューを実行する。

1. UI rubric プロファイルを読み込む:
   ```
   Read: ${CLAUDE_SKILL_DIR}/references/ui-rubric.md
   ```
2. `Design Quality / Originality / Craft / Functionality` の 4 軸を 0-10 で採点する
3. `review.rubric_target` がある場合はその閾値と比較し、無ければ 4 軸すべての default threshold=6 を使う
4. 1 軸でも target 未達なら `REQUEST_CHANGES`、全軸到達で `APPROVE`
5. `reviewer_profile: "ui-rubric"` を設定して Step 3 の JSON スキーマで結果を出力する

通常の Code Review と `--ui-rubric` の使い分け:

| | 通常の Code Review | `--ui-rubric` |
|---|---|---|
| 観点 | Security, Performance, Quality, Accessibility, AI Residuals | Design Quality, Originality, Craft, Functionality |
| 判定方法 | 問題の重みで verdict 決定 | 4 軸の点数と threshold 比較 |
| 向いている対象 | 実装全般、PR 総合確認 | UI・スタイリング・レイアウト・見た目品質 |
| 用途 | 仕様逸脱やバグの洗い出し | 体験品質と見た目の完成度評価 |

### Step 4: 修正ループとコミット判定

- **APPROVE**: 自動コミット実行（`--no-commit` でなければ）
- **REQUEST_CHANGES**: critical/major の指摘箇所と修正方針を提示。`harness-work` の修正ループで自動修正後に、Step 1 から修正後再レビューを実行する（最大 3 回）
- **decision_needed**: 修正に意思決定が必要な場合は `AskUserQuestion` を実行し、回答後に `harness-plan` / `harness-work` / `harness-review` の順で再開する

修正ループでは、同じ issue を 2 回連続で落とした場合に TeamAgent Debate を強制する。
3 回目の `REQUEST_CHANGES` 後も合格ライン未達なら、Lead は自走を止めて escalation する。

## Plan Review フロー

1. Plans.md を読み込む
2. 以下の **5 観点** でレビュー:
   - **Clarity**: タスク説明が明確か
   - **Feasibility**: 技術的に実現可能か
   - **Dependencies**: タスク間の依存関係が正しいか（Depends カラムと実際の依存が一致しているか）
   - **Acceptance**: 完了条件（DoD カラム）が定義され、検証可能か
   - **Value**: このタスクはユーザー課題を解くか？
     - 「誰の、どんな問題」が明示されているか
     - 代替手段（作らない選択肢）は検討されたか
     - Elephant（全員気づいているが放置されている問題）はないか
3. DoD / Depends カラムの品質チェック:
   - DoD が空欄のタスク → 警告（「完了条件が未定義です」）
   - DoD が検証不能（「いい感じ」「ちゃんと動く」等） → 警告 + 具体化提案
   - Depends に存在しないタスク番号 → エラー
   - 循環依存 → エラー
4. 改善提案を提示

## Scope Review フロー

1. 追加されたタスク/機能をリスト化
2. 以下の観点で分析:
   - **Scope-creep**: 当初スコープからの逸脱
   - **Priority**: 優先度は適切か
   - **Feasibility**: 現在のリソースで実現可能か
   - **Impact**: 既存機能への影響
3. リスクと推奨アクションを提示

## 異常検知

| 状況 | アクション |
|------|----------|
| セキュリティ脆弱性 | 即座に REQUEST_CHANGES |
| テスト改ざん疑い | 警告 + 修正要求 |
| force push 試み | 拒否 + 代替案提示 |

## Codex Environment

Codex CLI 環境（`CODEX_CLI=1`）では一部ツールが利用不可のため、以下のフォールバックを使用する。

| 通常環境 | Codex フォールバック |
|---------|-------------------|
| `TaskList` でタスク一覧取得 | Plans.md を `Read` して WIP/TODO タスクを確認 |
| `TaskUpdate` でステータス更新 | Plans.md のマーカーを `Edit` で直接更新（例: `cc:WIP` → `cc:完了`） |
| レビュー結果を Task に書き込み | レビュー結果を stdout に出力 |
| TeamAgent Debate | Codex reviewer subagent / `codex-companion.sh review` / explicit manual review pass で同じ視点を再現 |
| `AskUserQuestion` | 利用不可なら `decision_needed.v1` を stdout に出し、推測で修正しない |

### 検出方法

```bash
if [ "${CODEX_CLI:-}" = "1" ]; then
  # Codex 環境: Plans.md ベースのフォールバック
fi
```

### Codex 環境でのレビュー出力

Task ツール非対応のため、レビュー結果は標準出力にマークダウン形式で出力する。
Lead エージェントまたはユーザーが結果を読み取り、次のアクションを判断する。
ただし合格ライン、仕様正本、Plans.md、デグレ、修正後再レビュー、AskUserQuestion / `decision_needed.v1` の契約は Claude 環境と同じ。

## `/ultrareview` との関係（方針 B: Harness flow 内では呼ばない）

CC 2.1.111 で追加された built-in `/ultrareview` は、ユーザーが CC に直接アドホックなレビューを
求める operator entrypoint として設計されている（`.claude/rules/opus-4-7-prompt-audit.md` ルール 5 参照）。

Harness の自動レビューフローは `/ultrareview` を**呼び出さない**。理由は以下の通り:

- `/ultrareview` の出力スキーマは `review-result.v1` と非互換であり、Harness の修正ループ・
  commit guard・sprint-contract 検証に接続できない
- Harness flow 内のレビューは `codex-companion.sh review`（優先）と `reviewer` agent
  （`review-result.v1` 出力・フォールバック）でカバーしており、追加の呼び出しパスは不要
- `/ultrareview` を Harness 内部で呼ぶと `review-result.v1` の機械可読保証が失われる

ユーザーがアドホックなレビューに `/ultrareview` を使う場合、Harness は干渉しない。
`claude ultrareview [target] --json` は CI / script から同じアドホックレビューを機械的に呼ぶための
second-opinion 入口であり、`/harness-review` の Plans.md 連動、修正ループ、`review-result.v1` 契約を置き換えない。
詳細な差分・使い分けガイドは plugin root の `docs/ultrareview-policy.md`
（`${CLAUDE_PLUGIN_ROOT}/docs/ultrareview-policy.md`）を参照。

## Hook output governance

Review / test evidence を扱う hook は `PostToolUse.hookSpecificOutput.updatedToolOutput` を既定では使わない。
tool output の redaction / compaction / normalization が必要な場合だけ opt-in し、
元出力または復元可能な audit trail を残す。
`pytest` / `vitest` / `go test` / review finding の失敗根拠、file:line、exit code を消してはいけない。
詳細は plugin root の `docs/output-governance.md` を参照。

## 関連スキル

- `harness-work` — レビュー後に修正を実装
- `harness-plan` — 計画を作成・修正
- `harness-release` — レビュー通過後にリリース
