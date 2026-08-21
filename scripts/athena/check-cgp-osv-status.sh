#!/bin/bash

INPUT_FILE="${1:-chainguard-advisories.json}"
TOKEN="$(chainctl auth token)"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: input file '$INPUT_FILE' not found." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

: "${CONSOLE_API_OSV_VULNS_QUERY:?Set CONSOLE_API_OSV_VULNS_QUERY, e.g. https://console-api.enforce.dev/osv/v1/vulns}"

cgp_ids=$(jq -r '.cgps[]' "$INPUT_FILE")

while IFS= read -r cgp_id; do
  [ -z "$cgp_id" ] && continue

  url="${CONSOLE_API_OSV_VULNS_QUERY}/${cgp_id}"
  QUERYJSON=$(curl -s "$url" \
       -H "Authorization: Bearer $TOKEN" \
       -H 'Content-Type: application/json')

  # echo "$QUERYJSON" | jq .

  # An advisory can affect multiple packages/ranges, so pull each
  # package name + its fixed version as a tab-separated pair.
  fixes=$(echo "$QUERYJSON" | jq -r '
    .affected[]? as $a
    | $a.ranges[]?.events[]?
    | select(has("fixed"))
    | "\($a.package.name)\t\(.fixed)"
  ')

  if [ -n "$fixes" ]; then
    while IFS=$'\t' read -r pkg fixed_version; do
      echo "Fix available for $cgp_id ($pkg): update to $fixed_version"
    done <<< "$fixes"
  else
    # echo "Advisory $cgp_id: no fix version found"
    continue
  fi

done <<< "$cgp_ids"
