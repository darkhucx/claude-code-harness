#!/usr/bin/env bash
# test-codex-auth.sh
# auth / auth status / auth logout サブコマンドの単体テスト。
# 実際の API キーや ~/.codex/ を使わず、tmpdir を HOME として分離実行する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPANION="$PROJECT_ROOT/scripts/codex-companion.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "[PASS] $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "[FAIL] $1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ダミーキー（実際の API キーとは無関係な固定文字列）
DUMMY_KEY="harness-unit-test-key-placeholder"

# ---------------------------------------------------------------------------
# テスト 1: auth — ダミーキーを書き込み、ファイルの存在・パーミッション・内容を検証
# ---------------------------------------------------------------------------
run_auth_write_key() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local output
  output="$(printf '%s\n' "$DUMMY_KEY" | HOME="$tmpdir" bash "$COMPANION" auth 2>&1)"

  local config_file="$tmpdir/.codex/config.toml"

  if [ -f "$config_file" ]; then
    pass "auth write key: config.toml が作成された"
  else
    fail "auth write key: config.toml が作成されていない"
    return
  fi

  local perms
  perms="$(stat -f '%OLp' "$config_file" 2>/dev/null || stat -c '%a' "$config_file" 2>/dev/null || echo "unknown")"
  if [ "$perms" = "600" ]; then
    pass "auth write key: ファイルのパーミッションが 600"
  else
    fail "auth write key: ファイルのパーミッションが 600 でない (got: $perms)"
  fi

  if grep -q 'api_key' "$config_file"; then
    pass "auth write key: config.toml に api_key が含まれている"
  else
    fail "auth write key: config.toml に api_key が含まれていない"
  fi
}

# ---------------------------------------------------------------------------
# テスト 2: auth status — キーが設定済みの場合、configured と **** マスクを表示
# ---------------------------------------------------------------------------
run_auth_status_configured() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  # config.toml を手動で作成
  mkdir -p "$tmpdir/.codex"
  printf '[openai]\napi_key = "%s"\n' "$DUMMY_KEY" > "$tmpdir/.codex/config.toml"
  chmod 600 "$tmpdir/.codex/config.toml"

  local output
  output="$(HOME="$tmpdir" bash "$COMPANION" auth status 2>&1)"

  if printf '%s' "$output" | grep -q 'configured'; then
    pass "auth status configured: 出力に 'configured' が含まれている"
  else
    fail "auth status configured: 出力に 'configured' が含まれていない (got: $output)"
  fi

  if printf '%s' "$output" | grep -q '\*\*\*\*'; then
    pass "auth status configured: API キーがマスク (****) されている"
  else
    fail "auth status configured: API キーがマスクされていない (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 3: auth status — キーが未設定の場合、not configured を表示
# ---------------------------------------------------------------------------
run_auth_status_not_configured() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local output
  output="$(HOME="$tmpdir" bash "$COMPANION" auth status 2>&1)"

  if printf '%s' "$output" | grep -q 'not configured'; then
    pass "auth status not configured: 'not configured' が表示された"
  else
    fail "auth status not configured: 'not configured' が表示されなかった (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 4: auth logout — キーが設定済みの場合、削除して確認メッセージを表示
# ---------------------------------------------------------------------------
run_auth_logout_removes_key() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  # config.toml を手動で作成
  mkdir -p "$tmpdir/.codex"
  printf '[openai]\napi_key = "%s"\n' "$DUMMY_KEY" > "$tmpdir/.codex/config.toml"
  chmod 600 "$tmpdir/.codex/config.toml"

  local output
  output="$(HOME="$tmpdir" bash "$COMPANION" auth logout 2>&1)"

  if printf '%s' "$output" | grep -q '削除'; then
    pass "auth logout: 削除完了メッセージが表示された"
  else
    fail "auth logout: 削除完了メッセージが表示されなかった (got: $output)"
  fi

  local config_file="$tmpdir/.codex/config.toml"
  if [ -f "$config_file" ] && grep -q 'api_key' "$config_file"; then
    fail "auth logout: config.toml に api_key がまだ残っている"
  else
    pass "auth logout: api_key がファイルから削除された"
  fi
}

# ---------------------------------------------------------------------------
# テスト 5: auth logout — キーが未設定の場合、exit 0 で「設定されていません」を表示
# ---------------------------------------------------------------------------
run_auth_logout_already_empty() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local output
  local status=0
  output="$(HOME="$tmpdir" bash "$COMPANION" auth logout 2>&1)" || status=$?

  if [ "$status" -eq 0 ]; then
    pass "auth logout already empty: exit 0 で終了した"
  else
    fail "auth logout already empty: exit $status で終了した (期待: 0)"
  fi

  if printf '%s' "$output" | grep -q '設定されていません'; then
    pass "auth logout already empty: '設定されていません' が表示された"
  else
    fail "auth logout already empty: '設定されていません' が表示されなかった (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テストを実行
# ---------------------------------------------------------------------------
run_auth_write_key
run_auth_status_configured
run_auth_status_not_configured
run_auth_logout_removes_key
run_auth_logout_already_empty

echo ""
echo "passed=${PASS_COUNT} failed=${FAIL_COUNT}"
[ "${FAIL_COUNT}" -eq 0 ]
