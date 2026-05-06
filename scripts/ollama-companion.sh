#!/usr/bin/env bash
# ollama-companion.sh — Local Ollama instance companion via OpenAI-compatible API
#
# Harness のスキル・エージェントからローカル Ollama インスタンスを呼び出す。
# codex-companion.sh / gemini-companion.sh と対称なインターフェースを提供する。
#
# Usage:
#   bash scripts/ollama-companion.sh task "Fix the bug"
#   bash scripts/ollama-companion.sh task --model llama3.1:8b "Explain this code"
#   bash scripts/ollama-companion.sh status
#   bash scripts/ollama-companion.sh models
#   bash scripts/ollama-companion.sh score-task "add a login form"
#
# Subcommands: task, status, models, score-task
#
# Environment variables:
#   OLLAMA_BASE_URL          (default: http://localhost:11434)
#   OLLAMA_DEFAULT_MODEL     (default: qwen2.5-coder:7b)

set -euo pipefail

# ---- 設定 ----
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen2.5-coder:7b}"

# ---- ユーティリティ ----

# JSON から .choices[0].message.content を抽出
# jq が使えれば jq を使い、なければ grep/cut でフォールバック
extract_content() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "$json" | jq -r '.choices[0].message.content // empty'
  else
    # フォールバック: grep + cut
    echo "$json" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4
  fi
}

# Ollama が起動しているか確認（失敗時は exit 1）
check_ollama_running() {
  if ! curl -s --max-time 3 "${OLLAMA_BASE_URL}/api/tags" >/dev/null 2>&1; then
    echo "⚠️  Ollama is not running. Start with: ollama serve" >&2
    exit 1
  fi
}

# .claude-code-harness.config.yaml から routing.ollama_score_threshold を読む
# ファイルが存在しない・キーがない場合はデフォルト 3 を返す
read_score_threshold() {
  local config_file
  # git root → cwd の順でファイルを探す
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  local candidates=(
    "${git_root:+${git_root}/.claude-code-harness.config.yaml}"
    "$(pwd)/.claude-code-harness.config.yaml"
  )
  config_file=""
  for c in "${candidates[@]}"; do
    [ -n "$c" ] && [ -f "$c" ] && { config_file="$c"; break; }
  done

  if [ -n "$config_file" ]; then
    # routing.ollama_score_threshold: N の形式を grep + awk でパース
    local val
    val=$(grep -E '^\s*ollama_score_threshold\s*:' "$config_file" 2>/dev/null \
          | awk -F: '{gsub(/[[:space:]]/, "", $2); print $2}' \
          | head -1)
    if [ -n "$val" ] && echo "$val" | grep -qE '^[0-9]+$'; then
      echo "$val"
      return
    fi
  fi
  echo "3"
}

# ---- サブコマンド: task ----
cmd_task() {
  local model="$OLLAMA_DEFAULT_MODEL"
  local prompt=""
  local _write_flag=0  # --write は interface 対称性のために受け付けるが no-op

  # 引数パース
  while [ $# -gt 0 ]; do
    case "$1" in
      --model|-m)
        shift
        model="${1:?--model requires a value}"
        ;;
      --model=*)
        model="${1#--model=}"
        ;;
      --write)
        _write_flag=1
        ;;
      --*)
        # 未知フラグは無視（対称性のため）
        ;;
      *)
        prompt="$1"
        ;;
    esac
    shift
  done

  # stdin からの入力があれば使う
  if [ -z "$prompt" ] && [ ! -t 0 ]; then
    prompt="$(cat)"
  fi

  if [ -z "$prompt" ]; then
    echo "ERROR: task subcommand requires a prompt. Usage: task [--model <name>] \"<prompt>\"" >&2
    exit 1
  fi

  check_ollama_running

  # OpenAI-compatible chat completions API へ POST
  local request_json
  request_json=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}],"stream":false}' \
    "$model" \
    "$(echo "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr -d '\n' | sed 's/$//')")

  local response
  response=$(curl -s --max-time 120 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$request_json" \
    "${OLLAMA_BASE_URL}/v1/chat/completions") || {
    echo "ERROR: Failed to reach Ollama at ${OLLAMA_BASE_URL}" >&2
    exit 1
  }

  # エラーレスポンスの検出
  if echo "$response" | grep -q '"error"'; then
    local err_msg
    if command -v jq >/dev/null 2>&1; then
      err_msg=$(echo "$response" | jq -r '.error // .error.message // "unknown error"')
    else
      err_msg=$(echo "$response" | grep -o '"error":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    echo "ERROR: Ollama API error: ${err_msg}" >&2
    exit 1
  fi

  local content
  content=$(extract_content "$response")
  if [ -z "$content" ]; then
    echo "ERROR: Could not parse response from Ollama. Raw response:" >&2
    echo "$response" >&2
    exit 1
  fi

  echo "$content"
}

# ---- サブコマンド: status ----
cmd_status() {
  if curl -s --max-time 3 "${OLLAMA_BASE_URL}/api/tags" >/dev/null 2>&1; then
    echo "✓ Ollama is running"
    exit 0
  else
    echo "⚠️  Ollama is not running. Start with: ollama serve" >&2
    exit 1
  fi
}

# ---- サブコマンド: models ----
cmd_models() {
  check_ollama_running

  local response
  response=$(curl -s --max-time 10 "${OLLAMA_BASE_URL}/api/tags") || {
    echo "ERROR: Failed to reach Ollama at ${OLLAMA_BASE_URL}" >&2
    exit 1
  }

  local names
  if command -v jq >/dev/null 2>&1; then
    names=$(echo "$response" | jq -r '.models[].name // empty' 2>/dev/null || true)
  else
    # フォールバック: grep で "name" フィールドを抽出
    names=$(echo "$response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || true)
  fi

  if [ -z "$names" ]; then
    echo "No models installed. Run: ollama pull qwen2.5-coder:7b"
  else
    echo "$names"
  fi
}

# ---- サブコマンド: score-task ----
# 純粋な bash スコアリング — 外部 API 呼び出しなし
cmd_score_task() {
  local description="$*"

  # stdin からの入力があれば使う
  if [ -z "$description" ] && [ ! -t 0 ]; then
    description="$(cat)"
  fi

  if [ -z "$description" ]; then
    echo "ERROR: score-task requires a task description" >&2
    exit 1
  fi

  local score=0
  local desc_lower
  desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

  # +1: 単語数 > 20（長い = 複雑）
  local word_count
  word_count=$(echo "$description" | wc -w | tr -d '[:space:]')
  if [ "${word_count:-0}" -gt 20 ]; then
    score=$((score + 1))
  fi

  # +1: 複雑度キーワードを含む
  if echo "$desc_lower" | grep -qE 'security|migration|architecture|refactor|database|auth'; then
    score=$((score + 1))
  fi

  # +1: ファイル数指標（数値 >= 10、または all/every/each）
  local has_file_count=0
  # 10 以上の数値を検索
  if echo "$desc_lower" | grep -qE '\b([1-9][0-9]+|[1-9][0-9])\b'; then
    has_file_count=1
  fi
  # all / every / each キーワード
  if echo "$desc_lower" | grep -qE '\b(all|every|each)\b'; then
    has_file_count=1
  fi
  score=$((score + has_file_count))

  # +2: 重大度キーワードを含む
  if echo "$desc_lower" | grep -qE 'critical|breaking|production|deploy'; then
    score=$((score + 2))
  fi

  # 閾値を設定ファイルから読む（デフォルト 3）
  local threshold
  threshold=$(read_score_threshold)

  # engine 判定: score <= threshold なら ollama、それ以外は codex
  local engine reason
  if [ "$score" -le "$threshold" ]; then
    engine="ollama"
    reason="low complexity"
  else
    engine="codex"
    reason="high complexity"
  fi

  # JSON 出力
  printf '{"score": %d, "engine": "%s", "threshold": %d, "reason": "%s"}\n' \
    "$score" "$engine" "$threshold" "$reason"
}

# ---- usage ----
usage() {
  cat >&2 <<'EOF'
Usage: bash scripts/ollama-companion.sh <subcommand> [options]

Subcommands:
  task [--model <name>] [--write] "<prompt>"
      Send a prompt to Ollama and print the response.
      Default model: $OLLAMA_DEFAULT_MODEL (qwen2.5-coder:7b)

  status
      Check if Ollama is running. Exit 0 if running, 1 otherwise.

  models
      List installed Ollama models, one per line.

  score-task "<description>"
      Score task complexity (pure bash, no API calls).
      Outputs JSON: {"score": N, "engine": "ollama|codex", "threshold": N, "reason": "..."}

Environment variables:
  OLLAMA_BASE_URL          Default: http://localhost:11434
  OLLAMA_DEFAULT_MODEL     Default: qwen2.5-coder:7b
EOF
  exit 1
}

# ---- エントリポイント ----
SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
  task)
    cmd_task "$@"
    ;;
  status)
    cmd_status "$@"
    ;;
  models)
    cmd_models "$@"
    ;;
  score-task)
    cmd_score_task "$@"
    ;;
  ""|--help|-h)
    usage
    ;;
  *)
    echo "ERROR: Unknown subcommand: '${SUBCOMMAND}'" >&2
    usage
    ;;
esac
