#!/bin/bash
set -euo pipefail

# Required env vars:
#   token
#   artifactory_url
#   repo

if [ -z "${token:-}" ] || [ -z "${artifactory_url:-}" ] || [ -z "${repo:-}" ]; then
  echo "Error: 'token', 'artifactory_url', and 'repo' must be set."
  exit 1
fi

DAYS="${DAYS:-180}"
BASE_PATH="${BASE_PATH:-org/springframework}"
LIMIT="${LIMIT:-10000}"

aql_post() {
  curl -sS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: text/plain" \
    "$artifactory_url/api/search/aql" \
    --data "$1"
}

AQL_QUERY="
items.find({
  \"repo\": {\"\$eq\": \"$repo\"},
  \"type\": {\"\$eq\": \"file\"},
  \"path\": {\"\$match\": \"$BASE_PATH/*/*\"},
  \"name\": {\"\$match\": \"*.jar\"}
}).include(\"name\", \"repo\", \"path\", \"stat.downloads\", \"stat.downloaded\")
 .sort({\"\$desc\": [\"stat.downloads\"]})
 .limit($LIMIT)
"

output="$(aql_post "$AQL_QUERY")"

csv_file="$(mktemp --suffix=.csv)"
echo "groupId,artifactId,version,downloads,downloaded" > "$csv_file"

base_depth="$(awk -F'/' '{print NF}' <<<"$BASE_PATH")"

echo "$output" | jq -r \
  --arg base "$BASE_PATH" \
  --argjson depth "$base_depth" \
  --argjson days "$DAYS" '
  [ .results[]
    | select(.path | startswith($base + "/"))
    | (.stats[0]? // {}) as $s
    | ($s.downloads // 0) as $downloads
    | ($s.downloaded // null) as $downloaded
    | select($downloaded != null)
    | select(
        (now - (
          $downloaded
          | sub("\\.[0-9]+Z$"; "Z")
          | fromdateiso8601
        )) <= ($days * 24 * 60 * 60)
      )
    | (.path | split("/")) as $p
    | {
        groupId: ($base | gsub("/"; ".")),
        artifactId: $p[$depth],
        version: $p[$depth + 1],
        downloads: $downloads,
        downloaded: $downloaded
      }
  ]
  | sort_by(.groupId,.artifactId,.version)
  | group_by([.groupId,.artifactId,.version])
  | map({
      groupId: .[0].groupId,
      artifactId: .[0].artifactId,
      version: .[0].version,
      downloads: (map(.downloads) | add),
      downloaded: (map(.downloaded) | max)
    })
  | sort_by(-.downloads)
  | .[]
  | "\(.groupId),\(.artifactId),\(.version),\(.downloads),\(.downloaded)"
' >> "$csv_file"

echo "CSV saved to: $csv_file"
