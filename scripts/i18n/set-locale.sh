#!/bin/bash
# set-locale.sh
# Switch skill descriptions between English (default), Japanese, and Chinese
#
# Usage: ./scripts/i18n/set-locale.sh [ja|en|zh]
#
# When 'ja': copies description-ja value into description field
# When 'zh': copies description-zh value into description field
# When 'en': restores description to English default (from description-en backup)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOCALE="${1:-}"

case "$LOCALE" in
  ja|en|zh) ;;
  *)
    echo "Usage: $0 [ja|en|zh]"
    echo ""
    echo "  ja  - Set skill descriptions to Japanese"
    echo "  en  - Set skill descriptions to English (default)"
    echo "  zh  - Set skill descriptions to Chinese"
    exit 1
    ;;
esac

echo -e "${CYAN}🌐 Setting locale to: ${LOCALE}${NC}"
echo ""

updated=0
skipped=0
errors=0

process_skill_dir() {
  local skills_dir="$1"
  local label="$2"

  if [[ ! -d "$skills_dir" ]]; then
    return
  fi

  echo -e "${CYAN}📁 ${label}:${NC}"

  for skill_file in "$skills_dir"/*/SKILL.md; do
    if [[ ! -f "$skill_file" ]]; then
      continue
    fi

    local relative_path="${skill_file#$PROJECT_ROOT/}"

    if [[ "$LOCALE" == "en" ]]; then
      # Restore English description from description-en backup
      local has_en
      has_en=$(grep -c "^description-en:" "$skill_file" 2>/dev/null || true)

      if [[ "$has_en" -gt 0 ]]; then
        local en_value
        en_value=$(grep "^description-en:" "$skill_file" | sed 's/^description-en: *//')
        sed -i '' "s|^description: .*|description: ${en_value}|" "$skill_file"
        echo -e "  ${GREEN}✓${NC} $relative_path → en"
        updated=$((updated + 1))
      else
        echo -e "  ${YELLOW}⊘${NC} $relative_path (no description-en backup, skipping)"
        skipped=$((skipped + 1))
      fi
      continue
    fi

    # ja or zh
    local target_field="description-${LOCALE}"
    local has_target
    has_target=$(grep -c "^${target_field}:" "$skill_file" 2>/dev/null || true)

    if [[ "$has_target" -eq 0 ]]; then
      echo -e "  ${YELLOW}⊘${NC} $relative_path (no ${target_field}, skipping)"
      skipped=$((skipped + 1))
      continue
    fi

    local target_value
    target_value=$(grep "^${target_field}:" "$skill_file" | sed "s/^${target_field}: *//")

    if [[ -z "$target_value" ]]; then
      echo -e "  ${RED}✗${NC} $relative_path (empty ${target_field})"
      errors=$((errors + 1))
      continue
    fi

    # Backup current English description as description-en if not already present.
    # Only meaningful when current description is still in English (first switch from en).
    local has_en
    has_en=$(grep -c "^description-en:" "$skill_file" 2>/dev/null || true)
    if [[ "$has_en" -eq 0 ]]; then
      local en_value
      en_value=$(grep "^description:" "$skill_file" | sed 's/^description: *//')
      sed -i '' "/^description: /a\\
description-en: ${en_value}
" "$skill_file"
    fi

    # Replace description with target locale value
    sed -i '' "s|^description: .*|description: ${target_value}|" "$skill_file"
    echo -e "  ${GREEN}✓${NC} $relative_path → ${LOCALE}"
    updated=$((updated + 1))
  done
}

# Process all skill directories
process_skill_dir "$PROJECT_ROOT/skills" "skills"
# skills/ が SSOT
process_skill_dir "$PROJECT_ROOT/opencode/skills" "opencode/skills"
process_skill_dir "$PROJECT_ROOT/codex/.codex/skills" "codex/.codex/skills"
process_skill_dir "$PROJECT_ROOT/.opencode/skills" ".opencode/skills"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Updated: $updated${NC} | ${YELLOW}Skipped: $skipped${NC} | ${RED}Errors: $errors${NC}"

if [[ $errors -gt 0 ]]; then
  exit 1
fi

echo -e "${GREEN}✓ Locale set to '${LOCALE}' successfully${NC}"
