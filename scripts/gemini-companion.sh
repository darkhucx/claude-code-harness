#!/usr/bin/env bash
# gemini-companion.sh — Proxy to sakibsadmanshajib/gemini-plugin-cc companion
#
# 公式相当プラグイン gemini-plugin-cc の gemini-companion.mjs を
# 動的に発見して呼び出す。Harness のスキル・エージェントは
# raw `gemini` ではなく、このプロキシ経由で Gemini を呼び出す。
#
# Usage:
#   bash scripts/gemini-companion.sh task --write "Fix the bug"
#   bash scripts/gemini-companion.sh review --base HEAD~3
#   bash scripts/gemini-companion.sh setup --json
#   bash scripts/gemini-companion.sh status
#   bash scripts/gemini-companion.sh result <job-id>
#   bash scripts/gemini-companion.sh cancel <job-id>
#
# Subcommands: task, review, adversarial-review, setup, status, result, cancel
#
# Thinking 伝播 (Codex の effort 相当):
#   task サブコマンド実行時に calculate-effort.sh で effort を計算し、
#   Gemini の --thinking フラグ (off|low|medium|high) にマップして渡す。
#   calculate-effort.sh がない場合は環境変数 GEMINI_THINKING
#   (または CODEX_EFFORT 互換) を使い、最終的には medium にフォールバック。

set -euo pipefail

# Codex の --effort 6 段階を Gemini の --thinking 4 段階に正規化する
# none|minimal → off, low → low, medium → medium, high|xhigh → high
normalize_thinking_level() {
  case "${1:-medium}" in
    off|none|minimal) echo "off" ;;
    low) echo "low" ;;
    medium) echo "medium" ;;
    high|xhigh) echo "high" ;;
    *) echo "medium" ;;
  esac
}

# 公式相当プラグインの companion を検索
# Claude/Codex どちらの plugin ディレクトリでも見つかるようにし、
# cache と marketplace 配下の両方を対象にする。
PLUGIN_DIRS=()
[ -d "${HOME}/.claude/plugins" ] && PLUGIN_DIRS+=("${HOME}/.claude/plugins")
[ -d "${HOME}/.codex/plugins" ] && PLUGIN_DIRS+=("${HOME}/.codex/plugins")

COMPANION=""
if [ "${#PLUGIN_DIRS[@]}" -gt 0 ]; then
  # パスからバージョンセグメントを抽出し数値比較（macOS BSD sort 互換）
  COMPANION=$(find "${PLUGIN_DIRS[@]}" -name "gemini-companion.mjs" \
    \( -path "*/gemini-plugin-cc/*" -o -path "*/google-gemini/*" -o -path "*/plugins/gemini/*" \) \
    2>/dev/null \
    | awk -F/ '{version="0.0.0"; for(i=1;i<=NF;i++){if($i~/^[0-9]+\.[0-9]+(\.[0-9]+)?$/){version=$i}} print version,$0}' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1 \
    | cut -d' ' -f2-)
fi

if [ -z "$COMPANION" ]; then
  echo "ERROR: gemini-plugin-cc が見つかりません。" >&2
  echo "インストール: /plugin marketplace add sakibsadmanshajib/gemini-plugin-cc" >&2
  echo "          次に: /plugin install gemini@google-gemini" >&2
  echo "または: /gemini:setup を実行してください" >&2
  exit 1
fi

# ---- Thinking 伝播（task サブコマンドのみ）----
# task サブコマンドの場合、タスク説明から effort を計算して --thinking フラグで渡す。
# calculate-effort.sh が存在しない場合は環境変数 (GEMINI_THINKING or CODEX_EFFORT) を使う。
SUBCOMMAND="${1:-}"
if [ "$SUBCOMMAND" = "task" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  EFFORT_SCRIPT="${SCRIPT_DIR}/calculate-effort.sh"

  # 既に --thinking フラグが指定されている場合、または --resume-last の場合はスキップ
  THINKING_ALREADY_SET=0
  for arg in "$@"; do
    if [ "$arg" = "--thinking" ] || echo "$arg" | grep -qE '^--thinking='; then
      THINKING_ALREADY_SET=1
      break
    fi
    if [ "$arg" = "--resume-last" ] || [ "$arg" = "--resume" ]; then
      THINKING_ALREADY_SET=1
      break
    fi
  done

  if [ "$THINKING_ALREADY_SET" -eq 0 ]; then
    # タスク説明を引数から抽出（最後の非フラグ引数）
    # Boolean フラグ: --write, --resume-last, --json, --background, --wait, --fresh, --stream-output
    # 値付きフラグ: --base, --effort, --thinking, --model, --approval-mode, -m, -c, --config, --cd, --add-dir, --output-schema, -o, --output-last-message, --color
    TASK_DESC=""
    EXPECT_VALUE=""
    for arg in "${@:2}"; do
      if [ -n "$EXPECT_VALUE" ]; then
        EXPECT_VALUE=""
        continue
      fi
      case "$arg" in
        --*=*)
          # インライン値 (--foo=bar) — 自己完結、次引数を消費しない
          ;;
        --write|--resume-last|--json|--background|--wait|--fresh|--stream-output|--skip-git-repo-check)
          ;;
        --base|--effort|--thinking|--model|--approval-mode|-m|-c|--config|-C|--cd|--add-dir|--output-schema|-o|--output-last-message|--color)
          EXPECT_VALUE="$arg"
          ;;
        --*)
          # 未知の long フラグ → 安全側で値付き扱い（次引数を誤って TASK_DESC にしない）
          EXPECT_VALUE="$arg"
          ;;
        -*)
          # 未知の短フラグ → TASK_DESC を上書きしないよう無視する
          # 既知の短フラグ (-m, -c, -o など) は上の case で先に捕捉済み
          ;;
        *)
          TASK_DESC="$arg"
          ;;
      esac
    done

    # effort を計算 (calculate-effort.sh は Codex 形式を返す: none|minimal|low|medium|high|xhigh)
    # stdin がある場合はバイト列を保存するため tempfile を使う
    # (bash 変数に格納すると null byte が失われ、multimodal データが壊れる)
    COMPUTED_EFFORT=""
    TMP_STDIN=""
    cleanup_tmp_stdin() {
      [ -n "${TMP_STDIN:-}" ] && rm -f "$TMP_STDIN"
    }
    trap cleanup_tmp_stdin EXIT
    if [ -f "$EFFORT_SCRIPT" ]; then
      if [ -n "$TASK_DESC" ]; then
        COMPUTED_EFFORT=$(bash "$EFFORT_SCRIPT" "$TASK_DESC" 2>/dev/null || true)
      elif [ ! -t 0 ]; then
        TMP_STDIN=$(mktemp "${TMPDIR:-/tmp}/gemini-stdin-XXXXXX")
        cat > "$TMP_STDIN"
        if [ -s "$TMP_STDIN" ]; then
          COMPUTED_EFFORT=$(bash "$EFFORT_SCRIPT" < "$TMP_STDIN" 2>/dev/null || true)
          COMPUTED_THINKING="$(normalize_thinking_level "${COMPUTED_EFFORT:-medium}")"
          node "$COMPANION" "$@" --thinking "${COMPUTED_THINKING}" < "$TMP_STDIN"
          exit $?
        fi
      fi
    fi

    # フォールバック: GEMINI_THINKING → CODEX_EFFORT → medium
    if [ -z "$COMPUTED_EFFORT" ]; then
      COMPUTED_EFFORT="${GEMINI_THINKING:-${CODEX_EFFORT:-medium}}"
    fi

    COMPUTED_THINKING="$(normalize_thinking_level "$COMPUTED_EFFORT")"
    exec node "$COMPANION" "$@" --thinking "$COMPUTED_THINKING"
  fi
fi

exec node "$COMPANION" "$@"
