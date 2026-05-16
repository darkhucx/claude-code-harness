#!/bin/bash
# test-quality-guardrails.sh
# テスト改ざん防止機能（3層防御戦略）の検証テスト
#
# テスト対象:
# - 第1層: Rules テンプレートの存在と構造
# - 第2層: Skills の品質ガードレール統合
# - harness-init での展開設定

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# カウンター
PASSED=0
FAILED=0
TOTAL=0

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# テスト関数
assert_file_exists() {
  local file="$1"
  local description="$2"
  TOTAL=$((TOTAL + 1))

  if [ -f "$PLUGIN_ROOT/$file" ]; then
    echo -e "${GREEN}✓${NC} $description"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $description"
    echo "  Expected file: $file"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  TOTAL=$((TOTAL + 1))

  if [ ! -f "$PLUGIN_ROOT/$file" ]; then
    echo -e "${RED}✗${NC} $description (file not found)"
    FAILED=$((FAILED + 1))
    return 1
  fi

  if grep -qE "$pattern" "$PLUGIN_ROOT/$file"; then
    echo -e "${GREEN}✓${NC} $description"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $description"
    echo "  Expected pattern: $pattern"
    echo "  File: $file"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

assert_json_key_exists() {
  local file="$1"
  local key="$2"
  local description="$3"
  TOTAL=$((TOTAL + 1))

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠${NC} $description (jq not available, skipped)"
    return 0
  fi

  if [ ! -f "$PLUGIN_ROOT/$file" ]; then
    echo -e "${RED}✗${NC} $description (file not found)"
    FAILED=$((FAILED + 1))
    return 1
  fi

  if jq -e "$key" "$PLUGIN_ROOT/$file" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} $description"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $description"
    echo "  Expected key: $key"
    echo "  File: $file"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

echo "=================================================="
echo "テスト改ざん防止機能（3層防御戦略）検証"
echo "=================================================="
echo ""

# ============================================
# 第1層: Rules テンプレートの検証
# ============================================
echo "## 第1層: Rules テンプレート"
echo ""

# テスト品質ルールテンプレートの存在
assert_file_exists \
  "templates/rules/test-quality.md.template" \
  "test-quality.md.template が存在する"

# 実装品質ルールテンプレートの存在
assert_file_exists \
  "templates/rules/implementation-quality.md.template" \
  "implementation-quality.md.template が存在する"

# test-quality.md の必須コンテンツ
assert_file_contains \
  "templates/rules/test-quality.md.template" \
  "it.skip|test.skip" \
  "test-quality.md に skip 禁止パターンが含まれる"

assert_file_contains \
  "templates/rules/test-quality.md.template" \
  "eslint|lint|disable" \
  "test-quality.md に lint 設定改ざん禁止が含まれる"

assert_file_contains \
  "templates/rules/test-quality.md.template" \
  "_harness_template" \
  "test-quality.md にフロントマターメタデータが含まれる"

# implementation-quality.md の必須コンテンツ
assert_file_contains \
  "templates/rules/implementation-quality.md.template" \
  "ハードコード|hardcode" \
  "implementation-quality.md にハードコード禁止が含まれる"

assert_file_contains \
  "templates/rules/implementation-quality.md.template" \
  "スタブ|stub" \
  "implementation-quality.md にスタブ禁止が含まれる"

assert_file_contains \
  "templates/rules/implementation-quality.md.template" \
  "_harness_template" \
  "implementation-quality.md にフロントマターメタデータが含まれる"

# template-registry.json への登録
assert_json_key_exists \
  "templates/template-registry.json" \
  '.templates["rules/test-quality.md.template"]' \
  "template-registry.json に test-quality.md が登録されている"

assert_json_key_exists \
  "templates/template-registry.json" \
  '.templates["rules/implementation-quality.md.template"]' \
  "template-registry.json に implementation-quality.md が登録されている"

echo ""

# ============================================
# 第2層: Skills の品質ガードレール検証
# ============================================
echo "## 第2層: Skills 品質ガードレール"
echo ""

# harness-work スキルの品質ガードレール
assert_file_contains \
  "skills/harness-work/SKILL.md" \
  "重要停止条件|critical / major review finding" \
  "harness-work/SKILL.md に品質停止条件がある"

assert_file_contains \
  "skills/harness-work/SKILL.md" \
  "テストを弱める|skip|期待値.*緩める" \
  "harness-work/SKILL.md にテスト改ざん禁止が定義されている"

assert_file_contains \
  "skills/harness-work/SKILL.md" \
  "DoD|Plans\\.md|sprint-contract" \
  "harness-work/SKILL.md に DoD / Plans ベースの実装原則がある"

# harness-review / ci スキルの品質ガードレール
assert_file_contains \
  "skills/harness-review/SKILL.md" \
  "Security, Performance, Quality|AI Residuals" \
  "harness-review/SKILL.md に品質レビュー観点がある"

assert_file_contains \
  "skills/harness-review/SKILL.md" \
  "it\\.skip|describe\\.skip|test\\.skip" \
  "harness-review/SKILL.md にテスト skip 検出が定義されている"

assert_file_contains \
  "skills/ci/SKILL.md" \
  "承認リクエスト|Approval Request" \
  "ci/SKILL.md に承認リクエスト形式がある"

echo ""

# ============================================
# harness-init 統合検証
# ============================================
echo "## harness-init 統合"
echo ""

# harness-init での品質ルール展開設定（スキル移行後）
assert_file_contains \
  "skills/harness-setup/SKILL.md" \
  "harness-init|プロジェクト初期化|setup" \
  "harness-setup に旧 harness-init 相当のセットアップ機能が含まれる"

# 品質ルールファイルの存在確認
assert_file_contains \
  ".claude/rules/test-quality.md" \
  "テスト改ざん|Test Tampering|禁止" \
  "test-quality.md にテスト改ざん防止ルールがある"

assert_file_contains \
  ".claude/rules/implementation-quality.md" \
  "形骸化|stub|placeholder" \
  "implementation-quality.md に形骸化実装禁止ルールがある"

echo ""

# ============================================
# ドキュメント検証
# ============================================
echo "## ドキュメント"
echo ""

# CLAUDE.md / AGENTS.md のテスト改ざん防止セクション
assert_file_contains \
  "CLAUDE.md" \
  "テスト改ざん防止|Test Tampering Prevention" \
  "CLAUDE.md にテスト改ざん防止セクションがある"

# AGENTS.md は Codex CLI の project-local config で、clean public checkout には
# 含まれない (codex-cli-only.md 参照)。存在する場合のみ assert する。
if [ -f "AGENTS.md" ]; then
  assert_file_contains \
    "AGENTS.md" \
    "3層防御|3-layer|第1層|第2層|第3層" \
    "AGENTS.md に3層防御戦略の説明がある"
else
  echo "[skip] AGENTS.md not found (Codex CLI local config; not in public checkout)"
fi

# README.md の品質保証関連の言及
assert_file_contains \
  "README.md" \
  "Test tampering|Quality|品質" \
  "README.md に品質保証関連の言及がある"

# 設計ドキュメント (历史的な品質ガード導入記録)
# docs/update-summary-2025-12-23-24.md は導入時の一時的なサマリー doc。
# 現在は CLAUDE.md / .claude/rules/test-quality.md / implementation-quality.md に
# 統合されたため、ファイル自体が存在する場合のみ assert する。
if [ -f "docs/update-summary-2025-12-23-24.md" ]; then
  assert_file_exists \
    "docs/update-summary-2025-12-23-24.md" \
    "品質ガード導入ドキュメントが存在する"
else
  echo "[skip] docs/update-summary-2025-12-23-24.md not found (statement consolidated into CLAUDE.md and .claude/rules/)"
fi

echo ""

# ============================================
# 結果サマリー
# ============================================
echo "=================================================="
echo "テスト結果"
echo "=================================================="
echo ""
echo "合計: $TOTAL"
echo -e "成功: ${GREEN}$PASSED${NC}"
echo -e "失敗: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ すべてのテストが成功しました${NC}"
  exit 0
else
  echo -e "${RED}✗ $FAILED 件のテストが失敗しました${NC}"
  exit 1
fi
