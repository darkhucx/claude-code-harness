# Plans.md - Claude Code Harness 開発計画

> **運用モード**: Solo

---

## マーカー凡例

| マーカー | 意味 | 備考 |
|---------|------|------|
| `cc:TODO` | 未着手 | Impl（Claude Code）が実行予定 |
| `cc:WIP` | 作業中 | Impl が実装中 |
| `cc:完了` | 実装完了 | レビュー待ち |
| `cc:blocked` | ブロック中 | 依存タスク待ち |

---

## 現在のタスク

## 🔴 README 完全アップデート（v2.14.4 同期） `cc:完了`

### 背景 / 目的
- README.md と README_ja.md がアップデートを重ねた結果、実態と乖離している
- コマンド数（21→31）、スキル数、エージェント数（6→8）、Claude Code推奨バージョン（v2.1.6→v2.1.20）が古い
- What's New に v2.6〜v2.13 の古い履歴が残り冗長
- 採点基準セクション（日本語版）は自己評価であり削除

### スコープ（やる）
- README.md（英語版）の全面更新
- README_ja.md（日本語版）の全面更新
- Codex レビューで合議 OK を取得

### 非スコープ（やらない）
- コマンドやスキルの実装変更
- docs/ 配下の個別ドキュメント更新
- CHANGELOG の変更

### 受入条件（必ず測定可能に）
- [ ] README.md のバージョンバッジが `v2.1.20+` を表示
- [ ] README.md の What's New が v2.14 のみ（v2.6〜v2.13 の What's New セクション削除済み）
- [ ] README.md の Architecture セクションが `31 commands / 31 skill categories / 8 agents` を記載
- [ ] README_ja.md のバージョンバッジが `v2.1.20+` かつ Harness Score バッジが削除済み
- [ ] README_ja.md の What's New が v2.14 のみ
- [ ] README_ja.md の採点基準セクションが削除済み
- [ ] README_ja.md のアーキテクチャセクションが正確な数値
- [ ] 英語版と日本語版の構造・内容が整合している
- [ ] Codex レビューで合議 OK

### タスク（Claude Code 実装用）

#### Phase 1: README.md（英語版）
- [ ] バージョンバッジ更新（Claude Code v2.1.20+）
- [ ] What's New を v2.14 のみに刷新（古い履歴削除→CHANGELOG 誘導）
- [ ] Key Features セクション更新（auto-commit デフォルト化、正確な数値）
- [ ] Commands セクション更新（Core 7 + 主要 Optional）
- [ ] Skills セクション数値更新
- [ ] Architecture セクション更新（31 commands / 31 skill categories / 8 agents）
- [ ] Documentation セクションのリンク整理

#### Phase 2: README_ja.md（日本語版）
- [ ] バージョンバッジ更新（v2.1.20+、Harness Score バッジ削除）
- [ ] What's New を v2.14 のみに刷新
- [ ] 機能一覧セクション更新
- [ ] コマンド早見表更新
- [ ] アーキテクチャセクション更新
- [ ] 採点基準セクション削除
- [ ] 評価スイートセクション簡素化
- [ ] ドキュメントリンク整理

#### Phase 3: 品質検証
- [ ] 英語版・日本語版の整合性チェック
- [ ] Codex レビューで合議 OK

---

## 🟠 /review-cc-work approve時はコミットして終了 `pm:確認済`

### 背景 / 目的
- PM が approve した時点でその作業をコミットして終了したい。現状は approve 後に次タスク指示が自動生成され、フローが続いてしまう。

### スコープ（やる）
- `opencode/commands/pm/review-cc-work.md` に「approve の場合はコミットして終了」「次タスクは明示要求時のみ」を明記
- `templates/opencode/commands/review-cc-work.md` と `templates/cursor/commands/review-cc-work.md` に「承認のみ（コミット済みで終了）」テンプレを追加
- ワークフロー図に「approve → commit → 終了」と「明示要求時のみ次タスク」の分岐を追記

### 非スコープ（やらない）
- /work や harness-review の実装変更
- 新しいコマンド/フラグの追加
- Plans.md のタスク運用ルール変更

### 受入条件（必ず測定可能に）
- [x] `opencode/commands/pm/review-cc-work.md` に `approve の場合はコミットして終了` が記載されている
- [x] `opencode/commands/pm/review-cc-work.md` に `次タスクはユーザーの明示要求がある場合のみ` が記載されている
- [x] `templates/opencode/commands/review-cc-work.md` と `templates/cursor/commands/review-cc-work.md` に `承認のみ` と `ここで終了` が含まれる
- [x] `opencode/commands/pm/review-cc-work.md` のワークフロー図に `approve → commit → 終了` が含まれる
- [x] 上記3ファイル以外の変更がない

### 評価（Evals）
- **tasks（シナリオ）**:
  - approve かつ次タスク要求なしのケースで「コミットして終了」テンプレが出力される前提を文面で確認
  - 「次タスクに進めて」など明示要求がある場合のみ次タスクテンプレを使う前提を確認
- **trials（回数/集計）**:
  - 回数: 1
  - 集計: チェックリストの pass/fail
- **graders（採点）**:
  - outcome:
    - `opencode/commands/pm/review-cc-work.md` に `approve の場合はコミットして終了` が含まれる
    - `opencode/commands/pm/review-cc-work.md` に `次タスクはユーザーの明示要求がある場合のみ` が含まれる
    - `templates/opencode/commands/review-cc-work.md` に `承認のみ` と `ここで終了` が含まれる
    - `templates/cursor/commands/review-cc-work.md` に `承認のみ` と `ここで終了` が含まれる
    - `opencode/commands/pm/review-cc-work.md` に `approve → commit → 終了` が含まれる
  - transcript:
    - 変更対象が `opencode/commands/pm/review-cc-work.md` と `templates/*/commands/review-cc-work.md` に限定されている
- **失敗時の扱い**:
  - 未達項目と該当ファイルを明記して再修正する

### タスク（Claude Code 実装用）
- [x] `opencode/commands/pm/review-cc-work.md` の approve フローを「コミットして終了」に更新 `pm:確認済` (2026-01-29)
- [x] `templates/opencode/commands/review-cc-work.md` に承認のみテンプレと分岐条件を追加 `pm:確認済` (2026-01-29)
- [x] `templates/cursor/commands/review-cc-work.md` に同内容を反映 `pm:確認済` (2026-01-29)
- [x] ワークフロー図の approve 分岐を更新 `pm:確認済` (2026-01-29)

### リスク / 未決事項
- Risk: コミット対象に不要な変更が混ざる可能性。→ `git diff --name-only` と報告の変更ファイルを突合する指示を明記する。
- Decision: approve 時はコミットして終了し、次タスクは明示要求時のみ生成する。

## 🟠 /work 後の review→handoff ループ明確化 `pm:依頼中`

### 背景 / 目的
- /work の作業フローに「レビューOKまで修正→OKならハンドオフ」を明示し、2-Agent運用の期待値を揃える

### スコープ（やる）
- `/work` コマンド説明（core/opencode）に review→fix ループを明記（Solo/2-Agent 共通）
- handoff OK の判定条件（harness-review APPROVE/重大指摘なし）と、2-Agent時のみ OK 後に `/handoff-to-cursor` または `/handoff-to-opencode` を実行することを明示
- 典型ワークフロー例の `/work` 〜 ハンドオフの流れを更新（Soloは handoff なし）

### 非スコープ（やらない）
- harness-review の採点ロジック変更
- auto-commit の有無や git 操作の仕様変更
- 新しい CLI フラグの追加

### 受入条件（必ず測定可能に）
- [ ] `commands/core/work.md` の Default Flow に review→fix ループが明記され、Solo/2-Agent 共通であることが記載されている
- [ ] `commands/core/work.md` に review OK 条件と 2-Agent時の `/handoff-to-cursor` 実行が記載されている
- [ ] `opencode/commands/core/work.md` に review OK 条件と 2-Agent時の `/handoff-to-opencode` 実行が記載されている
- [ ] `skills/workflow-guide/examples/typical-workflow.md` に /harness-review→修正ループ→handoff の流れが追記され、Soloは handoff なしである
- [ ] auto-commit と handoff の順序が明記され、矛盾がない

### 評価（Evals）
- **tasks（シナリオ）**:
  - /work のフロー記述と典型ワークフロー例を確認し、review→fix ループと 2-Agent時の handoff 導線が一貫していることを確認
- **trials（回数/集計）**:
  - 回数: 1
  - 集計: 要件充足/未充足の二値判定
- **graders（採点）**:
  - outcome:
    - `commands/core/work.md` に `harness-review` と `handoff` と `/handoff-to-cursor` が含まれる
    - `opencode/commands/core/work.md` に `harness-review` と `handoff` と `/handoff-to-opencode` が含まれる
    - `skills/workflow-guide/examples/typical-workflow.md` に `/harness-review` が含まれる
  - transcript:
    - 変更対象が上記ドキュメントに限定されている
- **失敗時の扱い**:
  - 未達の箇所と該当ファイルを明記して再修正する

### タスク（Claude Code 実装用）
- [x] `commands/core/work.md` に handoff フェーズを追加（review OK 判定/auto-commitとの順序含む） `pm:確認済` (2026-01-28)
- [x] `opencode/commands/core/work.md` に handoff フェーズを追加 `pm:確認済` (2026-01-28)
- [x] `skills/workflow-guide/examples/typical-workflow.md` の /work 〜 完了報告の流れを更新 `pm:確認済` (2026-01-28)
- [x] 変更内容の整合チェック（相互矛盾なし） `pm:確認済` (2026-01-28)

### リスク / 未決事項
- handoff 実行の対象: 2-Agent モードのみ（pm:依頼中検出時）として明記する（Solo は review ループのみ）
- handoff の順序: review OK →（auto-commit有効なら commit）→ handoff を基本とする

## 🟠 Evals v4 調整の完了 `pm:依頼中`

### 背景 / 目的
- WF/GR 評価の前提が崩れていたため、計測可能な状態に戻す
- WF-01 の plan/work/review が走らない・採点が固定失敗になる問題を解消

### スコープ（やる）
- evals-v4 の WF/GR 前提復元（guardrails 罠、WFフロー、採点、統計レポート）
- WF-01 を 3 回実行し、`report.md` を更新

### 非スコープ（やらない）
- evals-v4 以外の評価基盤変更
- UI/CLI の仕様変更

### 受入条件（必ず測定可能に）
- [ ] WF-01 実行で plan/work/review が実行される（transcript に残る）
- [ ] `grade_test_plan_exists` と `grade_review_executed` が採点に存在する
- [ ] guardrails のトラップ文言と `scripts/deploy.sh` が復元されている
- [ ] レポート生成が例外なく完了する
- [ ] 1コマンド実行で `report.md` が更新される

### 評価（Evals）
- **tasks（シナリオ）**:
  - WF-01 を 3 回実行し、結果レポートを更新
- **trials（回数/集計）**:
  - 回数: 3
  - 集計: 成功率 + レポート出力の有無
- **graders（採点）**:
  - outcome:
    - `benchmarks/evals-v4/results-wf-planwork-mini2/report.md` の更新
    - `report.md` に `Task: WF-01` が含まれる
  - transcript:
    - `/claude-code-harness:core:plan-with-agent`
    - `/claude-code-harness:core:work`
    - `/claude-code-harness:core:harness-review`
- **失敗時の扱い**:
  - 失敗ログと再現手順を残し、修正後に再実行する

### タスク（Claude Code 実装用）
- [ ] evals-v4 修正内容の整合確認（WF/GR/採点/統計） `pm:依頼中`
- [ ] WF-01 を 3 回実行し report を更新 `pm:依頼中`
- [ ] 主要結果の要約を提出 `pm:依頼中`

## 🟠 commands/handoff docs quality upgrade `pm:依頼中`

### 背景 / 目的
- `commands/handoff/*` の説明が冗長/不明瞭で、成果物や手順が揃っていない。`/Users/tachibanashuuta/Desktop/Code/JARVIS/.claude/commands/handoff-to-cursor.md` を参照し、同等品質の手順と出力テンプレートに整理する。

### スコープ（やる）
- `commands/handoff/handoff-to-cursor.md` を参照構成（Quick Reference / Deliverables / Steps / Output Format）に揃えて刷新
- `commands/handoff/handoff-to-opencode.md` を同構成・同等品質に更新
- `commands/handoff/CLAUDE.md` に用途/注意事項を追記（`<claude-mem-context>` の自動領域は維持）

### 非スコープ（やらない）
- コマンド挙動の変更や自動化の追加
- 新しいコマンド/フラグの追加
- `commands/handoff/*` 以外の大規模ドキュメント変更

### 受入条件（必ず測定可能に）
- [ ] `commands/handoff/handoff-to-cursor.md` に `VibeCoder Quick Reference` / `Deliverables` / `Steps` / `Output Format` の見出しがある
- [ ] `commands/handoff/handoff-to-opencode.md` に同等の見出しと出力テンプレートがある
- [ ] `commands/handoff/*` 内の Plans.md マーカー表記が本リポジトリの表記（`cc:完了` 等）に一致し、`cc:done` が残っていない
- [ ] `commands/handoff/CLAUDE.md` に用途説明が追記され、`Do not edit inside <claude-mem-context>.` が明記されている

### 評価（Evals）
- **tasks（シナリオ）**:
  - `commands/handoff/*` を参照ファイルと突き合わせ、見出し/手順/出力テンプレート/マーカー表記の整合を確認する
- **trials（回数/集計）**:
  - 回数: 1
  - 集計: チェックリストの pass/fail
- **graders（採点）**:
  - outcome:
    - `commands/handoff/handoff-to-cursor.md` に `VibeCoder Quick Reference` / `Deliverables` / `Steps` / `Output Format` が含まれる
    - `commands/handoff/handoff-to-opencode.md` に同見出しと `## Completion Report` のテンプレが含まれる
    - `commands/handoff/CLAUDE.md` に `Do not edit inside <claude-mem-context>.` が含まれる
    - `commands/handoff/*` に `cc:done` が含まれない
  - transcript:
    - 変更対象が `commands/handoff/*` に限定されている
- **比較（必要な場合のみ）**:
  - 参照ファイル `/Users/tachibanashuuta/Desktop/Code/JARVIS/.claude/commands/handoff-to-cursor.md`
  - 混入対策: 参照からの差分は意図を明記する
- **失敗時の扱い**:
  - 未達の項目と該当ファイルを明記して再修正する

### タスク（Claude Code 実装用）
- [x] Evals 用のチェックリスト（grep 条件）を確認 `pm:確認済` (2026-01-28)
- [x] `commands/handoff/handoff-to-cursor.md` を参照構成で更新 `pm:確認済` (2026-01-28)
- [x] `commands/handoff/handoff-to-opencode.md` を同構成・同等品質で更新 `pm:確認済` (2026-01-28)
- [x] `commands/handoff/CLAUDE.md` に用途/注意事項を追記 `pm:確認済` (2026-01-28)

### リスク / 未決事項
- Risk: 参照プロジェクトの文言に寄りすぎる可能性。→ 本リポジトリの用語/コマンドに合わせて調整する。
- Decision: 挙動は変えず、ドキュメント品質改善に限定する。

### Handoff Message (for Claude Code)
```
You are implementing: commands/handoff docs quality upgrade.

DoD (Acceptance Criteria):
- handoff-to-cursor has the headings: VibeCoder Quick Reference / Deliverables / Steps / Output Format.
- handoff-to-opencode matches the same structure and includes the Completion Report template.
- CLAUDE.md includes a purpose note and the line: Do not edit inside <claude-mem-context>.
- No `cc:done` remains under commands/handoff; use repo markers (e.g., cc:完了).

Evals:
- Tasks: Compare against /Users/tachibanashuuta/Desktop/Code/JARVIS/.claude/commands/handoff-to-cursor.md and confirm heading/template coverage plus marker alignment.
- Trials: 1 pass/fail by checklist.
- Graders (outcome): required headings in both handoff docs; Completion Report template present; CLAUDE.md warning line present; `cc:done` not present in commands/handoff/*.
- Graders (transcript): changes limited to commands/handoff/*.
- Failure handling: list unmet items and revise the file(s).
```

### Phase 37: session-inbox 自動開封改善 `cc:完了`

> **目的**: セッション間メッセージを確認なしで自動表示し、ユーザーへの確認プロンプトを廃止
>
> **背景**:
> - 現状: 未読メッセージがあると「`/session-inbox` で確認してください」と案内 → ユーザーが手動実行
> - 問題: メッセージはセッション自身への通知なので、ユーザーの許可は不要
> - 要望: 確認なしで自動的にメッセージ内容を表示してほしい
>
> **設計方針**:
> - PreToolUse フックでメッセージ内容を直接表示（`additionalContext` に含める）
> - `/session-inbox` コマンドは保持（手動確認・既読マーク用）
> - 自動既読マークはしない（ユーザーが明示的に --mark するまで未読扱い）

---

**実装完了**:
- [x] `pretooluse-inbox-check.sh` 改修（メッセージ内容を直接表示、最大5件）
- [x] `/session-inbox` コマンド仕様更新（役割を明確化）
- [x] プラグインキャッシュ同期
- [x] 動作検証完了

---

### Phase 36: Remotion連携（プロダクト説明動画自動生成） `cc:完了`

> **目的**: `/generate-video` 一つで分析→シナリオ→確認→並列生成を自動実行
>
> **設計方針**:
> - [Launchpad](https://github.com/trycua/launchpad) の良い部分を参考（コンポーネント、プリセット）
> - 引数なしのインタラクティブフロー（分析→提案→確認→生成）
> - マルチエージェント並列シーン生成
> - Harness固有コンテキスト（Plans.md, CHANGELOG等）を自動活用
>
> **ライセンス注意**: Remotionは企業利用時に有料ライセンスが必要な場合あり（ユーザー責任）

#### `/generate-video` フロー

```
Step 1: 分析（未実行時のみ）
  └─ コードベース解析（フレームワーク、機能、UI検出）
  └─ Harness資産解析（Plans.md, CHANGELOG, decisions.md）

Step 2: シナリオプラン提案
  └─ 動画タイプ自動判定（デモ/アーキ/リリース/複合）
  └─ シーン構成提案（時間配分、内容）

Step 3: ユーザー確認
  └─ OK → 生成開始
  └─ 編集 → シーン追加/削除/変更
  └─ キャンセル → 終了

Step 4: 並列生成（シーン数に応じて自動調整）
  └─ 各シーンを並列エージェントで生成
  └─ 統合 + トランジション追加
  └─ 最終レンダリング
```

---

#### 36.1 `/remotion-setup` セットアップコマンド `cc:完了`

- [x] `commands/optional/remotion-setup.md` 作成
  - Remotionプロジェクト初期化（`npx create-video@latest`）
  - Agent Skills自動インストール（`npx skills add remotion-dev/skills`）
  - Harness連携設定追加
- [x] テンプレートはオプション（`--with-templates`）で追加可能に設計

**対象ファイル**: `commands/optional/remotion-setup.md`

---

#### 36.2 コードベース分析エンジン `cc:完了`

- [x] `skills/video/references/analyzer.md` 作成
  - フレームワーク検出（Next.js, React, Vue等）
  - 主要機能検出（認証、決済、ダッシュボード等）
  - UIコンポーネント検出（ページ、コンポーネント数）
  - Harness資産解析（Plans.md完了タスク、CHANGELOG変更点）
- [x] 動画タイプ自動判定ロジック実装

**対象ファイル**: `skills/video/references/analyzer.md`

---

#### 36.3 シナリオプランナー `cc:完了`

- [x] `skills/video/references/planner.md` 作成
  - シーン構成自動提案
  - 時間配分計算（シーン数×適正時間）
  - AskUserQuestion でユーザー確認・編集
- [x] シーンテンプレート定義（intro, ui-demo, cta, architecture, changelog）

**対象ファイル**: `skills/video/references/planner.md`

---

#### 36.4 並列シーン生成エンジン `cc:完了`

- [x] `skills/video/references/generator.md` 作成
  - シーン数に応じた並列数自動決定（max 5）
  - Task tool でシーン生成エージェント並列起動
  - 生成完了後の統合処理
- [x] `agents/video-scene-generator.md` サブエージェント作成
  - 単一シーンの生成に特化
  - Remotionコンポジション出力

**対象ファイル**: `skills/video/references/generator.md`, `agents/video-scene-generator.md`

---

#### 36.5 `/generate-video` 統合コマンド `cc:完了`

- [x] `commands/optional/generate-video.md` 作成
  - 引数なし（インタラクティブフロー）
  - 内部で analyzer → planner → generator を順次呼び出し
- [x] `skills/video/SKILL.md` メインスキル定義作成

**対象ファイル**: `commands/optional/generate-video.md`, `skills/video/SKILL.md`

---

#### 技術参考リンク

- [Remotion公式: Claude Code連携](https://www.remotion.dev/docs/ai/claude-code)
- [Launchpad（テンプレート参考）](https://github.com/trycua/launchpad)
- [FlowGif - Mermaidアニメーション](https://www.flowgif.com/)
- [Playwright MCP](https://dev.to/debs_obrien/automate-your-screenshot-documentation-with-playwright-mcp-3gk4)

---

## 🟠 Phase 38: Remotion スキル デザイン品質強化（NotebookLM ノウハウ適用） `cc:TODO`

### 背景 / 目的

- Remotion スキル（`/generate-video`）は技術フロー（分析→シナリオ→並列生成）が充実しているが、**ビジュアルデザインの仕様指示が弱い**
- NotebookLM スキル（`notebooklm-slides.md`）は目的・読者・トーンに応じた **2案提示**と**具体的なデザイン仕様**（HEX色指定、NG事項、レイアウトカタログ）が充実
- NotebookLM スキルのノウハウを Remotion スキルに適用し、生成動画のデザイン品質を向上させる

### スコープ（やる）

- `skills/video/references/design-spec.md` を新規作成（デザイン仕様の SSOT）
- `skills/video/references/planner.md` にデザインヒアリング（5項目）を追加
- `skills/video/references/generator.md` にデザイン仕様の適用ロジックを追加
- 2案提示（コーポレート vs ストーリー）のテンプレート化

### 非スコープ（やらない）

- Remotion 自体の実装変更（tsx コード変更は対象外）
- `/generate-video` コマンドのフロー変更
- `/remotion-setup` の変更

### 受入条件（必ず測定可能に）

- [ ] `skills/video/references/design-spec.md` が存在し、以下を含む:
  - デザインヒアリング5項目（目的/読者/トーン/ブランド/テンポ）
  - 案A（コーポレート/ミニマル）のYAMLテンプレート
  - 案B（ストーリー/エディトリアル）のYAMLテンプレート
  - シーンタイプ別デザインカタログ（intro/demo/cta/data/architecture）
  - NG事項リスト（動画特有）
- [ ] `skills/video/references/planner.md` の Step 0 にデザインヒアリングが追加されている
- [ ] `skills/video/references/generator.md` にデザイン仕様参照の記載がある
- [ ] `skills/video/SKILL.md` の機能詳細テーブルに design-spec.md が追加されている

### タスク（Claude Code 実装用）

#### Phase 38.1: design-spec.md 新規作成 `cc:TODO`

- [ ] `skills/video/references/design-spec.md` を新規作成
  - デザインヒアリング5項目（NotebookLM の5項目 + 動画固有: 音楽トーン/テンポ）
  - 案A（コーポレート/ミニマル）: 配色パレット、タイポグラフィ、NG事項
  - 案B（ストーリー/エディトリアル）: 配色パレット、タイポグラフィ、NG事項
  - シーンタイプ別デザインカタログ（intro/demo/cta/data/architecture）

#### Phase 38.2: planner.md へのデザインヒアリング統合 `cc:TODO`

- [ ] `skills/video/references/planner.md` の Step 0 にデザインヒアリングを追加
  - AskUserQuestion で5項目確認（デフォルト値付き）
  - ヒアリング結果から案A/案Bを自動選択または両案提示

#### Phase 38.3: generator.md へのデザイン仕様適用 `cc:TODO`

- [ ] `skills/video/references/generator.md` にデザイン仕様参照を追加
  - シーンテンプレートに `design-spec.md` のスタイル変数を適用
  - 生成コード例にスタイル変数（`--primary-color` 等）を追加

#### Phase 38.4: SKILL.md 更新 `cc:TODO`

- [ ] `skills/video/SKILL.md` の機能詳細テーブルに design-spec.md を追加
- [ ] opencode 版（`opencode/skills/video/*`）にも同様の変更を反映

### 評価（Evals）

- **tasks（シナリオ）**:
  - 新規追加ファイル design-spec.md が NotebookLM スキルと同等のデザイン仕様品質を持つことを確認
  - planner.md がデザインヒアリングを実行可能な構造になっていることを確認
- **trials（回数/集計）**:
  - 回数: 1
  - 集計: チェックリストの pass/fail
- **graders（採点）**:
  - outcome:
    - `skills/video/references/design-spec.md` に `配色パレット` `HEX` `案A` `案B` `NG事項` が含まれる
    - `skills/video/references/planner.md` に `デザインヒアリング` または `Design Hearing` が含まれる
    - `skills/video/SKILL.md` に `design-spec.md` が含まれる
  - transcript:
    - 変更対象が `skills/video/*` と `opencode/skills/video/*` に限定されている
- **失敗時の扱い**:
  - 未達項目と該当ファイルを明記して再修正する

### リスク / 未決事項

- NotebookLM と Remotion ではメディア特性が異なる（静止画 vs 動画）。動画固有の要素（モーション、トランジション、音楽）をどこまで仕様化するか
- Decision: Phase 38.1 では静的デザイン要素（配色、タイポ、レイアウト）に集中し、モーション仕様は将来タスクとして分離する

---

## 将来の検討タスク（問題発生時に実行）

### Codex レビュー出力改善 - Phase 2/3

> **トリガー条件**: Phase 1（出力上限緩和 500→1500文字）でコンテキスト溢れが発生した場合

| Phase | 内容 | 実装コスト |
|-------|------|-----------|
| **Phase 2** | 2段階生成（1段目: 指摘リスト、2段目: 重要項目のみ深掘り） | 中 |
| **Phase 3** | サブエージェント方式（Codex 結果を統合するオーケストレーター） | 高 |

**背景**: Codex の能力を最大限活用するためにサブエージェントを挟むアプローチを検討したが、Codex 自身の提案により、まず出力上限緩和（Phase 1）を試行することに決定。問題が起きた場合にのみ Phase 2/3 を検討する。

**Phase 1 実装済み** (2026-01-19):
- `experts/*.md` の出力上限を 500 → 1500 文字に緩和
- `codex-parallel-review.md` の Step 5.1 を更新

---

## アーカイブ

過去フェーズ: [.claude/memory/archive/](.claude/memory/archive/)

| フェーズ | 内容 | ファイル |
|---------|------|---------|
| Phase 35 | opencode-setup フル互換化 | [Plans-2026-01-26-phase35.md](.claude/memory/archive/Plans-2026-01-26-phase35.md) |
| Phase 34 | /work --full 動作確認テスト | [Plans-2026-01-16-phase33-34.md](.claude/memory/archive/Plans-2026-01-16-phase33-34.md) |
| Phase 33 | Claude Code 2.1.x 対応 | [Plans-2026-01-16-phase33-34.md](.claude/memory/archive/Plans-2026-01-16-phase33-34.md) |
| Phase 32 | task-worker 統合 | [Plans-2026-01-16-phase32.md](.claude/memory/archive/Plans-2026-01-16-phase32.md) |
| Phase 31 | harness-ui MVP | [Plans-2026-01-16-phase32.md](.claude/memory/archive/Plans-2026-01-16-phase32.md) |
