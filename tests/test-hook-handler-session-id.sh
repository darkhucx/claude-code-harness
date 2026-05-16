#!/usr/bin/env bash
# test-hook-handler-session-id.sh
# Phase 62.2.4: hook handler / Bash subprocess 経路の session ID 取得 policy test
#
# 検証内容:
#   (1) hook handlers は stdin JSON `.session_id` を SSOT として扱う
#   (2) `CLAUDE_CODE_SESSION_ID` env var への直接依存が hook handlers に無い
#   (3) `docs/session-id-env-policy.md` が 4 経路と 3 状態を記載
#   (4) 3 状態 (Healthy / NotConfigured / Corrupted) の命名規約準拠

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_DOC="${ROOT_DIR}/docs/session-id-env-policy.md"

# (1) policy doc が存在
[ -f "${POLICY_DOC}" ] || {
  echo "FAIL (1): ${POLICY_DOC} not found"
  exit 1
}

# (2) policy doc が 4 経路を記載
for path in 'stdin JSON' 'CLAUDE_CODE_SESSION_ID' 'session.json' 'CLAUDE_TRANSCRIPT_PATH'; do
  if ! grep -q "${path}" "${POLICY_DOC}"; then
    echo "FAIL (2): ${POLICY_DOC} missing '${path}'"
    exit 1
  fi
done

# (3) policy doc が 3 状態を記載
for state in 'Healthy' 'NotConfigured' 'Corrupted'; do
  if ! grep -q "TestSessionIdEnv_${state}" "${POLICY_DOC}"; then
    echo "FAIL (3): ${POLICY_DOC} missing TestSessionIdEnv_${state}"
    exit 1
  fi
done

# (4) hook handlers のうち session ID を扱うものは stdin JSON を使う
HOOK_HANDLER_DIR="${ROOT_DIR}/scripts/hook-handlers"
HANDLERS_WITH_SESSION_ID="$(grep -l 'session_id' "${HOOK_HANDLER_DIR}"/*.sh 2>/dev/null | sort -u)"
if [ -z "${HANDLERS_WITH_SESSION_ID}" ]; then
  echo "WARN (4): no hook handler references session_id; skipping handler check"
else
  for handler in ${HANDLERS_WITH_SESSION_ID}; do
    # 各 handler が stdin JSON 経由で session_id を取得していること:
    # - jq または python json.loads を使用
    # - .session_id を参照
    # (jq invocation は多行 (`jq -r '[ (.session_id // ""), ... ]'`) もあるため
    #  両方の grep が同時 PASS することで stdin JSON 経路を確認)
    if ! grep -q 'jq\|json\.loads' "${handler}"; then
      echo "FAIL (4a): ${handler} references session_id but does not use jq or json.loads"
      exit 1
    fi
    if ! grep -q '\.session_id' "${handler}"; then
      echo "FAIL (4b): ${handler} references session_id but does not use .session_id selector"
      exit 1
    fi
  done
fi

# (5) hook handlers は CLAUDE_CODE_SESSION_ID env に直接依存しない (stdin JSON を優先)
# 例外: 将来の helper / wrapper では env を読んでよい。現行 hook handlers では
# stdin JSON が SSOT であることを posture として固定する。
HANDLERS_USING_ENV="$(grep -l 'CLAUDE_CODE_SESSION_ID' "${HOOK_HANDLER_DIR}"/*.sh 2>/dev/null | sort -u || true)"
if [ -n "${HANDLERS_USING_ENV}" ]; then
  echo "FAIL (5): hook handlers should use stdin JSON, not CLAUDE_CODE_SESSION_ID env:"
  echo "${HANDLERS_USING_ENV}"
  echo "see ${POLICY_DOC} for the policy."
  exit 1
fi

# (6) Healthy / NotConfigured / Corrupted の説明が含まれる
grep -q 'env var あり' "${POLICY_DOC}" || {
  echo "FAIL (6): policy doc missing Healthy state description"
  exit 1
}
grep -q 'env 無し.*state file fallback' "${POLICY_DOC}" || {
  echo "FAIL (6b): policy doc missing NotConfigured state description"
  exit 1
}
grep -q 'env / state 両方無し' "${POLICY_DOC}" || {
  echo "FAIL (6c): policy doc missing Corrupted state description"
  exit 1
}

echo "PASS: test-hook-handler-session-id.sh (Phase 62.2.4) — 6 観点全 PASS"
