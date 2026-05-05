#!/bin/bash
# Validate Harness skill orchestration metadata.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MANIFEST_JSON="${TMP_DIR}/skill-manifest.json"
(cd "$ROOT_DIR" && bash scripts/generate-skill-manifest.sh --output "$MANIFEST_JSON" >/dev/null)

node - "$MANIFEST_JSON" <<'NODE'
const fs = require('fs');

const manifestPath = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

const coreSkills = new Set([
  'harness-plan',
  'harness-work',
  'harness-review',
  'harness-loop',
  'breezing',
  'harness-sync',
  'harness-setup',
  'harness-release',
  'harness-release-internal',
]);

const requiredFields = ['kind', 'purpose', 'trigger', 'shape', 'role', 'owner', 'since'];
const knownNames = new Set(manifest.skills.map((skill) => skill.name));
const errors = [];

for (const skill of manifest.skills) {
  if (!coreSkills.has(skill.name)) continue;

  for (const field of requiredFields) {
    if (skill[field] === null || skill[field] === '') {
      errors.push(`${skill.path}: missing design metadata field: ${field}`);
    }
  }

  if ((skill.base !== null && !knownNames.has(skill.base)) || (skill.pair !== null && !knownNames.has(skill.pair))) {
    if (skill.base !== null && !knownNames.has(skill.base)) {
      errors.push(`${skill.path}: base references unknown skill: ${skill.base}`);
    }
    if (skill.pair !== null && !knownNames.has(skill.pair)) {
      errors.push(`${skill.path}: pair references unknown skill: ${skill.pair}`);
    }
  }

  if (skill.shape === 'wrap' && (skill.base === null || skill.base === '')) {
    errors.push(`${skill.path}: shape=wrap requires base`);
  }

  if (skill.role === 'evaluator') {
    const mutating = (skill.allowed_tools || []).filter((tool) =>
      ['Write', 'Edit', 'Append', 'NotebookEdit', 'spawn_agent', 'send_input'].includes(tool)
    );
    if (mutating.length > 0) {
      errors.push(`${skill.path}: evaluator role allows mutating tools: ${mutating.join(', ')}`);
    }
    if (skill.context !== 'fork') {
      errors.push(`${skill.path}: evaluator role must use context: fork`);
    }
  }
}

if (errors.length > 0) {
  console.error('Skill design contract violations:');
  for (const error of errors) {
    console.error(`  - ${error}`);
  }
  process.exit(1);
}
NODE

echo "test-skill-design-contract: ok"
