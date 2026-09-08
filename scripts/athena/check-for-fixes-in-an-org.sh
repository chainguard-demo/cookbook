#!/usr/bin/env bash
set -euo pipefail

# Usage: ./osv-fixes.sh <parent> [output.csv]
PARENT="${1:?usage: $0 <parent> [output.csv]}"
OUTFILE="${2:-fixes.csv}"

TOKEN=""
PAGE=0

{
  while :; do
    PAGE=$((PAGE+1))

    ARGS=(uploads osv list --parent "$PARENT" -o json)
    [ -n "$TOKEN" ] && ARGS+=(--page-token "$TOKEN")

    RESP=$(chainctl "${ARGS[@]}")

    echo "$RESP" | jq -r '
      .vulns[]
      | ([.affected[]?.database_specific?.chainguard?.fixed_artifacts[]? | .purl // empty] | unique) as $purls
      | select($purls | length > 0)
      | [.id, ($purls | join(","))]
      | @csv'

    TOKEN=$(echo "$RESP" | jq -r '.next_page_token // ""')
    echo "page $PAGE done, next token: ${TOKEN:0:20}" >&2

    [ -z "$TOKEN" ] && break
  done
} > "$OUTFILE"

echo "wrote $(wc -l < "$OUTFILE") rows to $OUTFILE" >&2
