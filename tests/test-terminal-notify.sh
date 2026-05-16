#!/bin/bash
# test-terminal-notify.sh
# CC 2.1.141+ hook `terminalSequence` 出力契約のテスト (Phase 69.1.5)
#
# 検証項目:
#   1. HARNESS_TERMINAL_NOTIFY 未設定 → terminalSequence を出力しない
#   2. bell mode → BEL (\x07) のみ
#   3. osc9 mode → ESC ]9; <text> BEL
#   4. title mode → ESC ]0; <text> BEL
#   5. notify mode → ESC ]777;notify; <title>; <body> BEL
#   6. 不明な mode → silent (空文字列)
#   7. title が空 → 空文字列
#   8. 制御文字を含む title → サニタイズされる
#   9. JSON encoding が妥当
#   10. webhook-notify.sh が terminalSequence を含む JSON を返す
#   11. notification-handler.sh が permission_prompt で terminalSequence を返す
#   12. notification-handler.sh が unknown type では terminalSequence を返さない

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1" >&2
  FAIL=$((FAIL + 1))
}

# ============================================================
# Direct helper tests
# ============================================================
echo "1. terminal-notify.sh helper の直接テスト"

# 関数を呼べるよう source
unset HARNESS_TERMINAL_NOTIFY
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/terminal-notify.sh"

# Test 1: unset → empty
unset HARNESS_TERMINAL_NOTIFY
out="$(build_terminal_sequence "title" "body")"
if [ -z "${out}" ]; then
  pass "1.1 HARNESS_TERMINAL_NOTIFY unset → 空文字列"
else
  fail "1.1 HARNESS_TERMINAL_NOTIFY unset で出力が出た: [${out}]"
fi

# Test 2: "0" → empty
export HARNESS_TERMINAL_NOTIFY=0
out="$(build_terminal_sequence "title")"
if [ -z "${out}" ]; then
  pass "1.2 HARNESS_TERMINAL_NOTIFY=0 → 空文字列"
else
  fail "1.2 HARNESS_TERMINAL_NOTIFY=0 で出力が出た"
fi

# Test 3: bell → BEL のみ
export HARNESS_TERMINAL_NOTIFY=bell
out="$(build_terminal_sequence "title")"
expected="$(printf '\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.3 bell mode → BEL のみ (1 byte)"
else
  fail "1.3 bell mode が想定と違う: byte 数=${#out}"
fi

# Test 4: osc9 → ESC ]9; ... BEL
export HARNESS_TERMINAL_NOTIFY=osc9
out="$(build_terminal_sequence "Build complete")"
expected="$(printf '\x1b]9;Build complete\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.4 osc9 mode → ESC ]9; ... BEL"
else
  fail "1.4 osc9 mode が想定と違う"
fi

# Test 5: title → ESC ]0; ... BEL
export HARNESS_TERMINAL_NOTIFY=title
out="$(build_terminal_sequence "My Session")"
expected="$(printf '\x1b]0;My Session\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.5 title mode → ESC ]0; ... BEL"
else
  fail "1.5 title mode が想定と違う"
fi

# Test 6: notify with body → OSC 777;notify; ... ; ... BEL
export HARNESS_TERMINAL_NOTIFY=notify
out="$(build_terminal_sequence "Build complete" "all tests pass")"
expected="$(printf '\x1b]777;notify;Build complete;all tests pass\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.6 notify mode (with body) → OSC 777;notify;title;body;BEL"
else
  fail "1.6 notify mode が想定と違う"
fi

# Test 7: notify without body → OSC 777;notify;title;BEL
export HARNESS_TERMINAL_NOTIFY=notify
out="$(build_terminal_sequence "Build complete")"
expected="$(printf '\x1b]777;notify;Build complete\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.7 notify mode (no body) → OSC 777;notify;title;BEL"
else
  fail "1.7 notify mode (no body) が想定と違う"
fi

# Test 8: unknown mode → silent
export HARNESS_TERMINAL_NOTIFY=unknown
out="$(build_terminal_sequence "title")"
if [ -z "${out}" ]; then
  pass "1.8 unknown mode → 空文字列 (silent ignore)"
else
  fail "1.8 unknown mode で出力が出た"
fi

# Test 9: empty title (osc9) → empty
export HARNESS_TERMINAL_NOTIFY=osc9
out="$(build_terminal_sequence "" "body only")"
if [ -z "${out}" ]; then
  pass "1.9 title 空 (osc9) → 空文字列"
else
  fail "1.9 title 空 (osc9) でも出力が出た"
fi

# Test 9.5: empty title (bell) → BEL (bell は title 不要)
export HARNESS_TERMINAL_NOTIFY=bell
out="$(build_terminal_sequence "")"
expected="$(printf '\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.9.5 title 空でも bell mode は BEL を発火"
else
  fail "1.9.5 bell mode が title 空のときに発火しなかった (空タイトル ガード過剰)"
fi

# Test 9.6: empty title (mode=1, alias for bell) → BEL
export HARNESS_TERMINAL_NOTIFY=1
out="$(build_terminal_sequence "")"
if [ "${out}" = "${expected}" ]; then
  pass "1.9.6 title 空でも mode=1 alias は BEL を発火"
else
  fail "1.9.6 mode=1 alias が title 空のときに発火しなかった"
fi

# Test 10: control chars stripped
export HARNESS_TERMINAL_NOTIFY=osc9
# input contains \n, \x1b, \x07 — all should be stripped
raw_input="$(printf 'bad\ntitle\x1b\x07evil')"
out="$(build_terminal_sequence "${raw_input}")"
# expected: 制御文字除去後 "badtitleevil" + ESC ]9; ... BEL
expected="$(printf '\x1b]9;badtitleevil\x07')"
if [ "${out}" = "${expected}" ]; then
  pass "1.10 制御文字 (\\n, ESC, BEL) が title から除去される"
else
  fail "1.10 制御文字除去が想定と違う"
fi

# ============================================================
# JSON encoding tests
# ============================================================
echo ""
echo "2. JSON encoding テスト"

export HARNESS_TERMINAL_NOTIFY=osc9
seq="$(build_terminal_sequence "Build")"
encoded="$(encode_terminal_sequence_json "${seq}")"
# jq があれば妥当な JSON 文字列リテラルか確認
if command -v jq >/dev/null 2>&1; then
  decoded="$(printf '%s' "${encoded}" | jq -r . 2>/dev/null)" || decoded=""
  if [ "${decoded}" = "${seq}" ]; then
    pass "2.1 encode_terminal_sequence_json: jq でラウンドトリップ可能"
  else
    fail "2.1 jq ラウンドトリップ失敗: encoded=${encoded}, decoded=[${decoded}]"
  fi
else
  echo "  (skip 2.1: jq 不在)"
fi

# Empty input
out="$(encode_terminal_sequence_json "")"
if [ -z "${out}" ]; then
  pass "2.2 encode_terminal_sequence_json('') → 空"
else
  fail "2.2 empty input で出力が出た"
fi

# ============================================================
# webhook-notify.sh integration
# ============================================================
echo ""
echo "3. webhook-notify.sh integration テスト"

# Test: HARNESS_TERMINAL_NOTIFY set, HARNESS_WEBHOOK_URL unset → local notify only
unset HARNESS_WEBHOOK_URL
export HARNESS_TERMINAL_NOTIFY=osc9
out="$(echo '{}' | bash "${REPO_ROOT}/scripts/hook-handlers/webhook-notify.sh" build-complete 2>/dev/null)"
if command -v python3 >/dev/null 2>&1; then
  has_ts="$(printf '%s' "${out}" | python3 -c "import sys, json
try:
    d = json.loads(sys.stdin.read())
    print('yes' if 'terminalSequence' in d else 'no')
except Exception:
    print('parse-fail')" 2>/dev/null)"
  if [ "${has_ts}" = "yes" ]; then
    pass "3.1 HARNESS_TERMINAL_NOTIFY=osc9 + URL 未設定 → terminalSequence 含む JSON"
  else
    fail "3.1 terminalSequence が JSON に含まれない: ${out}"
  fi
fi

# Test: 未設定 → terminalSequence 含まない (既存挙動維持)
unset HARNESS_TERMINAL_NOTIFY
unset HARNESS_WEBHOOK_URL
out="$(echo '{}' | bash "${REPO_ROOT}/scripts/hook-handlers/webhook-notify.sh" some-event 2>/dev/null)"
if command -v python3 >/dev/null 2>&1; then
  has_ts="$(printf '%s' "${out}" | python3 -c "import sys, json
try:
    d = json.loads(sys.stdin.read())
    print('yes' if 'terminalSequence' in d else 'no')
except Exception:
    print('parse-fail')" 2>/dev/null)"
  if [ "${has_ts}" = "no" ]; then
    pass "3.2 HARNESS_TERMINAL_NOTIFY 未設定 → 既存挙動維持 (terminalSequence なし)"
  else
    fail "3.2 既存挙動が壊れた (terminalSequence が漏れた): ${out}"
  fi
fi

# ============================================================
# notification-handler.sh integration
# ============================================================
echo ""
echo "4. notification-handler.sh integration テスト"

export HARNESS_TERMINAL_NOTIFY=osc9
out="$(echo '{"notification_type":"permission_prompt","agent_type":"worker","session_id":"t1"}' \
  | bash "${REPO_ROOT}/scripts/hook-handlers/notification-handler.sh" 2>/dev/null)"
if command -v python3 >/dev/null 2>&1; then
  has_ts="$(printf '%s' "${out}" | python3 -c "import sys, json
try:
    d = json.loads(sys.stdin.read())
    print('yes' if 'terminalSequence' in d else 'no')
except Exception:
    print('parse-fail')" 2>/dev/null)"
  if [ "${has_ts}" = "yes" ]; then
    pass "4.1 permission_prompt + HARNESS_TERMINAL_NOTIFY=osc9 → terminalSequence 含む"
  else
    fail "4.1 permission_prompt で terminalSequence が含まれない: ${out}"
  fi
fi

# 未知の notification_type → terminalSequence なし (silent)
export HARNESS_TERMINAL_NOTIFY=osc9
out="$(echo '{"notification_type":"unknown_xyz"}' \
  | bash "${REPO_ROOT}/scripts/hook-handlers/notification-handler.sh" 2>/dev/null)"
if [ -z "${out}" ]; then
  pass "4.2 unknown notification_type → 出力なし (silent)"
else
  fail "4.2 unknown notification_type で出力が出た: ${out}"
fi

# 未設定 → 既存挙動 (silent)
unset HARNESS_TERMINAL_NOTIFY
out="$(echo '{"notification_type":"permission_prompt"}' \
  | bash "${REPO_ROOT}/scripts/hook-handlers/notification-handler.sh" 2>/dev/null)"
if [ -z "${out}" ]; then
  pass "4.3 HARNESS_TERMINAL_NOTIFY 未設定 → 既存挙動維持 (silent)"
else
  fail "4.3 既存挙動が壊れた: ${out}"
fi

# ============================================================
# Rule presence checks
# ============================================================
echo ""
echo "5. Rule / docs presence チェック"

rule_file="${REPO_ROOT}/.claude/rules/hooks-2.1.139-plus.md"
if [ -f "${rule_file}" ]; then
  required_anchors=(
    'HARNESS_TERMINAL_NOTIFY'
    'CLAUDE_EFFORT'
    'continueOnBlock'
    'args: string'
    'SessionStart'
    'terminalSequence'
  )
  missing=0
  for anchor in "${required_anchors[@]}"; do
    if ! grep -qF -- "${anchor}" "${rule_file}"; then
      fail "5.x ${rule_file} に '${anchor}' が無い"
      missing=$((missing + 1))
    fi
  done
  if [ "${missing}" -eq 0 ]; then
    pass "5.1 hooks-2.1.139-plus.md に必須 6 anchor が全て存在"
  fi
else
  fail "5.1 ${rule_file} が存在しない"
fi

policy_file="${REPO_ROOT}/docs/agent-view-policy.md"
if [ -f "${policy_file}" ]; then
  required_anchors=(
    'claude agents'
    '--dangerously-skip-permissions'
    'permission mode'
    'breezing'
  )
  missing=0
  for anchor in "${required_anchors[@]}"; do
    if ! grep -qF -- "${anchor}" "${policy_file}"; then
      fail "5.x ${policy_file} に '${anchor}' が無い"
      missing=$((missing + 1))
    fi
  done
  if [ "${missing}" -eq 0 ]; then
    pass "5.2 agent-view-policy.md に必須 4 anchor が全て存在"
  fi
else
  fail "5.2 ${policy_file} が存在しない"
fi

# Phase 69 snapshot doc
snapshot_file="${REPO_ROOT}/docs/upstream-update-snapshot-2026-05-15.md"
if [ -f "${snapshot_file}" ]; then
  required_anchors=(
    '2.1.133'
    '2.1.142'
    'worktree.baseRef'
    'autoMode.hard_deny'
    'terminalSequence'
    'claude agents'
    'Phase 69'
  )
  missing=0
  for anchor in "${required_anchors[@]}"; do
    if ! grep -qF -- "${anchor}" "${snapshot_file}"; then
      fail "5.x ${snapshot_file} に '${anchor}' が無い"
      missing=$((missing + 1))
    fi
  done
  if [ "${missing}" -eq 0 ]; then
    pass "5.3 Phase 69 snapshot doc に必須 7 anchor が全て存在"
  fi
else
  fail "5.3 ${snapshot_file} が存在しない"
fi

# ============================================================
# Template baseline checks
# ============================================================
echo ""
echo "6. Template baseline チェック"

template_file="${REPO_ROOT}/templates/claude/settings.security.json.template"
if [ -f "${template_file}" ]; then
  # JSON parse して値を厳密に検証 (key 存在だけではなく中身まで)
  if python3 - "${template_file}" >/dev/null 2>&1 <<'PY'
import json, sys
expected_hard_deny = {
    "Bash(sudo:*)",
    "Bash(rm -rf:*)",
    "Bash(rm -fr:*)",
    "Bash(git push -f:*)",
    "Bash(git push --force:*)",
    "Bash(git reset --hard:*)",
    "mcp__codex__*",
}
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
assert data.get('worktree', {}).get('baseRef') == 'fresh', \
    f"worktree.baseRef expected 'fresh', got {data.get('worktree', {}).get('baseRef')!r}"
actual = set(data.get('autoMode', {}).get('hard_deny', []))
assert actual == expected_hard_deny, \
    f"autoMode.hard_deny mismatch: missing={expected_hard_deny - actual}, extra={actual - expected_hard_deny}"
PY
  then
    pass "6.1 template の worktree.baseRef='fresh' + autoMode.hard_deny baseline 7 件が期待値どおり"
  else
    fail "6.1 template の worktree.baseRef または autoMode.hard_deny baseline が期待値と一致しない"
  fi

  # JSON validity (redundant with above but keeps a discrete check)
  if python3 -m json.tool "${template_file}" >/dev/null 2>&1; then
    pass "6.2 template が valid JSON"
  else
    fail "6.2 template が valid JSON ではない"
  fi
else
  fail "6.1 ${template_file} が存在しない"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=========================================="
echo "テスト結果"
echo "=========================================="
echo "  合格: ${PASS}"
echo "  失敗: ${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
exit 0
