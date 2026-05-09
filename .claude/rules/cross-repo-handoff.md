# Cross-Repo Handoff Workflow (claude-code-harness ↔ harness-mem)

claude-code-harness と sibling repo `harness-mem` の間で発生する責任境界の調整・契約変更・実装移管を、再現可能な形で記録する SSOT。

本文書は decisions.md D42 (`claude-code-harness ↔ harness-mem 責任境界 + Cross-repo Handoff Workflow`) の codifiable な policy 部分を抽出したもの。decisions.md は per-developer の local SSOT (gitignore 対象) であるため、共有が必要な policy は本ファイルに置く。

## なぜこのルールが必要か

claude-code-harness Phase 65 Phase A 完走時のレビューで、ユーザーから「本来 harness-mem 側に実装するべきものを claude-code-harness 側で実装していたら、(i) claude-code-harness から除外し、(ii) harness-mem 側に分かりやすく Issue を上げる」運用期待が示された。

実態は (i) は完了済み (Phase 60 の managed companion 化、Phase 63 の dead default 整理) だが、(ii) は GitHub Issue ではなく harness-mem repo の `Plans.md §NNN` という sibling-repo Plans SSOT 方式で運用されていた。GitHub Issue は #70 (Phase 49.1.2 follow-up) の 1 件のみ。

ユーザー期待 (GitHub Issue) と運用実態 (Plans.md SSOT) の差分は「ポリシー未文書化」が原因。本ルールで正式運用として固定し、再発を防ぐ。

## 3 層 Redaction の責任境界 (Phase 65 cross-project safety)

| Layer | 内容 | 実装層 | 理由 |
|---|---|---|---|
| Layer 1 | privacy filter (`<private>` strip) + project scope (`strict_project: true`) | **harness-mem server 側** | mem の出口で全 client (CC / Codex / opencode) を一律ガード。`include_private=false` default |
| Layer 2a | 辞書ベース固有名詞 redaction (`client-redaction.yaml`) | **claude-code-harness client 側** | project-local config の解釈は presentation layer の責任。server に schema 解釈を持たせると企業ごと redaction policy が server 設定面に漏れる |
| Layer 2b | NER (kuromoji 等の Japanese tokenizer) | **claude-code-harness client 側** | server 依存膨張回避: ONNX embedding (multilingual-e5) が既に重く、JP tokenizer 追加は cold start (~5ms) と memory footprint を毀損 |
| Layer 3 | HTML 生成直前最終 scan | **claude-code-harness client 側** | render-html.sh は client にしかない (rendering pipeline 上にしか置けない) |

将来 server 側 PII redaction フラグを希望する場合は `redact_profile` パラメータの opt-in 設計として harness-mem 側 §111 以降で再検討の余地あり。

### Phase 65.3 実装決定事項 (D43)

Phase 65.3 着手前の mem 側との coordination で確定した実装制約:

| 制約 | 内容 | 根拠 |
|---|---|---|
| MCP cross-project は N-call | `mcp__harness__harness_mem_search` の MCP schema は `project: string` 単一値のみ exposed (`projects: [array]` も `strict_project: boolean` も MCP には無い)。cross-project 検索は client が member ごとに 1 回ずつ MCP call し、結果を client 側でマージ・dedupe する | mem 側 mcp-server schema 確認 (`mcp-server/src/tools/memory.ts:297-341`) |
| client-redaction.yaml は PiiRule 互換 | client 側 dict schema (`client-redaction.v1`) は mem 側既存 `pii-filter.ts` の `PiiRule[]` schema と field 名を互換にする (`rule_id`, `pattern`, `replace_with` 等)。完全共通化 (npm package) は将来 follow-up | 重複実装回避 + Cross-client 一貫性節への upgrade path 確保 |
| `[REDACTED_*]` 二重置換ガード | server 側 `event-recorder.ts:redactContent` が email / API key / hex を `[REDACTED_*]` に置換済み。client Layer 2 redact は既存 mark を**再置換しない** sentinel ガードを必須 | 二重置換による情報破損防止 |
| applied_filters 注記方針 | mem 側 `applied_filters` meta は未実装 (内部 audit のみ)。Phase 65.3.6 audit log は Layer 2/3 (client) のみ記録し、Layer 1 (server) は「server default + 内部 audit に依存」と明示注記 | mem 側未実装を確認、今フェーズ blocking ではない |

将来 cross-project N-call のレイテンシが実運用で問題化したら **XR-005** (MCP schema に `projects: [array]` + `strict_project: boolean` 追加) として harness-mem §111 で起票する。

### Cross-client 一貫性の担保方針

「Codex 等の他 client から呼ばれた時にも redact が効く」要件は **client 側で shared library (npm package or sub-module) を共通化** する方針で対応する。server 側 MCP API 出口で redact しない理由:

- 将来の team sharing (`harness_mem_share_to_team`) で「正しい原文を返す」契約が破れ、可逆性を失う
- server を「presentation policy free」に保つことで、client diversity (CC / Codex / opencode / 将来の third-party client) を阻害しない

代わりに harness-mem は `mcp__harness__harness_mem_search` の response meta に `applied_filters` (例: `privacy_filter` / `project_scope`) を含める拡張を必要に応じて提供する (harness-mem §110 follow-up または §111 で起票)。

## Cross-repo Handoff の 2 経路

claude-code-harness ↔ harness-mem の handoff は以下の 2 経路を使い分ける。

### 経路 A: harness-mem repo の `Plans.md §NNN` (sibling-repo Plans SSOT)

**用途**: Cross-Contract changes (詳細 DoD が必要、複数セッションで参照される handoff)

**例**:
- §106 (companion contract handoff、Phase 60 で起票、cc:完了)
- §107 (checkpoint cold-start handoff、cc:完了)
- §110 (Cross-repo Handoff Workflow Codification、本ルールの相対側、harness-mem 側で codification 完了)

**手順**:
1. claude-code-harness 側で「mem 側に implementation を移すべき」と判断したら、Plans.md に section を追加 (例: §111)
2. section 内に必要な DoD を箇条書き (受け入れ条件、技術制約、参照すべき claude-code-harness 側 commit hash)
3. claude-code-harness 側の関連箇所 (skills/scripts/docs) を **同一 PR で除外** (Phase 60 の `1f4d9133`, `5373d50d` パターン)
4. 必要なら本ルール `.claude/rules/cross-repo-handoff.md` の表に新行を追加

### 経路 B: GitHub Issue

**用途**: Cross-Runtime long-running follow-ups (複数セッション・複数 PR に跨る検討、外部参加者への露出が必要なもの)

**例**: harness-mem #70 (Phase 49.1.2 follow-up)

**手順**:
1. `gh issue create --repo Chachamaru127/harness-mem --title "..." --body "..."` で起票
2. claude-code-harness 側からは関連箇所に `# See harness-mem#NN` のコメントだけ残す (実装はしない)
3. harness-mem 側で issue が close されたら、claude-code-harness 側で本ルールの参照を更新

## 判断軸 (どちらを使うか)

| 観点 | A: Plans.md §NNN | B: GitHub Issue |
|---|---|---|
| 詳細 DoD が必要か | ✓ 詳細 DoD を書ける | △ Issue body は流動的 |
| 複数セッションで参照されるか | ✓ Plans.md は永続 SSOT | △ Issue は時間経過で読みにくい |
| 外部参加者への露出が必要か | △ repo collaborator のみ | ✓ public repo なら外部から見える |
| 実害がない closeout-only か | ✓ 軽量 | △ Issue を立てると closeout 工数が発生 |
| long-running cross-runtime か | △ Plans.md は cross-runtime 向き弱い | ✓ Issue が適切 |

迷ったら **経路 A (Plans.md §NNN)** を default とする。理由: 過去 4 件の handoff のうち 3 件 (Phase 60, 63, 65) が Plans.md SSOT で完了しており、運用実績がある。GitHub Issue は #70 1 件のみ。

## 過去の境界調整実績 (retroactive 起票しない)

以下の過去 handoff は **本ルールで「Plans.md §NNN は GitHub Issue と等価」と確定した**ため、retroactive な GitHub Issue 起票はしない:

- Phase 60 (managed companion 化) — harness-mem Plans.md §106
- Phase 63 (dead default 整理) — harness-mem Plans.md §107
- Phase 65.3 (3 層 redaction の owner 確認) — 本ルール表 + harness-mem Plans.md §110

将来の境界変更時は本ルールの 2 経路から選択する。

## 関連

- claude-code-harness `.claude/memory/decisions.md` D42 (本ルールの local SSOT 元、gitignore 対象)
- claude-code-harness `.claude/rules/migration-policy.md` (Phase 60 削除済み概念の handoff 記録手順)
- harness-mem `docs/claude-harness-companion-contract.md:84-96` (Cross-repo Handoff Workflow セクション、harness-mem 側相対)
- harness-mem `.claude/memory/patterns.md:230` (P7 Non-Application Conditions に Plans.md SSOT 例外追記)
- harness-mem Plans.md §110 (Cross-repo Handoff Workflow Codification、本ルールの相対側)

## 見直し条件

- **Trigger A**: server 側で PII redaction を opt-in 提供する API (例: `redact_profile` parameter) が harness-mem §111+ で実装された時 — Layer 2 の owner を再検討
- **Trigger B**: cross-client 一貫性のための shared library が npm 化された時 — Cross-client 一貫性節を更新
- **Trigger C**: harness-mem `mcp__harness__harness_mem_search` の response meta に `applied_filters` が追加された時 — Layer 1 検証経路を更新
