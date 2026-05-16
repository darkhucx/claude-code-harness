#!/bin/bash
# Regression checks for the WorktreeCreate shell hook.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT_DIR}/scripts/hook-handlers/worktree-create.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

json_get() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get(sys.argv[2], ""))
PY
}

run_hook() {
  local payload="$1"
  local output_file="$2"
  (
    cd "${TMP_DIR}"
    printf '%s' "${payload}" | bash "${HOOK}"
  ) >"${output_file}"
}

INVALID_CWD='{"decision":"approve","reason":"WorktreeCreate: initialized worktree state"}'
INVALID_OUT="${TMP_DIR}/invalid.out"
run_hook "{\"session_id\":\"worker-json\",\"cwd\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${INVALID_CWD}")}" "${INVALID_OUT}"

[ "$(json_get "${INVALID_OUT}" decision)" = "approve" ] || fail "invalid cwd did not approve/no-op"
[ "$(json_get "${INVALID_OUT}" reason)" = "WorktreeCreate: invalid cwd" ] || fail "invalid cwd reason mismatch"
[ ! -e "${TMP_DIR}/${INVALID_CWD}" ] || fail "hook decision JSON was treated as a directory"

REAL_CWD="${TMP_DIR}/real-worktree"
mkdir -p "${REAL_CWD}"
REAL_OUT="${TMP_DIR}/real.out"
run_hook "{\"session_id\":\"worker-123\",\"cwd\":\"${REAL_CWD}\"}" "${REAL_OUT}"

[ "$(json_get "${REAL_OUT}" decision)" = "approve" ] || fail "real cwd did not approve"
[ "$(json_get "${REAL_OUT}" reason)" = "WorktreeCreate: initialized worktree state" ] || fail "real cwd reason mismatch"
[ -d "${REAL_CWD}/.claude/state" ] || fail "real cwd state dir was not created"
[ -f "${REAL_CWD}/.claude/state/worktree-info.json" ] || fail "worktree-info.json was not created"

python3 - "${REAL_CWD}/.claude/state/worktree-info.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
if data.get("worker_id") != "worker-123":
    raise SystemExit("worker_id mismatch")
if data.get("cwd") == "":
    raise SystemExit("cwd missing")
PY

echo "PASS: WorktreeCreate shell hook rejects decision JSON cwd and initializes real cwd"
