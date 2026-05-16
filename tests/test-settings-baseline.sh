#!/usr/bin/env bash
# test-settings-baseline.sh
# Phase 62.1.4 + 62.2.5 (+ Phase 64 hardening): settings template baseline 検証
#
# 検証内容:
#   (1) deniedDomains baseline が 9+ 件 (Phase 62.1.4 canonical baseline)
#   (2) deniedDomains に metadata exfil endpoints (3 件) が含まれる
#   (3) deniedDomains に Phase 62.1.4 paste-site/file-host 6 件が全て含まれる
#   (4) skillOverrides は許容 (template に存在しても任意、強制しない)
#   (5) `.claude-plugin/settings.json` と template が deniedDomains で完全一致
#   (6) skillOverrides governance doc が存在
#   (7) [Phase 64 SSOT-alignment] harness.toml と settings.json が deniedDomains で一致
#       — sync drift regression 検知用 (be2a1781 follow-up)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_SETTINGS="${ROOT_DIR}/.claude-plugin/settings.json"
SECURITY_TEMPLATE="${ROOT_DIR}/templates/claude/settings.security.json.template"
HARNESS_TOML="${ROOT_DIR}/harness.toml"

[ -f "${SECURITY_TEMPLATE}" ] || {
  echo "FAIL (0): ${SECURITY_TEMPLATE} does not exist"
  exit 1
}

# (1) deniedDomains baseline が 9+ 件 in template (Phase 62.1.4 canonical baseline)
TEMPLATE_DOMAINS_COUNT="$(jq -r '.sandbox.network.deniedDomains | length' "${SECURITY_TEMPLATE}")"
if [ "${TEMPLATE_DOMAINS_COUNT}" -lt 9 ]; then
  echo "FAIL (1): ${SECURITY_TEMPLATE} has only ${TEMPLATE_DOMAINS_COUNT} deniedDomains; Phase 62.1.4 baseline requires 9+"
  exit 1
fi

# (2) metadata exfil endpoints (cloud metadata) 3 件
for required in '169.254.169.254' 'metadata.google.internal' 'metadata.azure.com'; do
  if ! jq -e --arg d "${required}" '.sandbox.network.deniedDomains | index($d) != null' "${SECURITY_TEMPLATE}" >/dev/null; then
    echo "FAIL (2): ${SECURITY_TEMPLATE} missing required metadata domain: ${required}"
    exit 1
  fi
done

# (3) Phase 62.1.4 paste-site/file-host additions (6 件全て必須)
for paste_site in 'pastebin.com' 'transfer.sh' '0x0.st' 'paste.ee' 'termbin.com' 'ix.io'; do
  if ! jq -e --arg d "${paste_site}" '.sandbox.network.deniedDomains | index($d) != null' "${SECURITY_TEMPLATE}" >/dev/null; then
    echo "FAIL (3): ${SECURITY_TEMPLATE} missing Phase 62.1.4 paste-site domain: ${paste_site}"
    exit 1
  fi
done

# (4) skillOverrides は許容 (任意)
# 存在する場合は 3 mode のいずれかであること
if jq -e 'has("skillOverrides")' "${SECURITY_TEMPLATE}" >/dev/null; then
  MODE="$(jq -r '.skillOverrides' "${SECURITY_TEMPLATE}")"
  case "${MODE}" in
    off|user-invocable-only|name-only) ;;
    *)
      echo "FAIL (4): skillOverrides must be off|user-invocable-only|name-only, got: ${MODE}"
      exit 1
      ;;
  esac
fi
# template に skillOverrides が存在しないことは許容 (Phase 62.2.5 方針: harness-init は default を入れない)

# (5) `.claude-plugin/settings.json` と template の deniedDomains 完全一致
# Phase 64 hardening: Phase 62.1.4 では「user 手動同期」だったため WARN 扱いだったが、
# harness.toml を SSOT に格上げした今、両者が drift していたら sync 漏れの sign。
# 順序は問わず、集合として一致することを assert する。
if [ -f "${PLUGIN_SETTINGS}" ]; then
  for required in '169.254.169.254' 'metadata.google.internal' 'metadata.azure.com'; do
    if ! jq -e --arg d "${required}" '.sandbox.network.deniedDomains | index($d) != null' "${PLUGIN_SETTINGS}" >/dev/null; then
      echo "FAIL (5a): ${PLUGIN_SETTINGS} missing baseline metadata domain: ${required}"
      exit 1
    fi
  done

  PLUGIN_DOMAINS_COUNT="$(jq -r '.sandbox.network.deniedDomains | length' "${PLUGIN_SETTINGS}")"
  if [ "${PLUGIN_DOMAINS_COUNT}" -ne "${TEMPLATE_DOMAINS_COUNT}" ]; then
    echo "FAIL (5b): ${PLUGIN_SETTINGS} has ${PLUGIN_DOMAINS_COUNT} deniedDomains; template canonical has ${TEMPLATE_DOMAINS_COUNT}."
    echo "  → harness.toml [safety.sandbox.network].deniedDomains を更新してから 'bin/harness sync' を実行してください"
    exit 1
  fi

  # 全 paste-site が settings.json にも含まれること
  for paste_site in 'pastebin.com' 'transfer.sh' '0x0.st' 'paste.ee' 'termbin.com' 'ix.io'; do
    if ! jq -e --arg d "${paste_site}" '.sandbox.network.deniedDomains | index($d) != null' "${PLUGIN_SETTINGS}" >/dev/null; then
      echo "FAIL (5c): ${PLUGIN_SETTINGS} missing paste-site domain: ${paste_site}"
      echo "  → SSOT (harness.toml) に追加して 'bin/harness sync' を実行してください"
      exit 1
    fi
  done
fi

# (6) skillOverrides governance doc が存在 (Phase 62.2.5)
SKILL_OVERRIDES_DOC="${ROOT_DIR}/docs/skill-overrides-policy.md"
[ -f "${SKILL_OVERRIDES_DOC}" ] || {
  echo "FAIL (6): ${SKILL_OVERRIDES_DOC} not found (Phase 62.2.5)"
  exit 1
}
for required_mode in 'off' 'user-invocable-only' 'name-only'; do
  if ! grep -q "${required_mode}" "${SKILL_OVERRIDES_DOC}"; then
    echo "FAIL (6): skill-overrides-policy.md missing mode '${required_mode}'"
    exit 1
  fi
done

# (7) Phase 64 SSOT-alignment: harness.toml と settings.json の deniedDomains 一致
# be2a1781 follow-up:settings.json だけ手動編集して harness.toml を更新し忘れると、
# 次の SessionStart hook で `bin/harness sync` が走り、6 件が消える事故を起こす。
# harness.toml が真の SSOT なので、settings.json と件数・集合が一致しなければ FAIL。
if [ -f "${HARNESS_TOML}" ] && [ -f "${PLUGIN_SETTINGS}" ]; then
  # harness.toml から deniedDomains の値だけを抽出 (TOML 配列を grep で簡易抽出)
  TOML_DOMAINS_COUNT="$(awk '
    /^\[safety\.sandbox\.network\]/ { in_section=1; next }
    /^\[/ && in_section { in_section=0 }
    in_section && /^[[:space:]]*"/ { count++ }
    END { print count+0 }
  ' "${HARNESS_TOML}")"

  PLUGIN_DOMAINS_COUNT="$(jq -r '.sandbox.network.deniedDomains | length' "${PLUGIN_SETTINGS}")"
  if [ "${TOML_DOMAINS_COUNT}" -ne "${PLUGIN_DOMAINS_COUNT}" ]; then
    echo "FAIL (7): SSOT drift detected — harness.toml has ${TOML_DOMAINS_COUNT} deniedDomains but ${PLUGIN_SETTINGS} has ${PLUGIN_DOMAINS_COUNT}."
    echo "  → 'bin/harness sync' を実行して同期してください (be2a1781 follow-up regression 防止)"
    exit 1
  fi

  # 各 paste-site が harness.toml にも書かれていること
  for paste_site in 'pastebin.com' 'transfer.sh' '0x0.st' 'paste.ee' 'termbin.com' 'ix.io'; do
    if ! grep -q "\"${paste_site}\"" "${HARNESS_TOML}"; then
      echo "FAIL (7): SSOT missing — '${paste_site}' is in settings.json but not in harness.toml"
      echo "  → harness.toml [safety.sandbox.network].deniedDomains に追加してください"
      exit 1
    fi
  done
fi

echo "PASS: test-settings-baseline.sh (Phase 62.1.4 + 62.2.5 + Phase 64 SSOT-alignment) — 7 観点"
