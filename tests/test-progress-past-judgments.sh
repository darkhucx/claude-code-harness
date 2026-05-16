#!/bin/bash
# tests/test-progress-past-judgments.sh
# Phase 65.4.4 - Progress Tracker 過去判断 lookup の機械検証
#
# 検証ケース (Plans.md §65.4.4 DoD d):
#   1. judgment 0 件  - records 該当なし → total_count=0, rate=0
#   2. judgment 3 件  - mixed (2 reject + 1 accept) → total=3, rate=66
#   3. 全 reject     - 5 件全て reject_suggestion → rate=100
#   4. 全 accept     - 5 件全て follow_suggestion → rate=0
# 加えて (c) cross-project default OFF 確認
#   + alert kind enum 検証 + records-file not found エラー

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCRIPT="$ROOT_DIR/scripts/progress-past-judgments.sh"

PASS=0
FAIL=0
FAIL_MESSAGES=()

pass() { PASS=$((PASS + 1)); echo "✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAIL_MESSAGES+=("$1"); echo "✗ $1" >&2; }

if [[ ! -x "$SCRIPT" ]]; then
  fail "script not executable"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
pass "progress-past-judgments.sh exists and executable"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-past-judgments.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================
# Case 1: judgment 0 件 - records に該当なし
# ============================================================

REC1="$TMP_DIR/rec1-empty.jsonl"
cat > "$REC1" <<'JSONL'
{"data":{"alert_kind":"time-overrun","decision":"follow_suggestion","reasoning":"x","timestamp":"2026-05-01T00:00:00Z","project":"otherproj"}}
JSONL

OUT="$(bash "$SCRIPT" --alert-kind scope-creep --project myproj --records-file "$REC1")"

if echo "$OUT" | jq -e '
  .alert_kind == "scope-creep" and
  .project == "myproj" and
  .total_count == 0 and
  .rejected_count == 0 and
  .rejection_rate_pct == 0 and
  (.top_3_judgments | length == 0)
' >/dev/null 2>&1; then
  pass "Case 1 (0 件): total=0, rate=0, top_3=[]"
else
  fail "Case 1: bad output. got: $OUT"
fi

# ============================================================
# Case 2: judgment 3 件 (2 reject + 1 follow) → rate=66
# ============================================================

REC2="$TMP_DIR/rec2-mixed.jsonl"
cat > "$REC2" <<'JSONL'
{"data":{"alert_kind":"scope-creep","decision":"reject_suggestion","reasoning":"r1","timestamp":"2026-05-01T10:00:00Z","project":"myproj"}}
{"data":{"alert_kind":"scope-creep","decision":"reject_suggestion","reasoning":"r2","timestamp":"2026-05-02T10:00:00Z","project":"myproj"}}
{"data":{"alert_kind":"scope-creep","decision":"follow_suggestion","reasoning":"f1","timestamp":"2026-05-03T10:00:00Z","project":"myproj"}}
JSONL

OUT="$(bash "$SCRIPT" --alert-kind scope-creep --project myproj --records-file "$REC2")"

if echo "$OUT" | jq -e '
  .total_count == 3 and
  .rejected_count == 2 and
  .rejection_rate_pct == 66 and
  (.top_3_judgments | length == 3)
' >/dev/null 2>&1; then
  pass "Case 2 (3 件 mixed): total=3, rejected=2, rate=66"
else
  fail "Case 2: bad output. got: $OUT"
fi

# top_3 は timestamp 降順
FIRST_TIMESTAMP="$(echo "$OUT" | jq -r '.top_3_judgments[0].timestamp')"
if [[ "$FIRST_TIMESTAMP" == "2026-05-03T10:00:00Z" ]]; then
  pass "Case 2: top_3 sorted by timestamp DESC (newest first)"
else
  fail "Case 2: top_3 sort wrong. first=$FIRST_TIMESTAMP"
fi

# ============================================================
# Case 3: 全 reject (5 件) → rate=100
# ============================================================

REC3="$TMP_DIR/rec3-all-reject.jsonl"
for i in 1 2 3 4 5; do
  cat >> "$REC3" <<JSONL
{"data":{"alert_kind":"cost-warning","decision":"reject_suggestion","reasoning":"r$i","timestamp":"2026-05-0${i}T00:00:00Z","project":"myproj"}}
JSONL
done

OUT="$(bash "$SCRIPT" --alert-kind cost-warning --project myproj --records-file "$REC3")"

if echo "$OUT" | jq -e '
  .total_count == 5 and
  .rejected_count == 5 and
  .rejection_rate_pct == 100
' >/dev/null 2>&1; then
  pass "Case 3 (全 reject): rate=100"
else
  fail "Case 3: bad output. got: $OUT"
fi

# ============================================================
# Case 4: 全 follow (5 件) → rate=0
# ============================================================

REC4="$TMP_DIR/rec4-all-follow.jsonl"
for i in 1 2 3 4 5; do
  cat >> "$REC4" <<JSONL
{"data":{"alert_kind":"high-risk-file","decision":"follow_suggestion","reasoning":"f$i","timestamp":"2026-05-0${i}T00:00:00Z","project":"myproj"}}
JSONL
done

OUT="$(bash "$SCRIPT" --alert-kind high-risk-file --project myproj --records-file "$REC4")"

if echo "$OUT" | jq -e '
  .total_count == 5 and
  .rejected_count == 0 and
  .rejection_rate_pct == 0
' >/dev/null 2>&1; then
  pass "Case 4 (全 follow): rate=0"
else
  fail "Case 4: bad output. got: $OUT"
fi

# ============================================================
# (c) cross-project default OFF 確認
# ============================================================

# OFF: project=myproj 指定で otherproj record は除外
REC_MIX="$TMP_DIR/rec-mix-projects.jsonl"
cat > "$REC_MIX" <<'JSONL'
{"data":{"alert_kind":"time-overrun","decision":"reject_suggestion","reasoning":"a","timestamp":"2026-05-01T00:00:00Z","project":"myproj"}}
{"data":{"alert_kind":"time-overrun","decision":"follow_suggestion","reasoning":"b","timestamp":"2026-05-02T00:00:00Z","project":"otherproj"}}
{"data":{"alert_kind":"time-overrun","decision":"reject_suggestion","reasoning":"c","timestamp":"2026-05-03T00:00:00Z","project":"otherproj"}}
JSONL

OUT="$(bash "$SCRIPT" --alert-kind time-overrun --project myproj --records-file "$REC_MIX")"
if echo "$OUT" | jq -e '
  .total_count == 1 and
  .cross_project_used == false
' >/dev/null 2>&1; then
  pass "(c) cross-project default OFF: project=myproj のみ集計 (1 件), cross_project_used=false"
else
  fail "(c) default OFF: bad output. got: $OUT"
fi

# ON: cross-project-group 指定で全 records 集計
OUT_CROSS="$(bash "$SCRIPT" --alert-kind time-overrun --project myproj --records-file "$REC_MIX" --cross-project-group "TestG")"
if echo "$OUT_CROSS" | jq -e '
  .total_count == 3 and
  .cross_project_used == true
' >/dev/null 2>&1; then
  pass "(c) cross-project ON: project filter 解除 (3 件全集計), cross_project_used=true"
else
  fail "(c) cross-project ON: bad output. got: $OUT_CROSS"
fi

# ============================================================
# 共通: alert kind enum 検証
# ============================================================

if bash "$SCRIPT" --alert-kind not-a-kind --project myproj --records-file "$REC1" >/dev/null 2>&1; then
  fail "invalid alert kind: expected exit 2"
else
  pass "invalid alert kind: exit 2 as expected"
fi

# ============================================================
# 共通: records-file not found
# ============================================================

if bash "$SCRIPT" --alert-kind scope-creep --project myproj --records-file "/nonexistent" >/dev/null 2>&1; then
  fail "missing records-file: expected exit 1"
else
  pass "missing records-file: exit 1 as expected"
fi

# ============================================================
# 共通: required args missing
# ============================================================

if bash "$SCRIPT" --alert-kind scope-creep --project myproj 2>/dev/null; then
  fail "missing --records-file: expected exit 2"
else
  pass "missing --records-file: exit 2 as expected"
fi

# ============================================================
# Result
# ============================================================

echo ""
echo "============================================================"
echo "Test Summary (test-progress-past-judgments.sh)"
echo "============================================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for msg in "${FAIL_MESSAGES[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi

exit 0
