#!/bin/bash
# set-locale.sh
# Switch skill descriptions between English (default), Japanese, and Chinese.
#
# Usage: ./scripts/i18n/set-locale.sh [ja|en|zh]
#
# When 'ja': copies description-ja value into description field
# When 'zh': copies description-zh value into description field (darkhucx fork opt-in)
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

if [[ -z "$LOCALE" ]] || [[ "$LOCALE" != "ja" && "$LOCALE" != "en" && "$LOCALE" != "zh" ]]; then
  echo "Usage: $0 [ja|en|zh]"
  echo ""
  echo "  ja  - Set skill descriptions to Japanese"
  echo "  en  - Set skill descriptions to English (default)"
  echo "  zh  - Set skill descriptions to Chinese (darkhucx fork opt-in, Phase 62)"
  exit 1
fi

echo -e "${CYAN}🌐 Setting locale to: ${LOCALE}${NC}"
echo ""

updated=0
skipped=0
errors=0

extract_frontmatter_value() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    NR == 1 {
      if ($0 != "---") {
        exit 3
      }
      next
    }
    $0 == "---" {
      exit 2
    }
    index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]*/, "", value)
      print value
      exit 0
    }
    NR > 80 {
      exit 4
    }
  ' "$file"
}

replace_description() {
  local skill_file="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v value="$value" '
    /^description: / && replaced == 0 {
      print "description: " value
      replaced = 1
      next
    }
    { print }
  ' "$skill_file" > "$tmp"
  cat "$tmp" > "$skill_file"
  rm -f "$tmp"
}

insert_description_en() {
  local skill_file="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v value="$value" '
    /^description: / && inserted == 0 {
      print
      print "description-en: " value
      inserted = 1
      next
    }
    { print }
  ' "$skill_file" > "$tmp"
  cat "$tmp" > "$skill_file"
  rm -f "$tmp"
}

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

    if [[ "$LOCALE" == "ja" || "$LOCALE" == "zh" ]]; then
      # Extract description-<locale> value and write it to description
      local source_field="description-${LOCALE}"
      local has_source
      has_source=$(grep -c "^${source_field}:" "$skill_file" 2>/dev/null || true)

      if [[ "$has_source" -eq 0 ]]; then
        echo -e "  ${YELLOW}⊘${NC} $relative_path (no ${source_field}, skipping)"
        skipped=$((skipped + 1))
        continue
      fi

      local source_value
      source_value=$(grep "^${source_field}:" "$skill_file" | sed "s/^${source_field}: *//")

      if [[ -z "$source_value" ]]; then
        echo -e "  ${RED}✗${NC} $relative_path (empty ${source_field})"
        errors=$((errors + 1))
        continue
      fi

      # First, backup current English description as description-en if not already present
      local has_en
      has_en=$(grep -c "^description-en:" "$skill_file" 2>/dev/null || true)
      if [[ "$has_en" -eq 0 ]]; then
        local en_value
        en_value="$(extract_frontmatter_value "$skill_file" "description" || true)"
        insert_description_en "$skill_file" "$en_value"
      fi

      # Replace description with the localized value
      replace_description "$skill_file" "$source_value"
      echo -e "  ${GREEN}✓${NC} $relative_path → ${LOCALE}"
      updated=$((updated + 1))

    elif [[ "$LOCALE" == "en" ]]; then
      # Restore English description from description-en
      local has_en
      has_en=$(grep -c "^description-en:" "$skill_file" 2>/dev/null || true)

      if [[ "$has_en" -gt 0 ]]; then
        local en_value
        en_value="$(extract_frontmatter_value "$skill_file" "description-en" || true)"
        replace_description "$skill_file" "$en_value"
        echo -e "  ${GREEN}✓${NC} $relative_path → en"
        updated=$((updated + 1))
      else
        echo -e "  ${YELLOW}⊘${NC} $relative_path (no description-en backup, skipping)"
        skipped=$((skipped + 1))
      fi
    fi
  done
}

# Process all skill directories
process_skill_dir "$PROJECT_ROOT/skills" "skills"
process_skill_dir "$PROJECT_ROOT/skills-codex" "skills-codex"
process_skill_dir "$PROJECT_ROOT/codex/.codex/skills" "codex/.codex/skills"
process_skill_dir "$PROJECT_ROOT/.agents/skills" ".agents/skills"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Updated: $updated${NC} | ${YELLOW}Skipped: $skipped${NC} | ${RED}Errors: $errors${NC}"

if [[ $errors -gt 0 ]]; then
  exit 1
fi

echo -e "${GREEN}✓ Locale set to '${LOCALE}' successfully${NC}"
