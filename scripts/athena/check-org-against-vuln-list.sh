#!/usr/bin/env bash
set -euo pipefail

# Usage: ./check-org-against-vuln-list.sh <parent> <cgp-list.txt>
PARENT="${1:?usage: $0 <parent> <cgp-list.txt>}"
CGP_FILE="${2:?usage: $0 <parent> <cgp-list.txt>}"

VULNS_TMP=$(mktemp)
trap 'rm -f "$VULNS_TMP"' EXIT

TOKEN=""
PAGE=0

# Fetch every page once, store all vulns as NDJSON
while :; do
  PAGE=$((PAGE+1))

  ARGS=(uploads osv list --parent "$PARENT" -o json)
  [ -n "$TOKEN" ] && ARGS+=(--page-token "$TOKEN")

  RESP=$(chainctl "${ARGS[@]}")

  echo "$RESP" | jq -c '.vulns[]' >> "$VULNS_TMP"

  TOKEN=$(echo "$RESP" | jq -r '.next_page_token // ""')
  echo "page $PAGE done, next token: ${TOKEN:0:20}" >&2

  [ -z "$TOKEN" ] && break
done

IGNORED=0

# Go through the CGP list one line at a time
while IFS= read -r CGP || [ -n "$CGP" ]; do
  
  echo "Checking $CGP"

  # Skip blank lines / trim whitespace
  CGP=$(echo "$CGP" | tr -d '[:space:]')
  [ -z "$CGP" ] && continue

  # Pull the matching vuln (empty if not found)
  MATCH=$(jq -c --arg id "$CGP" 'select(.id == $id)' "$VULNS_TMP")

  if [ -z "$MATCH" ]; then
    IGNORED=$((IGNORED+1))
    continue
  else
    echo "Match: $CGP"
  fi
  
  echo "$MATCH" | jq -r '
  ([.affected[]?.database_specific?.chainguard?.fixed_artifacts[]? | .purl // empty] | unique) as $purls
  | ([.affected[]?.versions[]? | select(. != null)] | unique) as $versions
  | select($purls | length > 0)
  | [.id, ($purls | join(",")), ($versions | join(","))]
  | @csv'

done < "$CGP_FILE"

echo "ignored $IGNORED CGP ids not found in chainctl output" >&2
