#!/usr/bin/env bash
set -euo pipefail

# Usage: ./osv-fixes.sh <parent> [output.csv] [unfixed.csv] [fixes.json]
PARENT="${1:?usage: $0 <parent> [output.csv] [unfixed.csv] [fixes.json]}"
OUTFILE="${2:-fixes.csv}"
UNFIXED_FILE="${3:-unfixed.csv}"
JSON_FILE="${4:-fixes.json}"

TOKEN=""
PAGE=0
JSON_TMP=$(mktemp)
trap 'rm -f "$JSON_TMP"' EXIT

# Start fresh since we append per page
: > "$OUTFILE"
: > "$UNFIXED_FILE"

while :; do
  PAGE=$((PAGE+1))

  ARGS=(uploads osv list --parent "$PARENT" -o json)
  [ -n "$TOKEN" ] && ARGS+=(--page-token "$TOKEN")

  RESP=$(chainctl "${ARGS[@]}")

  # Vulns with at least one fixed artifact -> CSV
  echo "$RESP" | jq -r '
    .vulns[]
    | ([.affected[]?.database_specific?.chainguard?.fixed_artifacts[]? | .purl // empty] | unique) as $purls
    | select($purls | length > 0)
    | [.id, ($purls | join(","))]
    | @csv' >> "$OUTFILE"

  # Same vulns, full JSON objects -> one per line (NDJSON) into temp file
  echo "$RESP" | jq -c '
    .vulns[]
    | select(([.affected[]?.database_specific?.chainguard?.fixed_artifacts[]? | .purl // empty] | length) > 0)' >> "$JSON_TMP"

  # Vulns with no fixed artifacts anywhere
  echo "$RESP" | jq -r '
    .vulns[]
    | ([.affected[]?.database_specific?.chainguard?.fixed_artifacts[]? | .purl // empty] | unique) as $purls
    | select($purls | length == 0)
    | [.id]
    | @csv' >> "$UNFIXED_FILE"

  TOKEN=$(echo "$RESP" | jq -r '.next_page_token // ""')
  echo "page $PAGE done, next token: ${TOKEN:0:20}" >&2

  [ -z "$TOKEN" ] && break
done

# Combine the NDJSON lines into a single JSON array
jq -s '.' "$JSON_TMP" > "$JSON_FILE"

echo "wrote $(wc -l < "$OUTFILE") rows to $OUTFILE" >&2
echo "wrote $(wc -l < "$UNFIXED_FILE") rows to $UNFIXED_FILE" >&2
echo "wrote $(jq 'length' "$JSON_FILE") entries to $JSON_FILE" >&2
