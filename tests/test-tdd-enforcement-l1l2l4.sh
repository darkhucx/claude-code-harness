#!/bin/bash
# Focused Phase 68 local-trial smoke test for TDD L1/L2/L4 assets.
#
# L1: worker self-review / red-log signal source
# L2: reviewer and harness-review critical checks
# L4: validate-plugin static compliance gate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "ok - $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "not ok - $1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    pass "$label exists"
  else
    fail "$label missing: $path"
  fi
}

assert_executable() {
  local path="$1"
  local label="$2"
  if [ -x "$path" ]; then
    pass "$label is executable"
  else
    fail "$label is not executable: $path"
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "$needle" "$path"; then
    pass "$label"
  else
    fail "$label missing needle: $needle"
  fi
}

assert_json_field() {
  local json="$1"
  local key="$2"
  local want="$3"
  local label="$4"
  if JSON_INPUT="$json" python3 - "$key" "$want" <<'PY' >/dev/null 2>&1
import json
import os
import sys

key, want = sys.argv[1], sys.argv[2]
data = json.loads(os.environ["JSON_INPUT"])
if str(data.get(key)) != want:
    raise SystemExit(1)
PY
  then
    pass "$label"
  else
    fail "$label"
  fi
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for this test" >&2
  exit 1
fi

TDD_PATHS_FILE="$PLUGIN_ROOT/.claude/rules/tdd-paths.yaml"
TDD_DETECT_SCRIPT="$PLUGIN_ROOT/scripts/detect-test-framework.sh"
TDD_LOG_SCRIPT="$PLUGIN_ROOT/scripts/log-tdd-red.sh"
SPRINT_CONTRACT_GO="$PLUGIN_ROOT/go/internal/hookhandler/sprint_contract.go"

echo "1..30"

# L1: self-review and shared red-log source.
assert_contains "$PLUGIN_ROOT/harness.toml" "[tdd.enforce]" "L1 config exposes tdd.enforce"
assert_contains "$PLUGIN_ROOT/harness.toml" "enabled = false" "L1 config stays opt-in by default"
assert_contains "$PLUGIN_ROOT/harness.toml" "tdd-red-evidence-attached" "L1 self-review rule is registered in config"
assert_contains "$PLUGIN_ROOT/agents/worker.md" "tdd-red-evidence-attached" "L1 worker report requires red evidence when enabled"
if grep -Eq '^argument-hint: .*--tdd-bypass' "$PLUGIN_ROOT/skills-codex/harness-work/SKILL.md"; then
  pass "L1 Codex harness-work argument hint exposes TDD bypass"
else
  fail "L1 Codex harness-work argument hint missing TDD bypass"
fi
assert_contains "$PLUGIN_ROOT/skills-codex/harness-work/SKILL.md" "--tdd-bypass" "L1 Codex harness-work exposes TDD bypass"
assert_contains "$PLUGIN_ROOT/skills-codex/harness-work/SKILL.md" "log-tdd-red.sh" "L1 Codex harness-work records red-log evidence"
if grep -Eq '^argument-hint: .*--tdd-bypass' "$PLUGIN_ROOT/codex/.codex/skills/harness-work/SKILL.md"; then
  pass "L1 Codex mirror argument hint exposes TDD bypass"
else
  fail "L1 Codex mirror argument hint missing TDD bypass"
fi
assert_contains "$PLUGIN_ROOT/codex/.codex/skills/harness-work/SKILL.md" "--tdd-bypass" "L1 Codex mirror exposes TDD bypass"
assert_contains "$PLUGIN_ROOT/codex/.codex/skills/harness-work/SKILL.md" "log-tdd-red.sh" "L1 Codex mirror records red-log evidence"
assert_file "$TDD_LOG_SCRIPT" "L1 red-log script"
assert_executable "$TDD_LOG_SCRIPT" "L1 red-log script"

# L2: reviewer side must treat missing TDD evidence as a real review finding.
assert_contains "$PLUGIN_ROOT/agents/reviewer.md" "tdd_required=true" "L2 reviewer checks tdd_required contract"
assert_contains "$PLUGIN_ROOT/agents/reviewer.md" "critical" "L2 reviewer can escalate TDD failures to critical"
assert_contains "$PLUGIN_ROOT/skills/harness-review/SKILL.md" "TDD compliance check" "L2 harness-review has TDD section"
assert_contains "$PLUGIN_ROOT/skills/harness-review/SKILL.md" "skip_tdd_reason" "L2 harness-review checks skip reason"

# L4: validate-plugin gate and shared static sources.
assert_file "$TDD_PATHS_FILE" "L4 tdd-paths SSOT"
assert_contains "$TDD_PATHS_FILE" "schema_version: tdd-paths.v1" "L4 tdd-paths schema marker"
assert_contains "$TDD_PATHS_FILE" "src_patterns:" "L4 tdd-paths source patterns"
assert_contains "$TDD_PATHS_FILE" "test_patterns:" "L4 tdd-paths test patterns"
assert_file "$TDD_DETECT_SCRIPT" "L4 framework detector"
assert_executable "$TDD_DETECT_SCRIPT" "L4 framework detector"
assert_contains "$PLUGIN_ROOT/tests/validate-plugin.sh" "TDD compliance check (local trial)" "L4 validate-plugin has TDD section"

# Contract emitter keys consumed by L1/L2/L4.
assert_contains "$SPRINT_CONTRACT_GO" 'json:"tdd_required"' "contract emits tdd_required"
assert_contains "$SPRINT_CONTRACT_GO" 'json:"test_framework"' "contract emits test_framework"
assert_contains "$SPRINT_CONTRACT_GO" 'json:"test_todo_list"' "contract emits test_todo_list"
assert_contains "$SPRINT_CONTRACT_GO" 'json:"skip_tdd_reason"' "contract emits skip_tdd_reason"

tmp_go="$(mktemp -d)"
printf 'module example.com/tdd\n' > "$tmp_go/go.mod"
go_detect_json="$(bash "$TDD_DETECT_SCRIPT" --project-root "$tmp_go")"
assert_json_field "$go_detect_json" "framework" "go" "framework detector finds go"
rm -rf "$tmp_go" 2>/dev/null || true

tmp_none="$(mktemp -d)"
none_detect_json="$(bash "$TDD_DETECT_SCRIPT" --project-root "$tmp_none")"
assert_json_field "$none_detect_json" "framework" "none" "framework detector reports none"
rm -rf "$tmp_none" 2>/dev/null || true

tmp_log="$(mktemp -d)"
PROJECT_ROOT="$tmp_log" bash "$TDD_LOG_SCRIPT" --task-id A19 --test-file tests/a19_test.go --exit-code 1 --framework go >/dev/null
if python3 - "$tmp_log/.claude/state/tdd-red-log/A19.jsonl" <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.loads(f.readline())
if data.get("task_id") != "A19" or data.get("test_file") != "tests/a19_test.go" or data.get("exit_code") != 1:
    raise SystemExit(1)
PY
then
  pass "red-log script writes JSONL signal"
else
  fail "red-log script writes JSONL signal"
fi
rm -rf "$tmp_log" 2>/dev/null || true

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "# passed $PASS_COUNT checks"
  exit 0
fi

echo "# failed $FAIL_COUNT checks; passed $PASS_COUNT checks" >&2
exit 1
