#!/bin/bash
# tests/test-plan-brief-e2e.sh
# Phase 65.1.5 - Plan Brief end-to-end validation
#
# Validates the full Plan Brief pipeline by composing 65.1.1 - 65.1.4
# in a single fixture run:
#
#   Step 1 (request input)        : user 起動の simulation (literal text)
#   Step 2 (mem search)           : tests/fixtures/plan-brief-compile/case-*.json
#                                    (shell から MCP 不可のため fixture を投与)
#   Step 3 (HTML 生成)            : compile.sh → render-html.sh
#   Step 4 (承認)                  : record-decision.sh で approve payload を生成
#   Step 5 (mem write 後の再検索) : record の hash と request の hash が一致すること
#                                    (実 MCP 呼び出しなしで「検索可能性」を構造検証)
#
# 共通: cross-stage 整合性 (project 名 / user_request_hash / Claude Harness brand
#       palette が compile / render / record 全てに正しく propagate)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPILE="$ROOT_DIR/scripts/plan-brief-compile.sh"
RENDER="$ROOT_DIR/scripts/render-html.sh"
RECORD="$ROOT_DIR/scripts/plan-brief-record-decision.sh"
OPEN="$ROOT_DIR/scripts/plan-brief-open.sh"
SCHEMA="$ROOT_DIR/skills/harness-plan-brief/schemas/plan-brief-context.v1.schema.json"
FIXTURE_MEM="$ROOT_DIR/tests/fixtures/plan-brief-compile/case-5-all-done.json"

PASS=0
FAIL=0
FAIL_MESSAGES=()

pass() { PASS=$((PASS + 1)); echo "✓ $1"; }
fail() { FAIL=$((FAIL + 1)); FAIL_MESSAGES+=("$1"); echo "✗ $1" >&2; }

# ---- Pre-flight: 全 script が存在 + executable ----

for script in "$COMPILE" "$RENDER" "$RECORD" "$OPEN"; do
  if [[ -x "$script" ]]; then
    pass "Pre-flight: $(basename "$script") exists and is executable"
  else
    fail "Pre-flight: $(basename "$script") missing or not executable"
  fi
done

if [[ -f "$SCHEMA" ]]; then
  pass "Pre-flight: plan-brief-context.v1 schema exists"
else
  fail "Pre-flight: schema missing: $SCHEMA"
fi

if [[ -f "$FIXTURE_MEM" ]]; then
  pass "Pre-flight: mem-results fixture exists"
else
  fail "Pre-flight: fixture missing: $FIXTURE_MEM"
fi

# ---- Step 1: user request input (literal text) ----

USER_REQUEST="非エンジニア向けに進行管理 HTML を 1 枚で出してほしい。tasks 4 件を 30 分でレビューしたい。"
PROJECT_NAME="claude-code-harness-e2e-fixture"

if [[ -n "$USER_REQUEST" && -n "$PROJECT_NAME" ]]; then
  pass "Step 1: user request and project name set"
else
  fail "Step 1: user request or project name empty"
fi

# ---- Step 2: mem search 結果を fixture から読み込む (シミュレーション) ----

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plan-brief-e2e.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if jq -e '.' "$FIXTURE_MEM" >/dev/null 2>&1; then
  pass "Step 2: mem-results fixture is valid JSON"
else
  fail "Step 2: mem-results fixture parse failed"
fi

# ---- Step 3: compile + render ----

CONTEXT_JSON="$TMP_DIR/context.json"
HTML_OUT="$TMP_DIR/plan-brief.html"

if bash "$COMPILE" \
  --query "$USER_REQUEST" \
  --project "$PROJECT_NAME" \
  --mem-results "$FIXTURE_MEM" \
  --understanding "Plans.md の cc:WIP / cc:TODO / cc:完了 件数を 1 枚 HTML で可視化したい" \
  --out "$CONTEXT_JSON" 2>/dev/null; then
  pass "Step 3a: compile.sh succeeded → context.json"
else
  fail "Step 3a: compile.sh failed"
fi

# context JSON が plan-brief-context.v1 schema に valid (Python jsonschema 優先)
validated=0
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "
import json, sys
try: import jsonschema
except ImportError: sys.exit(2)
schema = json.load(open('$SCHEMA'))
data   = json.load(open('$CONTEXT_JSON'))
try:
    jsonschema.validate(data, schema)
    print('OK')
except jsonschema.ValidationError as e:
    print(f'FAIL: {e.message}')
    sys.exit(1)
" 2>/dev/null | grep -q OK; then
    pass "Step 3a: context.json validates against plan-brief-context.v1 schema (Python jsonschema)"
    validated=1
  fi
fi

if [[ "$validated" -eq 0 ]]; then
  # jq 構造的 fallback
  if jq -e '.schema == "plan-brief-context.v1"' "$CONTEXT_JSON" >/dev/null 2>&1; then
    pass "Step 3a: context.json has schema = plan-brief-context.v1 (jq fallback)"
  else
    fail "Step 3a: context.json schema field mismatch"
  fi
fi

# context の project と confidence を検証
ctx_proj="$(jq -r '.project' "$CONTEXT_JSON")"
if [[ "$ctx_proj" == "$PROJECT_NAME" ]]; then
  pass "Step 3a: context.project propagates from --project"
else
  fail "Step 3a: context.project mismatch: $ctx_proj vs $PROJECT_NAME"
fi

ctx_conf="$(jq -r '.confidence' "$CONTEXT_JSON")"
if [[ "$ctx_conf" -ge 0 && "$ctx_conf" -le 100 ]]; then
  pass "Step 3a: context.confidence in [0, 100] (got $ctx_conf)"
else
  fail "Step 3a: context.confidence out of range: $ctx_conf"
fi

# 5 全完了 + 6 D/P + DoD 数値あり → confidence 100 期待
if [[ "$ctx_conf" -ge 95 ]]; then
  pass "Step 3a: confidence is high as expected for 5-all-done fixture (got $ctx_conf, expected ≥ 95)"
else
  fail "Step 3a: confidence unexpectedly low for 5-all-done fixture: $ctx_conf"
fi

# Locale regression: GNU tr / awk style byte splitting can corrupt UTF-8 under
# LC_ALL=C and undercount Japanese sentence boundaries. The compile step must
# keep the same confidence signal in that CI-like locale.
CONTEXT_JSON_C_LOCALE="$TMP_DIR/context-c-locale.json"
if env LC_ALL=C LANG=C bash "$COMPILE" \
  --query "$USER_REQUEST" \
  --project "$PROJECT_NAME" \
  --mem-results "$FIXTURE_MEM" \
  --understanding "Plans.md の cc:WIP / cc:TODO / cc:完了 件数を 1 枚 HTML で可視化したい" \
  --out "$CONTEXT_JSON_C_LOCALE" 2>/dev/null; then
  ctx_conf_c_locale="$(jq -r '.confidence' "$CONTEXT_JSON_C_LOCALE")"
  if [[ "$ctx_conf_c_locale" -ge 95 ]]; then
    pass "Step 3a: LC_ALL=C compile keeps high confidence (got $ctx_conf_c_locale, expected ≥ 95)"
  else
    fail "Step 3a: LC_ALL=C compile lowered confidence unexpectedly: $ctx_conf_c_locale"
  fi
else
  fail "Step 3a: LC_ALL=C compile.sh failed"
fi

# ---- Step 3b: render HTML ----

if bash "$RENDER" --template plan-brief --data "$CONTEXT_JSON" --out "$HTML_OUT" 2>/dev/null; then
  pass "Step 3b: render-html.sh succeeded → plan-brief.html"
else
  fail "Step 3b: render-html.sh failed"
fi

if [[ -f "$HTML_OUT" && -s "$HTML_OUT" ]]; then
  pass "Step 3b: HTML file exists and is non-empty"
else
  fail "Step 3b: HTML file missing or empty"
fi

# HTML には user_request, project, brand palette が含まれる
if grep -qF "$USER_REQUEST" "$HTML_OUT"; then
  pass "Step 3b: HTML contains user_request literal"
else
  fail "Step 3b: HTML missing user_request"
fi

if grep -qF "$PROJECT_NAME" "$HTML_OUT"; then
  pass "Step 3b: HTML contains project name"
else
  fail "Step 3b: HTML missing project name"
fi

# Claude Harness brand palette の 3 色が HTML 内に存在
for color in "#FAFAFA" "#0F0F0F" "#F58A4A"; do
  if grep -qF "$color" "$HTML_OUT"; then
    pass "Step 3b: HTML contains Claude Harness palette color $color"
  else
    fail "Step 3b: HTML missing palette color $color"
  fi
done

# 全 {{...}} が resolve 済み
if grep -qE '\{\{[a-zA-Z]' "$HTML_OUT"; then
  fail "Step 3b: HTML contains unresolved {{...}} tags"
else
  pass "Step 3b: All {{...}} tags resolved"
fi

# ---- Step 4: 承認 (record-decision approve) ----

RECORD_JSON="$TMP_DIR/record.json"

if bash "$RECORD" \
  --action approve \
  --user-request "$USER_REQUEST" \
  --project "$PROJECT_NAME" \
  --chosen-option "Option A: Plans.md grep + render-html.sh" \
  --rejected-options "Option B: Heavy SPA, Option C: PDF only" \
  --reasoning "MVP として shell pipeline で十分" \
  --out "$RECORD_JSON" 2>/dev/null; then
  pass "Step 4: record-decision.sh succeeded → record.json"
else
  fail "Step 4: record-decision.sh failed"
fi

# tags 検証
if jq -e '.tags | index("personal-preference")' "$RECORD_JSON" >/dev/null 2>&1; then
  pass "Step 4: record.tags includes 'personal-preference' (searchable)"
else
  fail "Step 4: record.tags missing 'personal-preference'"
fi

if jq -e '.tags | index("plan-brief-approval")' "$RECORD_JSON" >/dev/null 2>&1; then
  pass "Step 4: record.tags includes 'plan-brief-approval' (searchable)"
else
  fail "Step 4: record.tags missing 'plan-brief-approval'"
fi

# record の project が compile / project name と一致
rec_proj="$(jq -r '.data.project' "$RECORD_JSON")"
if [[ "$rec_proj" == "$PROJECT_NAME" ]]; then
  pass "Step 4: record.data.project matches compile.project ($PROJECT_NAME)"
else
  fail "Step 4: record.data.project mismatch: $rec_proj"
fi

# ---- Step 5: mem write 後の再検索 (構造検証) ----
#
# 実 MCP 呼び出しは shell から不可なので「検索可能性」を構造的に検証:
#   (i)  record.data.user_request_hash が、別途 sha256 で USER_REQUEST を再計算した値と一致
#         → 同じ request で再 search すれば必ず join できる (決定性)
#   (ii) record.tags に "personal-preference" が含まれる (Step 4 で確認済み)
#   (iii) record.data.project が search filter で project=PROJECT_NAME に hit する形式

# (i) hash 決定性の独立検証
if command -v sha256sum >/dev/null 2>&1; then
  expected_hash="$(printf '%s' "$USER_REQUEST" | sha256sum | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  expected_hash="$(printf '%s' "$USER_REQUEST" | shasum -a 256 | awk '{print $1}')"
else
  expected_hash=""
fi

actual_hash="$(jq -r '.data.user_request_hash' "$RECORD_JSON")"

if [[ -n "$expected_hash" && "$expected_hash" == "$actual_hash" ]]; then
  pass "Step 5: user_request_hash is deterministic (recomputed sha256 matches record)"
else
  fail "Step 5: hash mismatch — expected=$expected_hash, actual=$actual_hash"
fi

# (iii) project が search filter で hit する形式 (non-empty + literal match-able)
if [[ -n "$rec_proj" ]]; then
  pass "Step 5: record.data.project is searchable (non-empty: '$rec_proj')"
else
  fail "Step 5: record.data.project empty (not searchable)"
fi

# ---- Bonus: auto-open dispatch (BROWSER=true で skip 動作) ----

OPEN_OUT="$(BROWSER=true bash "$OPEN" "$HTML_OUT" 2>/dev/null || true)"
if [[ -n "$OPEN_OUT" ]]; then
  pass "Step 5+: plan-brief-open.sh dispatches with BROWSER=true (CI-safe)"
else
  fail "Step 5+: plan-brief-open.sh produced no output"
fi

# ---- Cross-stage consistency final check ----

# 同じ request → 同じ hash であることを別実行で確認 (記録の re-attach 可能性)
RECORD_JSON_2="$TMP_DIR/record-2.json"
bash "$RECORD" \
  --action question \
  --user-request "$USER_REQUEST" \
  --project "$PROJECT_NAME" \
  --reasoning "後で確認" \
  --out "$RECORD_JSON_2" 2>/dev/null

hash_action_a="$(jq -r '.data.user_request_hash' "$RECORD_JSON")"
hash_action_b="$(jq -r '.data.user_request_hash' "$RECORD_JSON_2")"

if [[ "$hash_action_a" == "$hash_action_b" ]]; then
  pass "Cross-stage: same request → same hash across approve+question records (join-able)"
else
  fail "Cross-stage: hash differs between actions for same request"
fi

# ---- Summary ----

echo ""
echo "============================================"
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "FAIL details:" >&2
  for msg in "${FAIL_MESSAGES[@]}"; do
    echo "  - $msg" >&2
  done
  exit 1
fi
echo "Plan Brief e2e: full 5-step round-trip verified."
exit 0
