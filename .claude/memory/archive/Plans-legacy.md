# Plans.md - 完了済みタスク（レガシー）

このファイルには v2.0.x〜v2.6.x で完了したタスクが記録されています。

---

## v2.6.x で完了したタスク

### フェーズ9: Claude-mem 統合（v2.6.0）

> **目的**: Claude-mem のモードシステムをハーネス仕様にカスタマイズし、セッション跨ぎのガードレール能力、指示追従能力をアップグレード
> **位置づけ**: オプショナルな推奨プラグイン（入れたら能力が大幅に向上）

#### Phase 1: 基本セットアップ

- [x] `/harness-mem` コマンド作成（インストール検出、モードファイル生成）
- [x] `harness.json` モードファイル作成（observation_types, concepts, prompts）
- [x] `harness--ja.json` 作成（日本語版）

#### Phase 2: スキル統合

- [x] `memory-integration.md` ルール作成
- [x] `session-init` への mem-search 統合
- [x] `skills-gate.md` 更新（Memory-Enhanced Skills）

#### Phase 3: SSOT 同期

- [x] `sync-ssot-from-serena` → `sync-ssot-from-memory` リネーム
- [x] SSOT 昇格ロジック実装

#### Phase 4: 高度な統合

- [x] `review`, `verify`, `impl` への mem-search 追加
- [x] ガードレール強化（過去の発動回数表示）

---

## v2.5.x で完了したタスク

### フェーズ6.5: フロントマター統合（v2.5.30）

> **目的**: 生成ファイルに追跡情報を埋め込み、外部JSON依存から脱却

- [x] `scripts/frontmatter-utils.sh` 作成（5関数、MD/JSON/YAML対応）
- [x] 全15テンプレートに `_harness_template`/`_harness_version` 追加
- [x] `template-tracker.sh` をフロントマター優先に更新
- [x] `tests/test-frontmatter-integration.sh` 統合テスト追加
- [x] `docs/PLAN_RULES_IMPROVEMENT.md` 改善計画ドキュメント追加

### フェーズ6: テンプレート追跡機能

> **目的**: プラグイン更新後、生成済みファイル（CLAUDE.md等）を最新テンプレートに同期できるようにする

- [x] `templates/template-registry.json` の作成
- [x] `scripts/template-tracker.sh` の作成
- [x] `session-init.sh` にテンプレートチェックを追加
- [x] `/harness-update` コマンドを拡張
- [x] `scripts/ci/check-template-registry.sh` の作成
- [x] 動作検証（初回導入、更新検出、ローカライズ判定）

### Skill 命名整理: `ccp-*` Skill の廃止（削除）

- [x] `ccp-*` Skill を機械抽出し、移行先の新名称を決める `cc:完了`
- [x] `ccp-*` 子スキルを非 `ccp-*` 名に移行（28ディレクトリリネーム） `cc:完了`
- [x] `ccp-*` カテゴリスキルを非 `ccp-*` 名に移行（7件） `cc:完了`
- [x] CI/検証スクリプトの参照更新と回帰テスト追加 `cc:完了`
- [x] 最終確認: `ccp-` を name として持つ Skill が 0 件 `cc:完了`

### bypassPermissions 前提運用

- [x] `.claude/settings.json` 生成ポリシー見直し `cc:完了`
- [x] 初回 init 時に `bypassPermissions` をデフォルトにできる導線 `cc:完了`
- [x] 危険操作の deny / ask リストを "最小安全" で整備 `cc:完了`
- [x] 回帰防止（check-consistency.sh に追加） `cc:完了`

### SDDアップグレード（request_changes 対応）

- [x] `/plan-with-agent` の成果物統一（`docs/` に統一） `cc:完了`
- [x] config スキーマの整合 `cc:完了`
- [x] 回帰防止: docs 正規化チェック `cc:完了`

---

## v2.4.x で完了したタスク

### サブエージェント活用強化

- [x] CLAUDE.md にサブエージェント連携を追記 `cc:完了`
- [x] review スキルに並列サブエージェント呼び出しロジック追加 `cc:完了`
- [x] ci スキルに ci-cd-fixer 呼び出しロジック追加 `cc:完了`
- [x] harness-review コマンドの Task tool パターン明確化 `cc:完了`

---

## v2.3.x で完了したタスク

### スキル再編成・開発体験改善

- [x] スキルを目的別カテゴリに再編成 `cc:完了`
- [x] 旧カテゴリ（core, optional, worker）を削除 `cc:完了`
- [x] CLAUDE.md にスキルカテゴリ表を追加 `cc:完了`
- [x] pre-commit フックで自動バージョンバンプ `cc:完了`
- [x] Windows 対応ドキュメント追加 `cc:完了`

---

## v2.2.x で完了したタスク

### ライセンス変更（MIT → 独自ライセンス）

- [x] LICENSE ファイルを独自ライセンス文に置き換え `cc:完了`
- [x] README.md のライセンスセクションを更新 `cc:完了`
- [x] plugin.json / marketplace.json を更新 `cc:完了`

---

## v2.0.x で完了したタスク

- [x] `/sync-project-specs` 追加 (v2.0.9)
- [x] PM↔Impl ハンドオフ運用の Plans.md マーカー更新リマインド (v2.0.8)
- [x] ソロ PM↔Impl ハンドオフコマンド追加 (v2.0.7)
- [x] PreToolUse ガードメッセージ日本語化 (v2.0.6)
- [x] `/work` と `/start-task` の使い分け説明改善 (v2.0.5)
