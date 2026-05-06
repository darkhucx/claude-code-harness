#!/usr/bin/env bash
# codex-companion.sh — Proxy to official codex-plugin-cc companion
#
# 公式プラグイン openai/codex-plugin-cc の codex-companion.mjs を
# 動的に発見して呼び出す。Harness のスキル・エージェントは
# raw `codex exec` ではなく、このプロキシ経由で Codex を呼び出す。
#
# Usage:
#   bash scripts/codex-companion.sh task --write "Fix the bug"
#   bash scripts/codex-companion.sh review --base HEAD~3
#   bash scripts/codex-companion.sh setup --json
#   bash scripts/codex-companion.sh status
#   bash scripts/codex-companion.sh result <job-id>
#   bash scripts/codex-companion.sh cancel <job-id>
#
# Subcommands: task, review, adversarial-review, setup, status, result, cancel
#
# Effort 伝播:
#   task サブコマンド実行時に calculate-effort.sh で effort を計算し、
#   --effort フラグで companion に渡す。calculate-effort.sh がない場合は
#   環境変数 CODEX_EFFORT（未設定時: medium）にフォールバックする。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIMARY_ENV_GUARD="${SCRIPT_DIR}/codex-primary-environment-guard.sh"
EXECUTION_ROOT="${HARNESS_CODEX_EXECUTION_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

extract_target_cwd() {
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --cd|-C)
        printf '%s\n' "${2:-$PWD}"
        return 0
        ;;
      --cd=*|-C=*)
        printf '%s\n' "${1#*=}"
        return 0
        ;;
    esac
    shift || true
  done
  printf '%s\n' "$PWD"
}

task_has_write_intent() {
  [ "${1:-}" = "task" ] || return 1
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --write|--full-auto|--dangerously-bypass-approvals-and-sandbox)
        return 0
        ;;
      --sandbox|-s)
        case "${2:-}" in
          workspace-write|danger-full-access) return 0 ;;
        esac
        shift 2
        continue
        ;;
      --sandbox=*|-s=*)
        case "${1#*=}" in
          workspace-write|danger-full-access) return 0 ;;
        esac
        ;;
    esac
    shift || true
  done
  return 1
}

guard_primary_environment_if_needed() {
  if [ ! -x "${PRIMARY_ENV_GUARD}" ]; then
    return 0
  fi
  if task_has_write_intent "$@"; then
    local target_cwd
    target_cwd="$(extract_target_cwd "$@")"
    HARNESS_CODEX_EXECUTION_ROOT="${EXECUTION_ROOT}" \
      bash "${PRIMARY_ENV_GUARD}" --mode write --target-cwd "${target_cwd}"
  fi
}

should_use_structured_task_exec() {
  [ "${1:-}" = "task" ] || return 1
  shift || true
  for arg in "$@"; do
    case "$arg" in
      --output-schema|--output-schema=*) return 0 ;;
    esac
  done
  return 1
}

run_structured_task_exec() {
  local passthrough=()
  local saw_write=0
  local saw_sandbox=0
  local current=""

  # Codex 0.123.0+ inherits root-level shared flags for `codex exec`.
  # These exec-local sandbox defaults are kept only to encode Harness task intent:
  # `task --write` means workspace-write, and read-only remains the safe default.
  # If the caller provides --sandbox/-s/--full-auto/bypass explicitly, preserve it.
  # `--full-auto` is deprecated in current Codex guidance, so Harness must not
  # add it by default here; explicit caller intent is passed through unchanged.
  shift || true # drop "task"
  while [ $# -gt 0 ]; do
    current="$1"
    case "$current" in
      --background|--resume-last|--resume|--fresh|--prompt-file)
        echo "ERROR: structured task mode does not support ${current}" >&2
        exit 2
        ;;
      --write)
        saw_write=1
        passthrough+=(--sandbox workspace-write)
        shift
        ;;
      --sandbox|-s|--full-auto|--dangerously-bypass-approvals-and-sandbox)
        saw_sandbox=1
        passthrough+=("${current}")
        shift
        if [ "${current}" = "--sandbox" ] || [ "${current}" = "-s" ]; then
          passthrough+=("${1:-}")
          shift || true
        fi
        ;;
      --effort)
        # codex exec does not accept the companion-only --effort flag.
        # Structured task mode goes through codex exec directly, so drop it
        # here while preserving support for the Node companion path below.
        shift
        shift || true
        ;;
      --effort=*)
        # See --effort above.
        shift
        ;;
      *)
        passthrough+=("${current}")
        shift
        if [ "${current}" = "--model" ] || [ "${current}" = "-m" ] || \
           [ "${current}" = "--output-schema" ] || \
           [ "${current}" = "-o" ] || [ "${current}" = "--output-last-message" ] || \
           [ "${current}" = "-c" ] || [ "${current}" = "--config" ] || \
           [ "${current}" = "-C" ] || [ "${current}" = "--cd" ] || \
           [ "${current}" = "--add-dir" ] || [ "${current}" = "-i" ] || \
           [ "${current}" = "--image" ] || [ "${current}" = "--color" ] || \
           [ "${current}" = "--local-provider" ]; then
          passthrough+=("${1:-}")
          shift || true
        fi
        ;;
    esac
  done

  if [ "${saw_write}" -eq 0 ] && [ "${saw_sandbox}" -eq 0 ]; then
    passthrough+=(--sandbox read-only)
  fi

  exec codex exec "${passthrough[@]}"
}

# ---- auth サブコマンド ----
# codex-plugin-cc がインストールされていなくても動作するよう、
# companion 検索ブロックの前に early-exit で処理する。

CODEX_CONFIG_DIR="${HOME}/.codex"
CODEX_CONFIG_FILE="${CODEX_CONFIG_DIR}/config.toml"

_auth_read_key() {
  # config.toml から api_key の値を返す。未設定なら空文字列。
  if [ ! -f "${CODEX_CONFIG_FILE}" ]; then
    printf ''
    return 0
  fi
  grep -E '^[[:space:]]*api_key[[:space:]]*=' "${CODEX_CONFIG_FILE}" \
    | head -1 \
    | sed 's/^[[:space:]]*api_key[[:space:]]*=[[:space:]]*//' \
    | sed 's/^"//' \
    | sed 's/"[[:space:]]*$//'
}

_auth_write_key() {
  local new_key="$1"
  mkdir -p "${CODEX_CONFIG_DIR}"

  if [ ! -f "${CODEX_CONFIG_FILE}" ]; then
    # ファイルが存在しない場合は新規作成
    printf '[openai]\napi_key = "%s"\n' "${new_key}" > "${CODEX_CONFIG_FILE}"
  else
    # 既存ファイルを安全に書き換える（temp ファイル経由）
    local tmp_file
    tmp_file="$(mktemp "${CODEX_CONFIG_DIR}/.config.toml.XXXXXX")"

    local in_openai_section=0
    local key_written=0

    while IFS= read -r line || [ -n "${line}" ]; do
      # セクションヘッダの検出
      if printf '%s\n' "${line}" | grep -qE '^\['; then
        # [openai] セクションを抜けるとき、まだ書いていなければ書く
        if [ "${in_openai_section}" -eq 1 ] && [ "${key_written}" -eq 0 ]; then
          printf 'api_key = "%s"\n' "${new_key}" >> "${tmp_file}"
          key_written=1
        fi
        if printf '%s\n' "${line}" | grep -qE '^\[openai\]'; then
          in_openai_section=1
        else
          in_openai_section=0
        fi
        printf '%s\n' "${line}" >> "${tmp_file}"
        continue
      fi

      # [openai] セクション内の api_key 行を置換
      if [ "${in_openai_section}" -eq 1 ] && \
         printf '%s\n' "${line}" | grep -qE '^[[:space:]]*api_key[[:space:]]*='; then
        printf 'api_key = "%s"\n' "${new_key}" >> "${tmp_file}"
        key_written=1
        continue
      fi

      printf '%s\n' "${line}" >> "${tmp_file}"
    done < "${CODEX_CONFIG_FILE}"

    # ファイル末尾まで読んで [openai] セクションにいた場合
    if [ "${in_openai_section}" -eq 1 ] && [ "${key_written}" -eq 0 ]; then
      printf 'api_key = "%s"\n' "${new_key}" >> "${tmp_file}"
      key_written=1
    fi

    # [openai] セクション自体が存在しなかった場合は末尾に追記
    if [ "${key_written}" -eq 0 ]; then
      printf '\n[openai]\napi_key = "%s"\n' "${new_key}" >> "${tmp_file}"
    fi

    mv "${tmp_file}" "${CODEX_CONFIG_FILE}"
  fi

  chmod 600 "${CODEX_CONFIG_FILE}"
}

_auth_remove_key() {
  if [ ! -f "${CODEX_CONFIG_FILE}" ]; then
    echo "INFO: ${CODEX_CONFIG_FILE} が存在しません。" >&2
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp "${CODEX_CONFIG_DIR}/.config.toml.XXXXXX")"

  local in_openai_section=0
  local section_line_count=0
  local pending_section_header=""

  while IFS= read -r line || [ -n "${line}" ]; do
    # セクションヘッダの検出
    if printf '%s\n' "${line}" | grep -qE '^\['; then
      # 前の [openai] セクションが空だった場合はヘッダも出力しない
      if [ "${in_openai_section}" -eq 1 ] && [ "${section_line_count}" -eq 0 ]; then
        pending_section_header=""
      elif [ -n "${pending_section_header}" ]; then
        printf '%s\n' "${pending_section_header}" >> "${tmp_file}"
        pending_section_header=""
      fi

      if printf '%s\n' "${line}" | grep -qE '^\[openai\]'; then
        in_openai_section=1
        section_line_count=0
        pending_section_header="${line}"
      else
        in_openai_section=0
        pending_section_header=""
        printf '%s\n' "${line}" >> "${tmp_file}"
      fi
      continue
    fi

    # [openai] セクション内の api_key 行はスキップ（削除）
    if [ "${in_openai_section}" -eq 1 ] && \
       printf '%s\n' "${line}" | grep -qE '^[[:space:]]*api_key[[:space:]]*='; then
      continue
    fi

    # 空行や他のキーは残す
    if [ "${in_openai_section}" -eq 1 ]; then
      # 空行以外があればセクションは空でない
      if printf '%s\n' "${line}" | grep -qE '[^[:space:]]'; then
        if [ -n "${pending_section_header}" ]; then
          printf '%s\n' "${pending_section_header}" >> "${tmp_file}"
          pending_section_header=""
        fi
        section_line_count=$((section_line_count + 1))
      fi
      printf '%s\n' "${line}" >> "${tmp_file}"
    else
      printf '%s\n' "${line}" >> "${tmp_file}"
    fi
  done < "${CODEX_CONFIG_FILE}"

  # ファイル末尾での後処理
  if [ "${in_openai_section}" -eq 1 ] && [ "${section_line_count}" -eq 0 ]; then
    : # 空になった [openai] セクションのヘッダは出力しない（pending のまま）
  elif [ -n "${pending_section_header}" ]; then
    printf '%s\n' "${pending_section_header}" >> "${tmp_file}"
  fi

  mv "${tmp_file}" "${CODEX_CONFIG_FILE}"
  chmod 600 "${CODEX_CONFIG_FILE}"
}

cmd_auth() {
  local subcmd="${1:-}"

  case "${subcmd}" in
    status)
      local key
      key="$(_auth_read_key)"
      if [ -z "${key}" ]; then
        echo "API Key: not configured"
      else
        local last4="${key: -4}"
        local mtime=""
        if [ -f "${CODEX_CONFIG_FILE}" ]; then
          mtime="$(date -r "${CODEX_CONFIG_FILE}" '+%Y-%m-%d' 2>/dev/null || \
                   stat -c '%y' "${CODEX_CONFIG_FILE}" 2>/dev/null | cut -d' ' -f1 || \
                   echo "unknown")"
        fi
        echo "API Key: configured (****${last4}, saved ${mtime})"
      fi
      return 0
      ;;

    logout)
      local key
      key="$(_auth_read_key)"
      if [ -z "${key}" ]; then
        echo "API Key は設定されていません。"
        return 0
      fi
      _auth_remove_key
      echo "✓ API Key を削除しました。"
      return 0
      ;;

    "")
      # インタラクティブ入力で API Key を設定
      local existing_key
      existing_key="$(_auth_read_key)"
      if [ -n "${existing_key}" ]; then
        local last4="${existing_key: -4}"
        printf 'API Key はすでに設定されています (****%s)。上書きしますか? [y/N] ' "${last4}"
        local answer
        read -r answer
        case "${answer}" in
          y|Y|yes|YES) ;;
          *) echo "キャンセルしました。"; return 0 ;;
        esac
      fi

      printf 'OpenAI API Key を入力してください: '
      local new_key=""
      read -rs new_key
      printf '\n'

      if [ -z "${new_key}" ]; then
        echo "ERROR: API Key が空です。" >&2
        return 1
      fi

      _auth_write_key "${new_key}"
      echo "✓ API Key を ~/.codex/config.toml に保存しました。"
      return 0
      ;;

    *)
      echo "Usage: bash scripts/codex-companion.sh auth [status|logout]" >&2
      return 1
      ;;
  esac
}

# auth サブコマンドの early-exit dispatch
SUBCOMMAND_EARLY="${1:-}"
if [ "${SUBCOMMAND_EARLY}" = "auth" ]; then
  shift || true
  cmd_auth "${1:-}"
  exit $?
fi

# 公式プラグインの companion を検索
# Claude/Codex どちらの plugin ディレクトリでも見つかるようにし、
# cache と marketplace 配下の両方を対象にする。
PLUGIN_DIRS=()
[ -d "${HOME}/.claude/plugins" ] && PLUGIN_DIRS+=("${HOME}/.claude/plugins")
[ -d "${HOME}/.codex/plugins" ] && PLUGIN_DIRS+=("${HOME}/.codex/plugins")

COMPANION=""
if [ "${#PLUGIN_DIRS[@]}" -gt 0 ]; then
  # パスからバージョンセグメントを抽出し数値比較（macOS BSD sort 互換）
  COMPANION=$(find "${PLUGIN_DIRS[@]}" -name "codex-companion.mjs" \
    \( -path "*/openai-codex/*" -o -path "*/codex-plugin-cc/*" -o -path "*/plugins/codex/*" \) \
    2>/dev/null \
    | awk -F/ '{version="0.0.0"; for(i=1;i<=NF;i++){if($i~/^[0-9]+\.[0-9]+(\.[0-9]+)?$/){version=$i}} print version,$0}' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1 \
    | cut -d' ' -f2-)
fi

if [ -z "$COMPANION" ]; then
  echo "ERROR: codex-plugin-cc が見つかりません。" >&2
  echo "インストール: plugin marketplace add openai/codex-plugin-cc" >&2
  echo "または: /codex:setup を実行してください" >&2
  exit 1
fi

# ---- Effort 伝播（task サブコマンドのみ）----
# task サブコマンドの場合、タスク説明から effort を計算して --effort フラグで渡す。
# calculate-effort.sh が存在しない場合は CODEX_EFFORT 環境変数（デフォルト: medium）を使う。
SUBCOMMAND="${1:-}"
guard_primary_environment_if_needed "$@"
if should_use_structured_task_exec "$@"; then
  STRUCTURED_TASK_EXEC=1
else
  STRUCTURED_TASK_EXEC=0
fi
if [ "$SUBCOMMAND" = "task" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  EFFORT_SCRIPT="${SCRIPT_DIR}/calculate-effort.sh"

  # 既に --effort フラグが指定されている場合、または --resume-last の場合はスキップ
  # --resume-last は継続プロンプト（「続きをやって」等）が入るため effort 計算が不正確になる
  EFFORT_ALREADY_SET=0
  for arg in "$@"; do
    if [ "$arg" = "--effort" ] || echo "$arg" | grep -qE '^--effort='; then
      EFFORT_ALREADY_SET=1
      break
    fi
    if [ "$arg" = "--resume-last" ] || [ "$arg" = "--resume" ]; then
      EFFORT_ALREADY_SET=1
      break
    fi
  done

  if [ "$EFFORT_ALREADY_SET" -eq 0 ]; then
    # タスク説明を引数から抽出（最後の非フラグ引数）
    # Boolean フラグ（値を取らない）: --write, --resume-last, --json, --full-auto, --ephemeral, --oss, --skip-git-repo-check
    # 値付きフラグ（次の引数を消費）: --base, --effort, --model, -m, -i, --image, -c, --config, -C, --cd, --add-dir, --output-schema, -o, --output-last-message, --color, --enable, --disable, --local-provider
    # 未知の --* フラグ → 安全側で値付き（次引数を消費）として扱う
    TASK_DESC=""
    EXPECT_VALUE=""
    for arg in "${@:2}"; do
      if [ -n "$EXPECT_VALUE" ]; then
        # 前のフラグの値なのでスキップ
        EXPECT_VALUE=""
        continue
      fi
      case "$arg" in
        --write|--resume-last|--json|--full-auto|--ephemeral|--oss|--skip-git-repo-check|--dangerously-bypass-approvals-and-sandbox|--background|--resume|--fresh)
          # 値を取らない boolean フラグ → スキップするだけ
          ;;
        --base|--effort|--model|-m|-i|--image|-c|--config|-C|--cd|--add-dir|--output-schema|-o|--output-last-message|--color|--enable|--disable|--local-provider)
          # 明示的に値を取るフラグ
          EXPECT_VALUE="$arg"
          ;;
        --*)
          # 未知のフラグ → 安全側で値付きとして扱う（誤って次引数を TASK_DESC にしない）
          EXPECT_VALUE="$arg"
          ;;
        *)
          # 非フラグ引数 = タスク説明
          TASK_DESC="$arg"
          ;;
      esac
    done

    # effort を計算
    COMPUTED_EFFORT=""
    if [ -f "$EFFORT_SCRIPT" ]; then
      if [ -n "$TASK_DESC" ]; then
        COMPUTED_EFFORT=$(bash "$EFFORT_SCRIPT" "$TASK_DESC" 2>/dev/null || true)
      elif [ ! -t 0 ]; then
        # stdin が利用可能（パイプ）: 内容を読み取って effort を計算
        STDIN_CONTENT=$(cat)
        if [ -n "$STDIN_CONTENT" ]; then
          COMPUTED_EFFORT=$(echo "$STDIN_CONTENT" | bash "$EFFORT_SCRIPT" 2>/dev/null || true)
          # stdin を再セットアップ（here-string 経由で companion に渡す）
          if [ "${STRUCTURED_TASK_EXEC}" -eq 1 ]; then
            run_structured_task_exec "$@" --effort "${COMPUTED_EFFORT:-medium}" <<< "$STDIN_CONTENT"
          else
            exec node "$COMPANION" "$@" --effort "${COMPUTED_EFFORT:-medium}" <<< "$STDIN_CONTENT"
          fi
        fi
        # stdin が空の場合（</dev/null 等）はフォールスルーして通常フローへ
      fi
    fi

    # フォールバック: 環境変数 CODEX_EFFORT → medium
    if [ -z "$COMPUTED_EFFORT" ]; then
      COMPUTED_EFFORT="${CODEX_EFFORT:-medium}"
    fi

    # companion がサポートする effort レベルのみ渡す
    case "$COMPUTED_EFFORT" in
      none|minimal|low|medium|high|xhigh) ;;
      *) COMPUTED_EFFORT="medium" ;;
    esac

    if [ "${STRUCTURED_TASK_EXEC}" -eq 1 ]; then
      run_structured_task_exec "$@" --effort "$COMPUTED_EFFORT"
    else
      exec node "$COMPANION" "$@" --effort "$COMPUTED_EFFORT"
    fi
  fi
fi

if [ "${STRUCTURED_TASK_EXEC}" -eq 1 ]; then
  run_structured_task_exec "$@"
fi

exec node "$COMPANION" "$@"
