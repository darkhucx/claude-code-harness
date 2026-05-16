#!/bin/bash
# tests/test-cross-project-redaction-e2e.sh
# Phase 65.3.7 - Cross-Project + 3-Layer Redaction の e2e validation
#
# 検証フロー (Plans.md §65.3.7 DoD a-h):
#   (a) fixture group (3 member projects)
#   (b) 各 member project の observation 相当の data に proper nouns を仕込む
#   (c) 生成 HTML に proper nouns (NoraiCorp / YorozuPro / 田中 / 佐藤) が
#       含まれないことを grep で 0 件確認
#   (d) audit log に redaction 件数が正しく記録
#   (e) (実行は別スクリプト) validate-plugin.sh PASS
#   (f) (別スクリプト) check-consistency.sh PASS
#   (g) envelope (signals + prose) 構造に proper nouns を含めても
#       validateProseContainsSignals 相当の整合性が壊れないこと
#   (h) 既存 server 側 [REDACTED_*] mark の二重置換ガード検証

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOADER="$ROOT_DIR/scripts/load-cross-project-groups.sh"
RENDER="$ROOT_DIR/scripts/render-html.sh"

PASS=0
FAIL=0
FAIL_MESSAGES=()

pass() { PASS=$((PASS + 1)); echo "✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAIL_MESSAGES+=("$1"); echo "✗ $1" >&2; }

TOKENIZER_AVAILABLE="false"
if python3 -c "from fugashi import Tagger; Tagger()" 2>/dev/null; then
  TOKENIZER_AVAILABLE="true"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-redaction-e2e.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================
# (a) fixture group: 3 member projects
# ============================================================

GROUPS_YAML="$TMP_DIR/cross-project-groups.yaml"
cat > "$GROUPS_YAML" <<'YAML'
schema_version: cross-project-group.v1
groups:
  - name: TestE2E
    description: e2e validation group with 3 members
    members:
      - project-alpha
      - project-beta
      - project-gamma
YAML

MEMBERS_OUT="$(bash "$LOADER" --yaml "$GROUPS_YAML" --group "TestE2E" 2>/dev/null)"
if echo "$MEMBERS_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if len(d)==3 else 1)"; then
  pass "(a) Fixture group resolves to 3 members"
else
  fail "(a) Fixture group resolution failed"
fi

# ============================================================
# (b) fixture client dict
# ============================================================

CLIENT_DICT="$TMP_DIR/client-redaction.yaml"
cat > "$CLIENT_DICT" <<'YAML'
schema_version: client-redaction.v1
clients:
  - rule_id: e2e-c-001
    name: NoraiCorp
    aliases:
      - Norai Corp
    replace_with: "[Client_E2E_A]"
  - rule_id: e2e-c-002
    name: YorozuPro
    replace_with: "[Client_E2E_B]"
people: []
domains: []
YAML

# ============================================================
# (b) merged Plan Brief data with proper nouns embedded
# (実 MCP search の戻りを擬似する synthetic fixture)
#
# 含まれる固有名詞:
#   - NoraiCorp / YorozuPro (dict 経由で redact)
#   - 田中 / 佐藤 (NER 経由で redact, fugashi 利用可時)
#   - [REDACTED_email] (sentinel guard test, h 項目)
#   - signals/prose (envelope 構造、g 項目)
# ============================================================

DATA_E2E="$TMP_DIR/e2e-data.json"
cat > "$DATA_E2E" <<'JSON'
{
  "title": "NoraiCorp と YorozuPro の合同案件で 田中 さんと 佐藤 さんが進行中",
  "sections": [
    {"name": "NoraiCorp との打ち合わせ録"},
    {"name": "YorozuPro 側の感触: 田中 が 佐藤 に確認"},
    {"name": "Already redacted: [REDACTED_email] is in input"},
    {"name": "envelope-signal: source=project-alpha, label=NoraiCorp"}
  ]
}
JSON

# ============================================================
# Execute render-html.sh --with-redaction (Layer 2/3)
# + audit log (--audit-group / --audit-members / --audit-query-hash)
# ============================================================

OUT_HTML="$TMP_DIR/e2e-output.html"
QUERY_HASH="$(printf 'e2e-cross-project-test' | shasum -a 256 | awk '{print $1}')"
MEMBERS_CSV="project-alpha,project-beta,project-gamma"

# Clean default audit log first
rm -f .claude/state/audit/cross-project-search.jsonl

if bash "$RENDER" \
    --template test-fixture \
    --data "$DATA_E2E" \
    --out "$OUT_HTML" \
    --with-redaction \
    --client-dict "$CLIENT_DICT" \
    --audit-group "TestE2E" \
    --audit-members "$MEMBERS_CSV" \
    --audit-query-hash "$QUERY_HASH" \
    2>"$TMP_DIR/render-stderr.txt"; then
  pass "render-html.sh exit 0 with full --with-redaction + audit"
else
  fail "render-html.sh failed. stderr: $(cat "$TMP_DIR/render-stderr.txt")"
fi

if [[ ! -f "$OUT_HTML" ]]; then
  fail "HTML output not generated"
  echo "PASS=$PASS FAIL=$FAIL"
  exit 1
fi
pass "HTML output generated successfully"

# ============================================================
# (c) Plans.md DoD: 固有名詞が HTML に残っていないことを grep で確認
# ============================================================

# Latin literals (dict layer によるカバレッジ)
if grep -q -E "(NoraiCorp|YorozuPro)" "$OUT_HTML"; then
  fail "(c) Latin proper noun leaked: $(grep -E '(NoraiCorp|YorozuPro)' "$OUT_HTML" | head -1)"
else
  pass "(c) Latin proper nouns (NoraiCorp, YorozuPro) NOT in HTML (dict layer worked)"
fi

# Japanese names (NER layer によるカバレッジ、tokenizer 必要)
if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  if grep -q -E "(田中|佐藤)" "$OUT_HTML"; then
    fail "(c) Japanese name leaked: $(grep -E '(田中|佐藤)' "$OUT_HTML" | head -1)"
  else
    pass "(c) Japanese names (田中, 佐藤) NOT in HTML (NER layer worked)"
  fi
else
  pass "(c) Japanese names check: SKIPPED (tokenizer unavailable)"
fi

# Combined: the canonical Plans.md DoD command
if grep -q -E "(NoraiCorp|YorozuPro|田中|佐藤)" "$OUT_HTML"; then
  if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
    fail "(c) Plans.md DoD grep: residue found"
  else
    pass "(c) Plans.md DoD grep: tokenizer unavailable (Latin checked, JP skipped)"
  fi
else
  pass "(c) Plans.md DoD grep -E '(NoraiCorp|YorozuPro|田中|佐藤)' returns 0 results"
fi

# ============================================================
# (d) audit log: 件数記録、passed=true、schema 準拠
# ============================================================

DEFAULT_AUDIT="$ROOT_DIR/.claude/state/audit/cross-project-search.jsonl"
if [[ -f "$DEFAULT_AUDIT" ]]; then
  pass "(d) audit log file exists at default location"
else
  fail "(d) audit log not created"
fi

LATEST_LINE="$(tail -1 "$DEFAULT_AUDIT" 2>/dev/null || echo '{}')"

if echo "$LATEST_LINE" | jq -e '.schema_version == "cross-project-audit.v1"' >/dev/null 2>&1; then
  pass "(d) audit line schema = cross-project-audit.v1"
else
  fail "(d) audit line schema mismatch"
fi

if echo "$LATEST_LINE" | jq -e '.group_name == "TestE2E"' >/dev/null 2>&1; then
  pass "(d) audit line group_name = TestE2E"
else
  fail "(d) audit line group_name wrong"
fi

if echo "$LATEST_LINE" | jq -e '.member_projects | length == 3' >/dev/null 2>&1; then
  pass "(d) audit line records 3 member projects"
else
  fail "(d) audit line member_projects count wrong"
fi

if echo "$LATEST_LINE" | jq -e ".query_hash == \"$QUERY_HASH\"" >/dev/null 2>&1; then
  pass "(d) audit line query_hash matches"
else
  fail "(d) audit line query_hash mismatch"
fi

# 生クエリ文字列 'e2e-cross-project-test' は audit に記録されない (privacy)
if grep -q "e2e-cross-project-test" "$DEFAULT_AUDIT"; then
  fail "(d) RAW query string leaked in audit log!"
else
  pass "(d) audit log does NOT contain raw query string (privacy preserved)"
fi

# 件数: dict は最低 1 (NoraiCorp/YorozuPro が 4-5 回出現)
DICT_HIT="$(echo "$LATEST_LINE" | jq -r '.redaction_count.dict')"
if [[ "$DICT_HIT" -gt 0 ]]; then
  pass "(d) audit dict count > 0 (got: $DICT_HIT)"
else
  fail "(d) audit dict count = 0 (expected > 0). line: $LATEST_LINE"
fi

if [[ "$TOKENIZER_AVAILABLE" == "true" ]]; then
  NER_HIT="$(echo "$LATEST_LINE" | jq -r '.redaction_count.ner')"
  if [[ "$NER_HIT" -gt 0 ]]; then
    pass "(d) audit NER count > 0 (got: $NER_HIT)"
  else
    fail "(d) audit NER count = 0 (expected > 0). line: $LATEST_LINE"
  fi
else
  pass "(d) audit NER count check: SKIPPED"
fi

# passed_final_scan: true (residue が残っていれば false になっていた)
if echo "$LATEST_LINE" | jq -e '.output_passed_final_scan == true' >/dev/null 2>&1; then
  pass "(d) audit output_passed_final_scan = true"
else
  fail "(d) audit output_passed_final_scan != true"
fi

# ============================================================
# (g) envelope 整合性: signals/prose 構造に redact を通しても
#     不変条件が壊れない (test-fixture template に embed した envelope-like
#     section が存在することを確認)
# ============================================================

# render 後に "envelope-signal" 文言は残るが、その中の Latin proper noun
# (NoraiCorp) は redact されている。これは prose と signals の整合性が
# 「proper noun を共通 token に置換」によって保たれることを示す。
if grep -q "envelope-signal" "$OUT_HTML"; then
  pass "(g) envelope-signal label preserved in output (structural label intact)"
else
  fail "(g) envelope-signal label lost"
fi

if grep -q "source=project-alpha" "$OUT_HTML"; then
  pass "(g) envelope source field preserved"
else
  fail "(g) envelope source field lost"
fi

# label=NoraiCorp は label=[Client_E2E_A] に redact されている (dict layer)
if grep -q "label=\[Client_E2E_A\]" "$OUT_HTML"; then
  pass "(g) envelope label NoraiCorp → [Client_E2E_A] (signals consistent with prose redaction)"
else
  fail "(g) envelope label redaction did not propagate"
fi

# ============================================================
# (h) 二重置換ガード: 既存の [REDACTED_email] mark は preserved
# ============================================================

if grep -q "\[REDACTED_email\]" "$OUT_HTML"; then
  pass "(h) [REDACTED_email] sentinel mark preserved (二重置換ガード働く)"
else
  fail "(h) [REDACTED_email] was modified by Layer 2/3"
fi

# Plus dict-emitted [Client_E2E_A] / [Client_E2E_B] are sentinels for
# next-pass (idempotency)
if grep -q "\[Client_E2E_A\]" "$OUT_HTML"; then
  pass "(h) dict replacement [Client_E2E_A] present (and not re-replaced by NER)"
else
  fail "(h) dict replacement [Client_E2E_A] missing"
fi

# ============================================================
# 共通: HTML 末尾に audit footer
# ============================================================

if grep -q 'audit-summary' "$OUT_HTML" && grep -q 'redacted: dict' "$OUT_HTML"; then
  pass "HTML footer audit-summary present"
else
  fail "HTML footer audit-summary missing"
fi

# ============================================================
# Cleanup default audit (test isolation)
# ============================================================

rm -f .claude/state/audit/cross-project-search.jsonl

# ============================================================
# Result
# ============================================================

echo ""
echo "============================================================"
echo "Test Summary (test-cross-project-redaction-e2e.sh)"
echo "============================================================"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [[ "$TOKENIZER_AVAILABLE" == "false" ]]; then
  echo "(NOTE: NER cases skipped — fugashi unavailable)"
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
