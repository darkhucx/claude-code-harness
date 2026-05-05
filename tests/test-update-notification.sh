#!/bin/bash
# test-update-notification.sh
# 既存ユーザー向けアップデート通知機能の検証テスト
#
# テスト対象:
# - session-init.sh の新規ルール検出
# - session-init.sh の古いフック設定検出
# - template-tracker.sh の needsInstall 報告
# - harness-setup の update 統合後ガイダンス

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

assert_script_runs() {
  local script="$1"
  local description="$2"
  TOTAL=$((TOTAL + 1))

  if [ ! -f "$PLUGIN_ROOT/$script" ]; then
    echo -e "${RED}✗${NC} $description (script not found)"
    FAILED=$((FAILED + 1))
    return 1
  fi

  if bash -n "$PLUGIN_ROOT/$script" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} $description"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo -e "${RED}✗${NC} $description (syntax error)"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

echo "=================================================="
echo "既存ユーザー向けアップデート通知機能の検証"
echo "=================================================="
echo ""

# ============================================
# session-init.sh の検証
# ============================================
echo "## session-init.sh"
echo ""

assert_script_runs \
  "scripts/session-init.sh" \
  "session-init.sh の構文が正しい"

assert_file_contains \
  "scripts/session-init.sh" \
  "QUALITY_RULES.*test-quality.md.*implementation-quality.md" \
  "品質保護ルールのチェックロジックがある"

assert_file_contains \
  "scripts/session-init.sh" \
  "MISSING_RULES_INFO" \
  "未導入ルールの通知変数がある"

assert_file_contains \
  "scripts/session-init.sh" \
  "OLD_HOOKS_INFO" \
  "古いフック設定の検出変数がある"

assert_file_contains \
  "scripts/session-init.sh" \
  "jq.*\.hooks" \
  "hooks セクションの検出ロジックがある"

assert_file_contains \
  "scripts/session-init.sh" \
  "INSTALLS_COUNT" \
  "新規インストール件数の処理がある"

echo ""

# ============================================
# template-tracker.sh の検証
# ============================================
echo "## template-tracker.sh"
echo ""

assert_script_runs \
  "scripts/template-tracker.sh" \
  "template-tracker.sh の構文が正しい"

assert_file_contains \
  "scripts/template-tracker.sh" \
  "installs_details" \
  "インストール詳細の追跡変数がある"

assert_file_contains \
  "scripts/template-tracker.sh" \
  "installsCount" \
  "installsCount の出力がある"

assert_file_contains \
  "scripts/template-tracker.sh" \
  "installs_count" \
  "インストール件数のカウントがある"

echo ""

# ============================================
# harness-setup / update guidance の検証
# ============================================
echo "## harness-setup update guidance"
echo ""

# harness-update は現在 harness-setup に統合されている。
assert_file_contains \
  "skills/harness-setup/SKILL.md" \
  "harness-update.*Harness アップデート|Harness アップデート.*harness-update" \
  "harness-update の役割が harness-setup に統合されている"

assert_file_contains \
  "skills/harness-setup/SKILL.md" \
  "harness sync|harness doctor|sync.*doctor" \
  "harness-setup に同期と検証の手順がある"

assert_file_contains \
  "docs/update-summary-2025-12-23-24.md" \
  "古いフック設定.*hooks|カスタムフック保護" \
  "アップデート履歴にフック検出と保護の説明がある"

assert_file_contains \
  "docs/update-summary-2025-12-23-24.md" \
  "新しいスキルを自動検出|削除されたスキルも検出" \
  "アップデート履歴にスキル差分検出の説明がある"

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
