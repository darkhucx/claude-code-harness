#!/bin/bash
# check-translations.sh
# Check that all commands and skills have i18n translation fields
#
# Usage: ./scripts/i18n/check-translations.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Locales required for SKILL.md files. description-en は set-locale.sh が backup を作る運用
# なので静的な必須にはしない。
REQUIRED_SKILL_LOCALES=("description-ja" "description-zh")

echo "🌐 Checking i18n translations..."
echo ""

missing_count=0
total_count=0

# Check legacy commands for description-en
echo "📁 Commands (legacy):"
for file in "$PROJECT_ROOT"/commands/**/*.md; do
  if [[ -f "$file" ]]; then
    total_count=$((total_count + 1))
    relative_path="${file#$PROJECT_ROOT/}"
    if ! grep -q "description-en:" "$file"; then
      echo -e "  ${RED}✗${NC} $relative_path (missing description-en)"
      missing_count=$((missing_count + 1))
    else
      echo -e "  ${GREEN}✓${NC} $relative_path"
    fi
  fi
done

echo ""

# Check skills for required locale fields
skill_missing=0
skill_total=0
declare -A locale_missing_count
for locale in "${REQUIRED_SKILL_LOCALES[@]}"; do
  locale_missing_count["$locale"]=0
done

check_skills_dir() {
  local skills_dir="$1"
  local label="$2"

  if [[ ! -d "$skills_dir" ]]; then
    return
  fi

  echo "📁 ${label}:"
  for file in "$skills_dir"/*/SKILL.md; do
    if [[ ! -f "$file" ]]; then
      continue
    fi
    skill_total=$((skill_total + 1))
    total_count=$((total_count + 1))
    local relative_path="${file#$PROJECT_ROOT/}"
    local missing_locales=()

    for locale in "${REQUIRED_SKILL_LOCALES[@]}"; do
      if ! grep -q "^${locale}:" "$file"; then
        missing_locales+=("$locale")
        locale_missing_count["$locale"]=$((locale_missing_count["$locale"] + 1))
      fi
    done

    if [[ ${#missing_locales[@]} -gt 0 ]]; then
      echo -e "  ${RED}✗${NC} $relative_path (missing: ${missing_locales[*]})"
      skill_missing=$((skill_missing + 1))
      missing_count=$((missing_count + 1))
    else
      echo -e "  ${GREEN}✓${NC} $relative_path"
    fi
  done
  echo ""
}

check_skills_dir "$PROJECT_ROOT/skills" "Skills (SSOT)"
check_skills_dir "$PROJECT_ROOT/opencode/skills" "opencode/skills (mirror)"
check_skills_dir "$PROJECT_ROOT/codex/.codex/skills" "codex/.codex/skills (mirror)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $missing_count -eq 0 ]]; then
  echo -e "${GREEN}✓ All $total_count files have translations${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠ $missing_count / $total_count files missing translations${NC}"
  if [[ $skill_missing -gt 0 ]]; then
    echo -e "${YELLOW}  Skills with missing locale fields: $skill_missing / $skill_total${NC}"
    for locale in "${REQUIRED_SKILL_LOCALES[@]}"; do
      count="${locale_missing_count["$locale"]}"
      if [[ $count -gt 0 ]]; then
        echo -e "${YELLOW}    - $locale: $count missing${NC}"
      fi
    done
  fi
  exit 1
fi
