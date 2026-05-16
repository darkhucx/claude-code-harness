#!/bin/bash
# harness-mem wrapper scripts should resolve the sibling repo without hardcoded Desktop paths.
#
# Local-only test: the production-side `scripts/harness-mem-client.sh` was
# removed in commit 5373d50d ("fix: exclude harness-mem wrappers and hooks from
# distribution", v2.20.10) when harness-mem became a managed npm companion.
# This test exercises the historical sibling-repo bridge contract that some
# callers (`scripts/auto-checkpoint.sh`, `scripts/codex-loop.sh`) still expect
# to be available when the operator clones harness-mem alongside this repo.
#
# Skip behavior matches `tests/test-memory-lifecycle-integration.sh`:
#   - default + missing client → skip exit 0 (clean checkout)
#   - HARNESS_MEM_REPO=/abs/path → use that copy of the client
#   - HARNESS_MEM_REQUIRE=1     → treat missing client as FAIL (CI gate)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve the production-side harness-mem-client.sh:
#   1. ROOT_DIR/scripts/harness-mem-client.sh (re-introduced locally)
#   2. HARNESS_MEM_REPO/scripts/harness-mem-client.sh (sister repo override)
#   3. ../harness-mem/scripts/harness-mem-client.sh (default sibling)
HARNESS_MEM_CLIENT_SRC=""
for candidate in \
  "${ROOT_DIR}/scripts/harness-mem-client.sh" \
  "${HARNESS_MEM_REPO:-}/scripts/harness-mem-client.sh" \
  "${ROOT_DIR}/../harness-mem/scripts/harness-mem-client.sh"; do
  if [ -n "${candidate}" ] && [ -f "${candidate}" ]; then
    HARNESS_MEM_CLIENT_SRC="${candidate}"
    break
  fi
done

if [ -z "${HARNESS_MEM_CLIENT_SRC}" ]; then
  if [ "${HARNESS_MEM_REQUIRE:-0}" = "1" ]; then
    echo "FAIL: harness-mem-client.sh not found in ROOT_DIR or sibling repo and HARNESS_MEM_REQUIRE=1" >&2
    exit 1
  fi
  echo "skip: scripts/harness-mem-client.sh not found (Phase v2.20.10 managed-companion migration)"
  echo "  this test exercises the sibling-repo bridge contract."
  echo "  to run locally, clone harness-mem alongside claude-code-harness:"
  echo "    git clone <harness-mem-url> ${ROOT_DIR}/../harness-mem"
  echo "  or set HARNESS_MEM_REPO=/abs/path/to/harness-mem"
  echo "  to enforce as CI gate, set HARNESS_MEM_REQUIRE=1"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/claude-code-harness/scripts/lib"
mkdir -p "${TMP_DIR}/claude-code-harness/scripts/hook-handlers"
mkdir -p "${TMP_DIR}/harness-mem/scripts/hook-handlers"

cp "${ROOT_DIR}/scripts/lib/harness-mem-bridge.sh" "${TMP_DIR}/claude-code-harness/scripts/lib/harness-mem-bridge.sh"
cp "${ROOT_DIR}/scripts/hook-handlers/memory-session-start.sh" "${TMP_DIR}/claude-code-harness/scripts/hook-handlers/memory-session-start.sh"
cp "${HARNESS_MEM_CLIENT_SRC}" "${TMP_DIR}/claude-code-harness/scripts/harness-mem-client.sh"

cat > "${TMP_DIR}/harness-mem/scripts/hook-handlers/memory-session-start.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'memory-session-start-ok\n'
EOF

cat > "${TMP_DIR}/harness-mem/scripts/harness-mem-client.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'harness-mem-client-ok:%s\n' "${1:-none}"
EOF

chmod +x \
  "${TMP_DIR}/claude-code-harness/scripts/hook-handlers/memory-session-start.sh" \
  "${TMP_DIR}/claude-code-harness/scripts/harness-mem-client.sh" \
  "${TMP_DIR}/harness-mem/scripts/hook-handlers/memory-session-start.sh" \
  "${TMP_DIR}/harness-mem/scripts/harness-mem-client.sh"

wrapper_output="$(cd "${TMP_DIR}/claude-code-harness" && ./scripts/hook-handlers/memory-session-start.sh)"
client_output="$(cd "${TMP_DIR}/claude-code-harness" && ./scripts/harness-mem-client.sh health)"

[ "${wrapper_output}" = "memory-session-start-ok" ] || {
  echo "memory-session-start wrapper did not resolve sibling harness-mem repo"
  exit 1
}

[ "${client_output}" = "harness-mem-client-ok:health" ] || {
  echo "harness-mem-client wrapper did not resolve sibling harness-mem repo"
  exit 1
}

echo "OK"
