#!/usr/bin/env bash
# test-ollama-companion.sh
# scripts/ollama-companion.sh の単体テスト。
# 実際の Ollama デーモンを使わず、偽の curl バイナリで HTTP API をモックする。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPANION="$PROJECT_ROOT/scripts/ollama-companion.sh"

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

# ---------------------------------------------------------------------------
# テスト 1: status — Ollama が起動中（モック curl は /api/tags に成功）
# ---------------------------------------------------------------------------
run_status_running() {
  local MOCK_DIR
  MOCK_DIR="$(mktemp -d)"
  trap 'rm -rf "$MOCK_DIR"' RETURN

  cat > "$MOCK_DIR/curl" << 'FAKE'
#!/usr/bin/env bash
ARGS="$*"
if echo "$ARGS" | grep -q "api/tags"; then
  echo '{"models":[{"name":"qwen2.5-coder:7b"},{"name":"llama3.1:8b"}]}'
  exit 0
else
  exit 1
fi
FAKE
  chmod +x "$MOCK_DIR/curl"

  local output
  local status=0
  output="$(PATH="$MOCK_DIR:$PATH" bash "$COMPANION" status 2>&1)" || status=$?

  if [ "$status" -eq 0 ]; then
    pass "status running: exit 0 で終了した"
  else
    fail "status running: exit $status で終了した (期待: 0)"
  fi

  if printf '%s' "$output" | grep -qi 'running'; then
    pass "status running: 出力に 'running' が含まれている"
  else
    fail "status running: 出力に 'running' が含まれていない (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 2: status — Ollama が停止中（モック curl は常に exit 1）
# ---------------------------------------------------------------------------
run_status_not_running() {
  local MOCK_DIR
  MOCK_DIR="$(mktemp -d)"
  trap 'rm -rf "$MOCK_DIR"' RETURN

  cat > "$MOCK_DIR/curl" << 'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
  chmod +x "$MOCK_DIR/curl"

  local output
  local status=0
  output="$(PATH="$MOCK_DIR:$PATH" bash "$COMPANION" status 2>&1)" || status=$?

  if [ "$status" -ne 0 ]; then
    pass "status not running: 非ゼロ exit で終了した"
  else
    fail "status not running: exit 0 で終了した (期待: 非ゼロ)"
  fi

  if printf '%s' "$output" | grep -qiE 'not running|ollama serve'; then
    pass "status not running: 出力に 'not running' または 'ollama serve' が含まれている"
  else
    fail "status not running: 期待メッセージが含まれていない (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 3: models — モデル一覧を出力する
# ---------------------------------------------------------------------------
run_models() {
  local MOCK_DIR
  MOCK_DIR="$(mktemp -d)"
  trap 'rm -rf "$MOCK_DIR"' RETURN

  cat > "$MOCK_DIR/curl" << 'FAKE'
#!/usr/bin/env bash
ARGS="$*"
if echo "$ARGS" | grep -q "api/tags"; then
  echo '{"models":[{"name":"qwen2.5-coder:7b"},{"name":"llama3.1:8b"}]}'
  exit 0
else
  exit 1
fi
FAKE
  chmod +x "$MOCK_DIR/curl"

  local output
  output="$(PATH="$MOCK_DIR:$PATH" bash "$COMPANION" models 2>&1)"

  if printf '%s' "$output" | grep -q 'qwen2.5-coder:7b'; then
    pass "models: 出力に 'qwen2.5-coder:7b' が含まれている"
  else
    fail "models: 出力に 'qwen2.5-coder:7b' が含まれていない (got: $output)"
  fi

  if printf '%s' "$output" | grep -q 'llama3.1:8b'; then
    pass "models: 出力に 'llama3.1:8b' が含まれている"
  else
    fail "models: 出力に 'llama3.1:8b' が含まれていない (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 4: task — モック Ollama からの応答を出力する
# ---------------------------------------------------------------------------
run_task_basic() {
  local MOCK_DIR
  MOCK_DIR="$(mktemp -d)"
  trap 'rm -rf "$MOCK_DIR"' RETURN

  cat > "$MOCK_DIR/curl" << 'FAKE'
#!/usr/bin/env bash
ARGS="$*"
if echo "$ARGS" | grep -q "api/tags"; then
  echo '{"models":[{"name":"qwen2.5-coder:7b"}]}'
  exit 0
elif echo "$ARGS" | grep -q "chat/completions"; then
  echo '{"choices":[{"message":{"content":"Hello from mock Ollama"}}]}'
  exit 0
else
  exit 1
fi
FAKE
  chmod +x "$MOCK_DIR/curl"

  local output
  output="$(PATH="$MOCK_DIR:$PATH" bash "$COMPANION" task "Say hello" 2>&1)"

  if printf '%s' "$output" | grep -q 'Hello from mock Ollama'; then
    pass "task basic: 出力に 'Hello from mock Ollama' が含まれている"
  else
    fail "task basic: 期待する応答が含まれていない (got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 5: score-task — 低複雑度タスク → engine=ollama, score <= 3
# ---------------------------------------------------------------------------
run_score_task_low_complexity() {
  local output
  output="$(bash "$COMPANION" score-task "add a field" 2>&1)"

  if printf '%s' "$output" | grep -qE '"engine":\s*"ollama"'; then
    pass "score-task low: engine が 'ollama'"
  else
    fail "score-task low: engine が 'ollama' でない (got: $output)"
  fi

  # JSON から score 値を抽出して閾値チェック
  local score
  score=$(printf '%s' "$output" | grep -o '"score": *[0-9]*' | grep -o '[0-9]*' || echo "")
  if [ -n "$score" ] && [ "$score" -le 3 ]; then
    pass "score-task low: score=$score (<= 3)"
  else
    fail "score-task low: score が 3 以下でない (score=$score, got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テスト 6: score-task — 高複雑度タスク → engine=codex, score >= 4
# ---------------------------------------------------------------------------
run_score_task_high_complexity() {
  local output
  output="$(bash "$COMPANION" score-task "critical security migration for all database tables in production" 2>&1)"

  if printf '%s' "$output" | grep -qE '"engine":\s*"codex"'; then
    pass "score-task high: engine が 'codex'"
  else
    fail "score-task high: engine が 'codex' でない (got: $output)"
  fi

  # JSON から score 値を抽出して閾値チェック
  local score
  score=$(printf '%s' "$output" | grep -o '"score": *[0-9]*' | grep -o '[0-9]*' || echo "")
  if [ -n "$score" ] && [ "$score" -ge 4 ]; then
    pass "score-task high: score=$score (>= 4)"
  else
    fail "score-task high: score が 4 以上でない (score=$score, got: $output)"
  fi
}

# ---------------------------------------------------------------------------
# テストを実行
# ---------------------------------------------------------------------------
run_status_running
run_status_not_running
run_models
run_task_basic
run_score_task_low_complexity
run_score_task_high_complexity

echo ""
echo "passed=${PASS_COUNT} failed=${FAIL_COUNT}"
[ "${FAIL_COUNT}" -eq 0 ]
