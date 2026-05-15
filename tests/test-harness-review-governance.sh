#!/bin/bash
# Verify harness-review keeps the TeamAgent debate and acceptance-gate contract
# in both the shared skill and shipped mirrors.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

skill_files=(
  "$ROOT_DIR/skills/harness-review/SKILL.md"
  "$ROOT_DIR/codex/.codex/skills/harness-review/SKILL.md"
  "$ROOT_DIR/opencode/skills/harness-review/SKILL.md"
)

reference_files=(
  "$ROOT_DIR/skills/harness-review/references/dual-review.md"
  "$ROOT_DIR/codex/.codex/skills/harness-review/references/dual-review.md"
  "$ROOT_DIR/opencode/skills/harness-review/references/dual-review.md"
)

required_skill_terms=(
  "AskUserQuestion"
  "今までの作業のレビュー"
  "REVIEW_TARGET_ASK"
  "REVIEW_TARGET_AMBIGUOUS"
  "REVIEW_TARGET_CONFIRMED"
  "未コミット変更のみ"
  "直近 1 commit"
  "TeamAgent Debate"
  "明確な合格ライン"
  "仕様正本"
  "Plans.md"
  "デグレ"
  "修正後再レビュー"
  "team_agent_mode"
  "decision_needed"
  "Spec Agent"
  "Plans Agent"
  "Regression Agent"
  "Skeptic Agent"
)

required_reference_terms=(
  "TeamAgent Debate"
  "合格ライン"
  "仕様正本"
  "Plans.md"
  "デグレ"
  "acceptance_bar"
  "team_debate"
  "manual-pass"
)

failures=0

check_file_contains() {
  local file="$1"
  local term="$2"

  if ! grep -Fq "$term" "$file"; then
    echo "missing required term in ${file#$ROOT_DIR/}: $term" >&2
    failures=$((failures + 1))
  fi
}

for file in "${skill_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "missing skill file: ${file#$ROOT_DIR/}" >&2
    failures=$((failures + 1))
    continue
  fi

  for term in "${required_skill_terms[@]}"; do
    check_file_contains "$file" "$term"
  done

  if ! grep -Eq '^allowed-tools: .*AskUserQuestion' "$file"; then
    echo "AskUserQuestion is not exposed in allowed-tools: ${file#$ROOT_DIR/}" >&2
    failures=$((failures + 1))
  fi
done

for file in "${reference_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "missing reference file: ${file#$ROOT_DIR/}" >&2
    failures=$((failures + 1))
    continue
  fi

  for term in "${required_reference_terms[@]}"; do
    check_file_contains "$file" "$term"
  done
done

if ! diff -qr --exclude='.DS_Store' "$ROOT_DIR/skills/harness-review" "$ROOT_DIR/codex/.codex/skills/harness-review" >/dev/null; then
  echo "codex harness-review mirror drifted from skills/ SSOT" >&2
  failures=$((failures + 1))
fi

if ! diff -qr --exclude='.DS_Store' "$ROOT_DIR/skills/harness-review" "$ROOT_DIR/opencode/skills/harness-review" >/dev/null; then
  echo "opencode harness-review mirror drifted from skills/ SSOT" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "test-harness-review-governance: ok"
