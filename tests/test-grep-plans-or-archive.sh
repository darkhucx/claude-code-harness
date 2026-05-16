#!/usr/bin/env bash
# Phase 64.1.3: grep_plans_or_archive helper の 4 状態 unit test
#
# Phase 64.1.1 で導入した archive-aware Plans.md grep helper の振る舞いを
# 4 状態 (Plans only / archive only / both / miss) で固定する。
# helper の divergence を防ぐため、tests/lib/grep_plans_or_archive.sh を
# 直接 source して動作を検証する。
#
# テスト戦略:
# - mktemp で tmp dir を作り、Plans.md と archive/Plans-XXX.md を fixture として配置
# - GPOA_PLANS_FILE / GPOA_ARCHIVE_DIR を override し、helper を呼ぶ
# - 各ケースで return code を assert
#
# 使い方: bash tests/test-grep-plans-or-archive.sh
# 期待: PASS=4 FAIL=0 で exit 0

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/grep_plans_or_archive.sh
. "${ROOT_DIR}/tests/lib/grep_plans_or_archive.sh"

PASS=0
FAIL=0

assert_returns() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "${expected}" = "${actual}" ]; then
        echo "  ✓ ${label} (returned ${actual})"
        PASS=$((PASS + 1))
    else
        echo "  ✗ ${label} (expected ${expected}, got ${actual})"
        FAIL=$((FAIL + 1))
    fi
}

# Setup: tmp fixture
TMPDIR_FIX="$(mktemp -d /tmp/test-gpoa.XXXXXX)"
trap 'rm -rf "${TMPDIR_FIX}"' EXIT

PLANS_FIX="${TMPDIR_FIX}/Plans.md"
ARCHIVE_FIX="${TMPDIR_FIX}/archive"
mkdir -p "${ARCHIVE_FIX}"

export GPOA_PLANS_FILE="${PLANS_FIX}"
export GPOA_ARCHIVE_DIR="${ARCHIVE_FIX}"

echo "=== Test 1: PlansHit (Plans.md だけに pattern) ==="
echo "Phase 99.1.1 | unique-pattern-plans-only" > "${PLANS_FIX}"
rm -f "${ARCHIVE_FIX}"/Plans-*.md
set +e
grep_plans_or_archive 'unique-pattern-plans-only'
RC=$?
set -e
assert_returns "PlansHit returns 0" 0 "${RC}"

echo ""
echo "=== Test 2: ArchiveHit (archive だけに pattern) ==="
echo "Phase 47.1.1 | something-else" > "${PLANS_FIX}"
echo "Phase 51.1.1 | unique-pattern-archive-only" > "${ARCHIVE_FIX}/Plans-2026-05-08-phase47-61.md"
set +e
grep_plans_or_archive 'unique-pattern-archive-only'
RC=$?
set -e
assert_returns "ArchiveHit returns 0" 0 "${RC}"

echo ""
echo "=== Test 3: BothHit (両方に pattern) ==="
echo "shared-pattern-both" > "${PLANS_FIX}"
echo "shared-pattern-both" > "${ARCHIVE_FIX}/Plans-2026-05-08-phase47-61.md"
set +e
grep_plans_or_archive 'shared-pattern-both'
RC=$?
set -e
assert_returns "BothHit returns 0" 0 "${RC}"

echo ""
echo "=== Test 4: Miss (どちらにもない) ==="
echo "Phase X | irrelevant content" > "${PLANS_FIX}"
echo "Phase Y | another irrelevant" > "${ARCHIVE_FIX}/Plans-2026-05-08-phase47-61.md"
set +e
grep_plans_or_archive 'pattern-that-does-not-exist'
RC=$?
set -e
assert_returns "Miss returns 1" 1 "${RC}"

echo ""
echo "=== Summary ==="
echo "PASS=${PASS} FAIL=${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

echo "OK"
exit 0
