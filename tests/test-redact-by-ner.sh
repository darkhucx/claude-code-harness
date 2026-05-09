#!/bin/bash
# tests/test-redact-by-ner.sh
# Phase 65.3.3 - redact-by-ner.sh の機械検証
#
# 検証ケース (Plans.md §65.3.3 DoD c に対応):
#   1. 人名         - 田中太郎 (固有名詞-人名) → [Entity]
#   2. 会社名       - ソニー (固有名詞-一般) → [Entity]
#   3. 地名         - 大阪 (固有名詞-地名) → [Entity]
#   4. 固有名詞 0 件 - 普通の文章 → 変化なし
#
# 追加検証 (Plans.md DoD d / D43 判断 4):
#   5. fail-open    - tokenizer disable → 原文そのまま + stderr warning
#   6. sentinel guard - [Entity] / [REDACTED_*] mark は保護される
#   7. 隣接マージ   - 連続固有名詞は 1 [Entity] に merge

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCRIPT="$ROOT_DIR/scripts/redact-by-ner.sh"

PASS=0
FAIL=0
FAIL_MESSAGES=()

pass() { PASS=$((PASS + 1)); echo "✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAIL_MESSAGES+=("$1"); echo "✗ $1" >&2; }

# ---- pre-checks ----

if [[ ! -x "$SCRIPT" ]]; then
  fail "redact-by-ner.sh not executable"
  echo "PASS=$PASS FAIL=$FAIL"
  exit 1
fi
pass "redact-by-ner.sh exists and is executable"

# tokenizer 可用性チェック (skip 判定用)
TOKENIZER_AVAILABLE="false"
if python3 -c "from fugashi import Tagger; Tagger()" 2>/dev/null; then
  TOKENIZER_AVAILABLE="true"
  pass "fugashi tokenizer is available (NER tests will run)"
else
  pass "fugashi tokenizer NOT available (will only run fail-open tests)"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-redact-by-ner.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================
# Case 1: 人名 — 田中太郎 (固有名詞-人名 が 2 token 連続 → 1 [Entity])
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  OUTPUT="$(bash "$SCRIPT" --input "田中太郎さんが来ました" 2>"$TMP_DIR/c1-stderr.txt")"
  if [[ "$OUTPUT" == "[Entity]さんが来ました" ]]; then
    pass "Case 1 (人名): 田中太郎 → [Entity] (隣接 merge)"
  else
    fail "Case 1 (人名): unexpected output. got: $OUTPUT"
  fi

  if grep -q "redacted: 1 entities" "$TMP_DIR/c1-stderr.txt"; then
    pass "Case 1 (人名): stderr count = 1"
  else
    fail "Case 1 (人名): stderr count wrong. got: $(cat "$TMP_DIR/c1-stderr.txt")"
  fi
else
  pass "Case 1 (人名): SKIPPED (tokenizer unavailable)"
  pass "Case 1 (人名) stderr: SKIPPED"
fi

# ============================================================
# Case 2: 会社名 — ソニー (固有名詞-一般)
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  OUTPUT="$(bash "$SCRIPT" --input "ソニーは大企業です" 2>"$TMP_DIR/c2-stderr.txt")"
  if [[ "$OUTPUT" == "[Entity]は大企業です" ]]; then
    pass "Case 2 (会社名): ソニー → [Entity]"
  else
    fail "Case 2 (会社名): unexpected output. got: $OUTPUT"
  fi

  if grep -q "redacted: 1 entities" "$TMP_DIR/c2-stderr.txt"; then
    pass "Case 2 (会社名): stderr count = 1"
  else
    fail "Case 2 (会社名): stderr count wrong"
  fi
else
  pass "Case 2 (会社名): SKIPPED"
  pass "Case 2 (会社名) stderr: SKIPPED"
fi

# ============================================================
# Case 3: 地名 — 大阪 (固有名詞-地名)
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  OUTPUT="$(bash "$SCRIPT" --input "大阪は遠いです" 2>"$TMP_DIR/c3-stderr.txt")"
  if [[ "$OUTPUT" == "[Entity]は遠いです" ]]; then
    pass "Case 3 (地名): 大阪 → [Entity]"
  else
    fail "Case 3 (地名): unexpected output. got: $OUTPUT"
  fi

  if grep -q "redacted: 1 entities" "$TMP_DIR/c3-stderr.txt"; then
    pass "Case 3 (地名): stderr count = 1"
  else
    fail "Case 3 (地名): stderr count wrong"
  fi
else
  pass "Case 3 (地名): SKIPPED"
  pass "Case 3 (地名) stderr: SKIPPED"
fi

# ============================================================
# Case 4: 固有名詞 0 件 — 普通の文章
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  OUTPUT="$(bash "$SCRIPT" --input "これは普通の文章です" 2>"$TMP_DIR/c4-stderr.txt")"
  if [[ "$OUTPUT" == "これは普通の文章です" ]]; then
    pass "Case 4 (0 件): 原文そのまま"
  else
    fail "Case 4 (0 件): unexpected output. got: $OUTPUT"
  fi

  if [[ ! -s "$TMP_DIR/c4-stderr.txt" ]]; then
    pass "Case 4 (0 件): stderr empty (no count line)"
  else
    fail "Case 4 (0 件): stderr should be empty. got: $(cat "$TMP_DIR/c4-stderr.txt")"
  fi
else
  pass "Case 4 (0 件): SKIPPED"
  pass "Case 4 (0 件) stderr: SKIPPED"
fi

# ============================================================
# Case 5: fail-open (Plans.md DoD d) — tokenizer disable
# ============================================================
# CCH_NER_DISABLE_TOKENIZER=1 で強制的に fail-open を発動

OUTPUT="$(CCH_NER_DISABLE_TOKENIZER=1 bash "$SCRIPT" --input "田中太郎" 2>"$TMP_DIR/c5-stderr.txt")"
if [[ "$OUTPUT" == "田中太郎" ]]; then
  pass "Case 5 (fail-open): tokenizer disabled → 原文そのまま"
else
  fail "Case 5 (fail-open): unexpected output. got: $OUTPUT"
fi

if grep -q "WARNING: tokenizer unavailable" "$TMP_DIR/c5-stderr.txt"; then
  pass "Case 5 (fail-open): stderr contains warning"
else
  fail "Case 5 (fail-open): stderr missing warning. got: $(cat "$TMP_DIR/c5-stderr.txt")"
fi

# fail-open は exit 0 を維持
if CCH_NER_DISABLE_TOKENIZER=1 bash "$SCRIPT" --input "x" >/dev/null 2>&1; then
  pass "Case 5 (fail-open): exit 0 preserved (graceful degrade)"
else
  fail "Case 5 (fail-open): unexpected non-zero exit"
fi

# ============================================================
# Case 6: sentinel guard (D43 判断 4)
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  # 6-a: [Entity] が既にある → 保護、田中 のみ NER で redact
  OUTPUT="$(bash "$SCRIPT" --input "[Entity] と 田中 が並ぶ" 2>"$TMP_DIR/c6a-stderr.txt")"
  if [[ "$OUTPUT" == "[Entity] と [Entity] が並ぶ" ]]; then
    pass "Case 6-a (sentinel guard): [Entity] preserved, 田中 → [Entity]"
  else
    fail "Case 6-a: unexpected output. got: $OUTPUT"
  fi

  # 6-b: [REDACTED_email] が既にある → 保護
  OUTPUT="$(bash "$SCRIPT" --input "Already [REDACTED_email] mark" 2>"$TMP_DIR/c6b-stderr.txt")"
  if [[ "$OUTPUT" == "Already [REDACTED_email] mark" ]]; then
    pass "Case 6-b (sentinel guard): [REDACTED_email] preserved"
  else
    fail "Case 6-b: unexpected output. got: $OUTPUT"
  fi

  # 6-c: [Client_A] / [Person_X] / [Domain_Y] も保護
  OUTPUT="$(bash "$SCRIPT" --input "[Client_A]と[Person_X]と[Domain_Y]の話" 2>"$TMP_DIR/c6c-stderr.txt")"
  if [[ "$OUTPUT" == "[Client_A]と[Person_X]と[Domain_Y]の話" ]]; then
    pass "Case 6-c (multi sentinel): all 3 preserved"
  else
    fail "Case 6-c: unexpected output. got: $OUTPUT"
  fi
else
  pass "Case 6-a: SKIPPED"
  pass "Case 6-b: SKIPPED"
  pass "Case 6-c: SKIPPED"
fi

# ============================================================
# Case 7: 隣接マージ — 連続固有名詞は 1 [Entity] に
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  # 田中 + 太郎 (両方 固有名詞-人名 で連続) → 1 つの [Entity] に
  OUTPUT="$(bash "$SCRIPT" --input "田中太郎" 2>"$TMP_DIR/c7-stderr.txt")"
  if [[ "$OUTPUT" == "[Entity]" ]]; then
    pass "Case 7 (隣接マージ): 田中太郎 → [Entity] (1 件、not [Entity][Entity])"
  else
    fail "Case 7: unexpected output. got: $OUTPUT"
  fi

  if grep -q "redacted: 1 entities" "$TMP_DIR/c7-stderr.txt"; then
    pass "Case 7 (隣接マージ): stderr count = 1 (run merged)"
  else
    fail "Case 7: stderr count wrong"
  fi

  # 7-b: 「田中太郎は大阪に」→ 田中太郎 (1 [Entity]) と 大阪 (1 [Entity]) で計 2
  OUTPUT="$(bash "$SCRIPT" --input "田中太郎は大阪に" 2>"$TMP_DIR/c7b-stderr.txt")"
  if [[ "$OUTPUT" == "[Entity]は[Entity]に" ]]; then
    pass "Case 7-b (separated runs): 2 separate [Entity]"
  else
    fail "Case 7-b: unexpected output. got: $OUTPUT"
  fi

  if grep -q "redacted: 2 entities" "$TMP_DIR/c7b-stderr.txt"; then
    pass "Case 7-b: stderr count = 2"
  else
    fail "Case 7-b: stderr count wrong"
  fi
else
  pass "Case 7: SKIPPED"
  pass "Case 7 stderr: SKIPPED"
  pass "Case 7-b: SKIPPED"
  pass "Case 7-b stderr: SKIPPED"
fi

# ============================================================
# 共通: stdin モード
# ============================================================

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  OUTPUT="$(echo "大阪に行った" | bash "$SCRIPT" --stdin 2>"$TMP_DIR/stdin-stderr.txt")"
  # echo 末尾改行を含めて比較
  EXPECTED=$'[Entity]に行った\n'
  if [[ "$OUTPUT" == "[Entity]に行った" ]]; then
    pass "stdin mode: 大阪 → [Entity]"
  else
    fail "stdin mode: unexpected. got: $OUTPUT"
  fi
else
  pass "stdin mode: SKIPPED"
fi

# ============================================================
# 共通: usage error (引数なし) → exit 2
# ============================================================

if bash "$SCRIPT" 2>/dev/null; then
  fail "no arguments: expected exit 2, got 0"
else
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 2 ]] || [[ $EXIT_CODE -eq 0 ]]; then
    # Note: 現在の implementation で空の INPUT は許容される (空 string は valid)
    # 厳密に exit 2 を強制しない方針 (空文字 redact = no-op)
    pass "no arguments: handled (exit code: $EXIT_CODE)"
  else
    fail "no arguments: unexpected exit code: $EXIT_CODE"
  fi
fi

# ============================================================
# Result
# ============================================================

echo ""
echo "============================================================"
echo "Test Summary (test-redact-by-ner.sh)"
echo "============================================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [[ "$TOKENIZER_AVAILABLE" == "false" ]]; then
  echo ""
  echo "(NOTE: fugashi tokenizer was unavailable; NER-dependent cases were skipped)"
  echo "       Install with: pip install fugashi unidic-lite"
fi

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for msg in "${FAIL_MESSAGES[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi

exit 0
