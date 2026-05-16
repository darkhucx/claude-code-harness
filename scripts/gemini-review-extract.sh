#!/bin/bash
# gemini-review-extract.sh
# Gemini adversarial-review の result JSON から review-output.schema.json 準拠の
# 構造化 review JSON を取り出す。background モードでは plugin が schema 出力を
# rawOutput に markdown fence 付きで埋め込むため、剥ぎ取って write-review-result.sh
# が読める形式に正規化する。
#
# Usage:
#   bash scripts/gemini-companion.sh result <job-id> --json > /tmp/gemini-raw.json
#   bash scripts/gemini-review-extract.sh /tmp/gemini-raw.json > /tmp/gemini-clean.json
#   bash scripts/write-review-result.sh /tmp/gemini-clean.json

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

INPUT="${1:-}"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "Usage: scripts/gemini-review-extract.sh <gemini-result-json-file>" >&2
  exit 1
fi

# 入力が既に schema 形式なら（verdict 字段あり）そのまま通す
if jq -e 'has("verdict") and has("findings")' "$INPUT" >/dev/null 2>&1; then
  cat "$INPUT"
  exit 0
fi

# Gemini companion の result JSON から rawOutput を取り出す
RAW=$(jq -r '.result.rawOutput // .rawOutput // empty' "$INPUT")
if [ -z "$RAW" ]; then
  echo "ERROR: rawOutput field not found in $INPUT" >&2
  exit 3
fi

# rawOutput 内の ```json ... ``` fence を剥ぐ
# Gemini は時々 CR (`\r`) や末尾空白を付けるため、事前に tr で CR を落とし
# awk 側では `[[:space:]]*` で末尾空白を許容する (fence なしで plain JSON が
# 入っているケースにも対応)。
EXTRACTED=$(printf '%s' "$RAW" | tr -d '\r' | awk '
  /^```json[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { in_block=0; exit }
  in_block { print }
')

# fence が見つからなかった場合は raw そのものが JSON の可能性を試す
if [ -z "$EXTRACTED" ]; then
  EXTRACTED="$RAW"
fi

# 妥当な JSON であることを確認
if ! echo "$EXTRACTED" | jq -e '.' >/dev/null 2>&1; then
  echo "ERROR: extracted content is not valid JSON" >&2
  echo "--- raw content ---" >&2
  echo "$RAW" >&2
  exit 4
fi

# findings[] の schema 準拠率は Gemini の出力ばらつきで低くなる。
# write-review-result.sh が severity / title / body を期待するため、
# 欠落している場合は安全側 (severity: medium, title: finding の冒頭) で埋める。
echo "$EXTRACTED" | jq '
  def normalize_finding(f):
    f
    | .severity = (.severity // "medium")
    | .title = (.title // .finding // .body // "untitled finding")
    | .body = (.body // .finding // .title // "");
  .findings = ((.findings // []) | map(normalize_finding(.)))
'
